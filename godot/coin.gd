extends RigidBody2D

# The coin moves itself. It stays a RigidBody2D node so the scene keeps its
# mass and signal wiring, but it is frozen kinematic, so Godot's solver never
# touches it -- every pixel it travels is moved by the code below.
#
# A solver decides collisions from where a body is at the start and end of a
# tick. A steelpush accelerates this 0.03 kg coin at ~6.6 million px/s^2, fast
# enough to cross hundreds of pixels between those two snapshots, so a wall it
# should have hit appears in neither and it passes through. Instead the coin is
# swept: move_and_collide() drags its shape along the entire path it means to
# travel and stops it at the first thing in the way. That behaves identically
# at any speed.
#
# Trade-off: Godot no longer resolves coin-against-coin contact, so a pile of
# coins is not modelled. The sim has never modelled coin rotation either.


# --- Tunable numbers ---------------------------------------------------------

# Coulomb friction, matching sim/bodies.py. Push within 31 degrees of a
# surface's normal and the coin grips; anything shallower skids it. That is the
# project's critical Coinshot angle, which is the same limit measured from the
# surface instead of its normal: 90 - 31 = 59 degrees.
const FRICTION_STATIC = 0.6
const FRICTION_KINETIC = 0.4

# How bouncy an impact is: 0 stops dead, 1 rebounds as fast as it arrived.
const BOUNCE = 0.0

# How far ahead to look for something solid when deciding whether a push is
# blocked. The coin's box is 1x3 px, so its centre sits ~2 px from its edge; 6
# px clears that and is short enough to only find surfaces it is touching.
const CONTACT_PROBE_DISTANCE_PX = 6.0

# Below this sliding speed the coin counts as sitting still, so static grip can
# take hold. Same test as sim/world.py's STATIC_SPEED_EPSILON_M_PER_S.
const RESTING_SPEED_PX_PER_S = 1.0

# How many times in one tick the coin may hit something, redirect, and carry on
# with its leftover travel. Caps a coin wedged in a corner from looping forever.
const MAX_SWEEP_STEPS = 4

# How many points of flight path the yellow trail keeps. The whole array is
# copied every frame, so an uncapped trail gets slower the longer it gets.
const MAX_TRACE_POINTS = 300


# --- State -------------------------------------------------------------------

# The coin's velocity in pixels per second. Used instead of the RigidBody2D
# property linear_velocity, which is inert while the body is frozen.
var velocity: Vector2 = Vector2.ZERO

# True while the coin is riding on the player. player.gd owns its position for
# as long as this is set, and nothing in this file moves it.
var is_carried: bool = true

var debug_log: FileAccess


func _ready() -> void:
	debug_log = FileAccess.open("res://coin_debug.log", FileAccess.WRITE)
	# FREEZE_MODE_KINEMATIC leaves the body present to the physics world --
	# things still collide with it and rays still find it -- but the solver
	# never integrates or moves it.
	freeze = true
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC


func release() -> void:
	# Called when the player lets go of the coin, so it starts obeying gravity
	# and pushes instead of riding along.
	is_carried = false


func recall() -> void:
	# Snap the coin back to the player's hand from wherever it ended up.
	# Testing affordance, not a mechanic: there is one coin and no way to pick
	# it up. Real coin handling is issue #5.
	is_carried = true
	velocity = Vector2.ZERO
	$"../TrajectoryTrace".points = PackedVector2Array()


func _process(_delta: float) -> void:
	if is_carried:
		# Still riding along on the player -- keep the trace empty.
		$"../TrajectoryTrace".points = PackedVector2Array()
	else:
		# In flight -- append this frame's position so the trace grows into the
		# path actually flown, even though the coin itself moves too fast this
		# tick to see clearly on its own.
		# NOTE: "points" is a PackedVector2Array. Reading it through the
		# property getter hands back a COPY, not the live array -- calling
		# .append() straight on $Node.points silently mutates a throwaway copy
		# and never touches the real property. It has to be copied out,
		# appended to, then assigned back.
		var trace_points: PackedVector2Array = $"../TrajectoryTrace".points
		trace_points.append(global_position)
		if trace_points.size() > MAX_TRACE_POINTS:
			# Drop the oldest point, making the trail a moving window over the
			# recent path rather than the whole history.
			trace_points.remove_at(0)
		$"../TrajectoryTrace".points = trace_points


