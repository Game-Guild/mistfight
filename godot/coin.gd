extends RigidBody2D

# The coin.
#
# The coin drives itself. Godot's rigid body solver never moves it: the node
# stays a RigidBody2D so the scene, its mass, and the push signal connection
# all keep working, but it is frozen in kinematic mode from _ready() onward,
# which tells the solver to keep its hands off. Every pixel the coin travels is
# moved by the code below.
#
# Why, in one paragraph. A solver figures out collisions by comparing where
# things are at the start and end of a tick. A steelpush pushes a 0.03 kg coin
# at roughly 6.6 million pixels per second squared, which at 240 ticks a second
# means the coin can cross 400+ pixels between one snapshot and the next -- so
# a wall it should have hit is in neither snapshot, and it sails through. That
# is not a Godot flaw, it is what discrete-time simulation is, and it is why no
# engine simulates bullets as rigid bodies. The standard answer everywhere is
# to sweep: each tick, drag the shape along the whole line it means to travel
# and stop it at the first thing in the way. move_and_collide() does exactly
# that, and it behaves the same at 5 pixels a second as at 90,000.
#
# Measured on 2026-08-02, the failures this replaces: contact reporting that
# read zero contacts for three ticks running while the coin sat inside the
# floor; position moving 15 pixels on a tick where velocity claimed a quarter
# of a pixel; and a coin leaving at 7,800 px/s in a direction the push never
# pointed. Godot's CCD does not cover this either -- Cast Ray only stops the
# skip-over, and Cast Shape is a known open engine bug in 2D
# (godotengine/godot#72674) that does nothing at all.
#
# What this gives up: Godot no longer resolves coin-versus-coin contact, so a
# pile of coins resting on each other is not modelled. Nothing in the game has
# more than one coin yet. The Python sim in sim/ has never modelled coin
# rotation either, so no tumbling behaviour is being lost here that existed
# anywhere else.


# --- Tunable numbers ---------------------------------------------------------

# Coulomb friction, taken from sim/bodies.py line 15 rather than picked here.
# 0.6 static is the number behind this project's stated critical Coinshot angle.
#
# Getting that angle the right way round matters, because there are two ways to
# measure it and they are not the same number:
#
#   measured from the surface's NORMAL (the direction sticking straight out of
#   it): grip holds while tan(angle) <= 0.6, so up to 31 degrees.
#   measured from the SURFACE ITSELF (lying flat along it): the same limit is
#   59 degrees, because 90 - 31 = 59. This is the "critical Coinshot angle"
#   written down in the project's canon notes as tan(theta) = 1 / 0.6.
#
# Both describe the same rule. Push steeply into a surface and the coin grips.
# Push at a glancing angle and it skids away. The changeover is 31 degrees off
# straight-on, which is a good deal narrower than "59 degrees" makes it sound.
const FRICTION_STATIC = 0.6
const FRICTION_KINETIC = 0.4

# How bouncy an impact is, from 0 (stops dead, all the energy gone) to 1
# (perfectly elastic, bounces back as fast as it arrived). Left at 0 on purpose
# so this change does not quietly alter how the coin behaves: main.tscn's
# physics material never set a bounce value either, so zero is what the coin
# has always done. Raise it if a skittering coin turns out to feel better.
const BOUNCE = 0.0

# How far ahead of the coin to look for something solid when deciding whether a
# push is being blocked. The coin's collision box is 1x3 px, so its centre sits
# about 2 px from its bottom edge; 6 px reaches past that with margin and is
# short enough to only ever find a surface it is genuinely touching.
const CONTACT_PROBE_DISTANCE_PX = 6.0

# Below this sliding speed the coin counts as sitting still, which is what lets
# static grip take hold. sim/world.py makes the same test with its own
# STATIC_SPEED_EPSILON_M_PER_S; this is that idea in pixels, loose enough to
# survive the small numerical jitter any resting body has.
const RESTING_SPEED_PX_PER_S = 1.0

# How many times in one tick the coin is allowed to hit something, redirect,
# and keep going with whatever travel it had left. Without this a coin wedged
# in a corner could ping between two walls forever inside a single tick. Four
# is enough for a corner plus slack, and cheap.
const MAX_SWEEP_STEPS = 4

