extends RigidBody2D
@export var SPEED = 0
var debug_log: FileAccess

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	debug_log = FileAccess.open("res://coin_debug.log", FileAccess.WRITE)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if freeze:
		# Still riding along, not fired yet -- keep the trace empty.
		$"../TrajectoryTrace".points = PackedVector2Array()
	else:
		# In flight -- append this frame's position so the trace grows into
		# the path actually flown, even though the coin itself moves too
		# fast this tick to see clearly on its own.
		# NOTE: "points" is a PackedVector2Array. Reading it through the
		# property getter hands back a COPY, not the live array -- calling
		# .append() straight on $Node.points silently mutates a throwaway
		# copy and never touches the real property. Has to be copied out,
		# appended to, then assigned back.
		var trace_points: PackedVector2Array = $"../TrajectoryTrace".points
		trace_points.append(global_position)
		$"../TrajectoryTrace".points = trace_points

# Hard ceiling on the coin's speed, applied unconditionally (in flight or in
# contact), worked out 2026-08-01 at the same safety margin used for the
# in-contact cap below: 15px of travel per physics tick at the project's
# current 240 ticks/second, which stays comfortably under a ~50px wall.
# This costs the "flies away bullet-fast" flavor entirely -- confirmed
# tonight that the push force, applied honestly, produces real bullet-range
# speeds (Mach 2+), and no engine resolves a wall collision correctly for
# something moving that fast in a single tick. Correctness came first.
const MAX_SPEED_PX_PER_S = 12000.0


func _on_character_body_2d_push(angle: float, force: float) -> void:
	var coin_push = Vector2.from_angle(angle)*force
	# Applied directly to linear_velocity and capped here, synchronously,
	# instead of routed through apply_central_force. apply_central_force
	# queues the force for Godot's own next internal integration step --
	# confirmed 2026-08-01 that there's a one-tick lag between when a force
	# is queued that way and when _integrate_forces() can see and clip its
	# effect, meaning Godot's own solver was resolving collisions using the
	# raw, uncapped velocity a full tick before any of this script's
	# clipping ever ran. Setting velocity here, in the same call that
	# receives the push, closes that gap -- there's no queue left for the
	# solver to read an uncapped number from.
	linear_velocity += coin_push / mass * get_physics_process_delta_time()
	if linear_velocity.length() > MAX_SPEED_PX_PER_S:
		linear_velocity = linear_velocity.normalized() * MAX_SPEED_PX_PER_S
	debug_log.store_line("[coin push received] angle=" + str(angle) + " force=" + str(force) + " coin_push=" + str(coin_push) + " my_global_pos=" + str(global_position) + " my_linear_velocity=" + str(linear_velocity) + " my_mass=" + str(mass))


# In-contact sliding speed limit (px/s), worked out 2026-08-01: physics runs
# at 60 ticks/second, so at this speed the coin covers 900/60 = 15px per
# tick while touching something -- comfortably under even a thin (~50px)
# wall, with room to spare. Free-flight speed (no contact) is NOT capped --
# a shot coin should still fly as fast as the push formula says. This limit
# only ever applies while something is actually touching the coin.
const MAX_TANGENTIAL_CONTACT_SPEED_PX_PER_S = 900.0


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Diagnostic only, added 2026-08-01 to check whether contact reporting
	# is flickering tick-to-tick under heavy push force (the working theory
	# for why the coin still covers huge distance in single ticks despite
	# the clipping below). Logs every tick the coin is in flight, so this is
	# meant for a single short test run, not left on indefinitely.
	var velocity_before_clipping: Vector2 = state.linear_velocity
	var contact_count: int = state.get_contact_count()
	if not freeze:
		debug_log.store_line("[integrate_forces] contact_count=" + str(contact_count) + " velocity_before_clip=" + str(velocity_before_clipping) + " position=" + str(global_position))

	# A real collision cancels the part of an object's velocity that's
	# driving it INTO whatever it's touching -- that's the whole job of a
	# contact response, same thing sim/world.py's ground contact does by
	# zeroing velocity.y the instant it would cross the floor. Godot's own
	# solver tries to do the same thing, but under a force this large it can
	# lose that fight within one physics step. This does the cancellation
	# directly and exactly, every tick there's contact, instead of trusting
	# the solver to arrive there smoothly on its own.
	for contact_index in range(contact_count):
		var surface_normal: Vector2 = state.get_contact_local_normal(contact_index)

		# Godot's contact normal points AWAY from the surface, toward this
		# body -- moving INTO the surface means a NEGATIVE dot product with
		# it. Positive (or zero) means already separating, leave it alone.
		var velocity_into_surface: float = state.linear_velocity.dot(surface_normal)
		if velocity_into_surface < 0.0:
			state.linear_velocity -= surface_normal * velocity_into_surface

		# Friction's strength scales with how hard the two surfaces are
		# pressed together (the normal force). While our push is still
		# fighting to hold the coin against this surface, that pressing
		# force stays enormous, so the friction response computed off it can
		# overshoot into a huge sideways kick -- the same instability as
		# above, just along the surface instead of into it. Cap the sliding
		# speed directly rather than trust the solver's friction response to
		# stay sane under a force this size.
		var velocity_along_surface: Vector2 = state.linear_velocity - surface_normal * state.linear_velocity.dot(surface_normal)
		var sliding_speed: float = velocity_along_surface.length()
		if sliding_speed > MAX_TANGENTIAL_CONTACT_SPEED_PX_PER_S:
			var velocity_perpendicular_to_surface: Vector2 = state.linear_velocity - velocity_along_surface
			state.linear_velocity = velocity_perpendicular_to_surface + velocity_along_surface.normalized() * MAX_TANGENTIAL_CONTACT_SPEED_PX_PER_S

		# Confirmed 2026-08-01: clipping velocity alone isn't enough. Logs
		# showed the coin's POSITION jumping hundreds of pixels in a tick
		# where velocity was reported as only a few px/s the whole time --
		# meaning Godot's own contact resolution moves position directly
		# through some channel that never shows up in linear_velocity (several
		# physics engines do this on purpose, so a big correction doesn't look
		# like added kinetic energy in the velocity readout). Push the coin's
		# center back onto the correct side of the contact plane directly --
		# the same job sim/world.py's floor clamp does, generalized to
		# whatever surface and angle THIS contact's normal says instead of
		# assuming "down", and done as a real position write since velocity
		# clearly isn't the channel Godot's own correction uses either.
		# Treating the coin as a point is a fair approximation -- its real
		# shape is a tiny 1x3px rectangle.
		var contact_point: Vector2 = state.get_contact_local_position(contact_index)
		var offset_from_contact_point: Vector2 = state.transform.origin - contact_point
		var distance_behind_contact_plane: float = offset_from_contact_point.dot(surface_normal)
		if distance_behind_contact_plane < 0.0:
			# Transform2D is a value type -- reading state.transform.origin and
			# writing straight back to it would silently edit a throwaway copy,
			# same trap as the PackedVector2Array note in _process() above. Has
			# to be copied out, changed, assigned back.
			var corrected_transform: Transform2D = state.transform
			corrected_transform.origin -= surface_normal * distance_behind_contact_plane
			state.transform = corrected_transform

	if not freeze:
		debug_log.store_line("[integrate_forces] velocity_after_clip=" + str(state.linear_velocity))