func _physics_process(delta: float) -> void:
	if is_carried:
		return
	# Gravity, then move. Any steelpush force arriving this tick has already
	# been folded into velocity by _on_character_body_2d_push below, which runs
	# from the player's own _physics_process.
	velocity += get_gravity() * delta
	_move_by_sweeping(delta)


func _move_by_sweeping(delta: float) -> void:
	# How far the coin means to travel this tick. move_and_collide() wants a
	# distance, not a speed, so the per-second velocity is scaled by how long
	# this tick lasted.
	var travel_remaining: Vector2 = velocity * delta

	for sweep_step in range(MAX_SWEEP_STEPS):
		# Drag the coin's shape along the whole of travel_remaining and stop it
		# at the first thing in the way. Returns null for a clear path.
		var collision: KinematicCollision2D = move_and_collide(travel_remaining)
		if collision == null:
			return

		_respond_to_collision(collision, delta)

		# Whatever travel did not happen because something got in the way. The
		# part of it heading into the surface is gone -- the surface is there --
		# so what is left runs along the surface instead. slide() does exactly
		# that subtraction.
		travel_remaining = collision.get_remainder().slide(collision.get_normal())
		if travel_remaining.length() < 0.01:
			return


func _respond_to_collision(collision: KinematicCollision2D, delta: float) -> void:
	# move_and_collide() only reports: it stopped the coin at the surface and
	# handed back the facts. Deciding what the impact means happens here.
	var surface_normal: Vector2 = collision.get_normal()

	# Split the coin's speed into the part heading into the surface and the
	# part running along it. Godot's normals point back out of a surface, so
	# heading into one means a negative dot product with its normal.
	var speed_into_surface: float = velocity.dot(surface_normal)
	var velocity_along_surface: Vector2 = velocity - surface_normal * speed_into_surface

	if speed_into_surface < 0.0:
		# The impact itself. The into-the-surface speed is removed, and BOUNCE
		# decides how much of it comes back the other way. At BOUNCE = 0 none
		# does, so the coin simply stops dead against the surface and keeps
		# only whatever sideways motion it had.
		velocity = velocity_along_surface - surface_normal * speed_into_surface * BOUNCE
	else:
		velocity = velocity_along_surface

	# Sliding friction. A coin skidding along the ground slows at
	# friction_kinetic * gravity, which famously does not depend on its mass --
	# so this needs no reference to how heavy the coin is.
	var friction_slowdown: float = FRICTION_KINETIC * get_gravity().length() * delta
	var sliding_speed: float = velocity_along_surface.length()
	if sliding_speed <= friction_slowdown:
		# Friction has more than enough bite to stop the skid this tick. Zero it
		# rather than let it reverse, which is what subtracting blindly would do.
		velocity -= velocity_along_surface
	elif sliding_speed > 0.0:
		velocity -= velocity_along_surface.normalized() * friction_slowdown

	# The single door for damage, breaking and knockback to come through, so the
	# coin never grows a list of special cases per target. Nothing implements it
	# yet.
	var thing_hit: Object = collision.get_collider()
	var thing_hit_name: String = "nothing"
	if thing_hit is Node:
		thing_hit_name = thing_hit.name
	if thing_hit != null and thing_hit.has_method("take_coin_hit"):
		thing_hit.take_coin_hit(collision.get_position(), velocity, mass)

	_log("hit " + thing_hit_name
		+ " normal=" + str(surface_normal)
		+ " speed_into_surface=" + str(speed_into_surface))