# How many points of flight path the yellow trail keeps. A coin moving at
# bullet speed covers most of a screen in a couple of frames, so a few hundred
# points is already a longer trail than fits on screen, and keeping more only
# costs performance nobody sees. See _process() for why an uncapped trail is
# actively harmful rather than merely wasteful.
const MAX_TRACE_POINTS = 300


# --- State -------------------------------------------------------------------

# The coin's own velocity, in pixels per second. This replaces the RigidBody2D
# property linear_velocity, which is inert while the body is frozen. Anything
# that used to read coin.linear_velocity should read coin.velocity now.
var velocity: Vector2 = Vector2.ZERO

# True while the coin is riding along on the player, not yet released. While
# this is set, player.gd owns the coin's position and nothing here moves it.
# This replaces the old use of the `freeze` flag to mean "carried" -- freeze
# now means "the solver does not move this body", which is true permanently.
var is_carried: bool = true

var debug_log: FileAccess


func _ready() -> void:
	debug_log = FileAccess.open("res://coin_debug.log", FileAccess.WRITE)
	# Hand the body to ourselves, permanently. FREEZE_MODE_KINEMATIC means the
	# body still exists to the physics world -- other things collide with it,
	# rays find it -- but the solver never integrates it or moves it. Setting
	# this in code rather than in main.tscn keeps the reason next to the
	# explanation of why.
	freeze = true
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC


func release() -> void:
	# Called when the player lets go of the coin, so it starts obeying gravity
	# and pushes instead of riding along.
	is_carried = false


func recall() -> void:
	# Snap the coin back into the player's hand from wherever it ended up.
	#
	# This is a TESTING AFFORDANCE, not a designed mechanic, and it should not
	# survive into anything anyone plays. There is exactly one coin in the
	# scene and no way to pick it up, so without this you get one throw per
	# launch of the game. Real coin handling -- a supply you carry, spend, and
	# retrieve -- is issue #5, and this is a placeholder standing where that
	# will go.
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
			# Drop the oldest point so the trail is a moving window over the
			# recent path rather than the entire history. Without this the array
			# grows without limit, and since the whole thing is copied out and
			# back every single frame, the cost of drawing it climbs with its
			# own length. Measured 2026-08-02: an uncapped trail stalled a
			# 40-second headless run so badly it had to be killed, while the
			# same run with a short flight finished in 3 seconds.
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
	# move_and_collide() only reports. It stopped the coin at the surface and
	# handed back the facts; deciding what the impact MEANS is this function's
	# job and nothing else does it.
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

	# Tell whatever got hit that it got hit. Nothing implements this yet -- no
	# health system exists -- so this is the single door for damage, breaking,
	# and knocking things over to come through later, rather than the coin
	# growing a list of special cases for each kind of target.
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
# Two cases.
#
# NOT PRESSED AGAINST ANYTHING: the whole push becomes acceleration. The coin
# flies, and the sweep above makes sure it cannot pass through anything on the
# way, however fast it goes.
#
# PRESSED AGAINST SOMETHING SOLID: the push gets split against that surface.
#   - the part aimed INTO the surface is dropped. Solid ground cancels it, which
#     is what solid ground does.
#   - the part aimed ALONG the surface is kept, less friction. That is the coin
#     skidding, and it is wanted: a push at a shallow angle should shove a coin
#     sideways, which is what makes a tripod of coins mean anything.
# Whether it grips or skids is sim/world.py's rule (lines 93-109): static grip
# holds while the sideways force stays under friction_static * normal_force,
# and past that the coin breaks loose and only weaker kinetic friction resists.
# The normal force includes the push itself, so a coin pressed harder grips
# harder.
#
# The player's half of the force pair is untouched by any of this. It is worked
# out separately in player_states/coin_shoot_state.gd and never passes through
# here, so a coin pinned against the ground still throws the player the full
# launch -- exactly what sim/steelpush.py describes: "a coin pinned against the
# ground cannot move, so the pusher takes the full launch."

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
	# We ask the physics world ourselves with a ray rather than reading Godot's
	# own contact report, because that report was measured on 2026-08-02 to be
	# untrustworthy under a push this size: it read zero contacts for three
	# ticks running while the coin was demonstrably inside the floor. A ray is a
	# direct geometric question with a direct answer.
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