# --- Receiving a steelpush ----------------------------------------------------
#
# Touching nothing: the whole push becomes acceleration and the coin flies.
#
# Pressed against something solid: the push is split against that surface. The
# part aimed into it is dropped, because solid ground cancels it. The part
# aimed along it is kept, less friction, so a shallow push skids the coin
# sideways. Grip or skid follows sim/world.py: static grip holds while the
# sideways force stays under friction_static * normal_force, and the normal
# force includes the push, so a coin pressed harder grips harder.
#
# The player's half of the force pair never passes through here -- it is worked
# out in coin_shoot_state.gd -- so a pinned coin still throws the player the
# full launch, as sim/steelpush.py describes.

func _on_character_body_2d_push(angle: float, force: float) -> void:
	# `angle` points from the player to this coin, so pushing along it shoves
	# the coin directly away from the player.
	var coin_push: Vector2 = Vector2.from_angle(angle) * force
	var push_delta: float = get_physics_process_delta_time()
	var surface_normal: Vector2 = _find_surface_being_pushed_into(coin_push)

	if surface_normal == Vector2.ZERO:
		_apply_push_force(coin_push, push_delta, "free-flight")
		return

	var push_into_surface: float = coin_push.dot(surface_normal)
	if push_into_surface >= 0.0:
		# Aimed away from the surface it is resting on -- lifting off it, not
		# pressing into it. Nothing is blocked, so nothing is absorbed.
		_apply_push_force(coin_push, push_delta, "lifting-off")
		return

	# How hard the coin is being pressed against the surface. This is the normal
	# force, and it is what friction is measured against: press harder, grip
	# harder.
	var normal_force: float = -push_into_surface
	var push_along_surface: Vector2 = coin_push - surface_normal * push_into_surface

	var velocity_along_surface: Vector2 = velocity - surface_normal * velocity.dot(surface_normal)
	var already_sliding: bool = velocity_along_surface.length() > RESTING_SPEED_PX_PER_S

	if not already_sliding and push_along_surface.length() <= FRICTION_STATIC * normal_force:
		# Static grip holds. sim/world.py: "Static grip holds: the ground
		# cancels the shove." The coin does not move at all this tick.
		velocity -= velocity_along_surface
		_log("push gripped force=" + str(force))
		return

	# Broken loose, or already skidding.
	var slide_force: float = push_along_surface.length() - FRICTION_KINETIC * normal_force
	if slide_force <= 0.0:
		# Friction eats the whole sideways shove; nothing left over to move it.
		velocity -= velocity_along_surface
		_log("push friction-ate-it force=" + str(force))
		return

	_apply_push_force(push_along_surface.normalized() * slide_force, push_delta, "sliding")


func _apply_push_force(push: Vector2, push_delta: float, mode: String) -> void:
	# Newton, one tick at a time: a force on a mass is an acceleration, and an
	# acceleration over a slice of time is a change in speed.
	velocity += push / mass * push_delta
	_log("push " + mode + " push=" + str(push) + " velocity_now=" + str(velocity))


func _find_surface_being_pushed_into(coin_push: Vector2) -> Vector2:
	# Look a short way along the push direction for something solid and report
	# the angle of whatever is found, or Vector2.ZERO for "nothing there".
	#
	# A ray rather than Godot's own contact report, which is unreliable under a
	# push this size -- it reads zero contacts while the coin sits inside a
	# surface. A ray is a direct geometric question with a direct answer.
	if coin_push.length() < 0.0001:
		return Vector2.ZERO
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var probe_end: Vector2 = global_position + coin_push.normalized() * CONTACT_PROBE_DISTANCE_PX
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, probe_end)
	# Without this the ray would immediately hit the coin's own collision box.
	query.exclude = [get_rid()]
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector2.ZERO
	return hit.normal


func _log(what: String) -> void:
	debug_log.store_line("[coin] " + what
		+ " | position=" + str(global_position)
		+ " velocity=" + str(velocity))
