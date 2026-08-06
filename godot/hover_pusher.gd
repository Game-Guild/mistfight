extends CharacterBody2D

# Reproduces notebook 15's Coinshot-hover experiment
# (notebooks/15_the_coinshot_hover.ipynb) inside the engine, using the same
# push formula and constants player.gd already uses for coin-shoot recoil,
# and the same math sim/steelpush.py, sim/air.py, and notebook 15's
# HoverControl class use. The player holds a push against a FIXED anchor
# below them; because the anchor can't move, the full reaction force lands
# on the player instead of the small recoil player.gd's coin-shoot gives.

const SPEED = 300.0
const JUMP_VELOCITY = -400.0

# Same numbers as player.gd (BASE_PUSH_FORCE, MAX_RANGE_M, PIXELS_PER_METER)
# and notebook 15 (PUSH_STRENGTH_N, MAX_RANGE_M, WAX_MASS_KG). They already
# match; that match is what makes this scene a faithful reproduction instead
# of a new experiment. BASE_MASS_KG is no longer a separate copy -- it reads
# player.gd's DEFAULT_MASS_KG directly (issue #21), so the two can't drift
# apart the way a hand-synced pair of consts could.
const BASE_PUSH_FORCE_N = 2000.0
const MAX_RANGE_M = 16.0
const BASE_MASS_KG = Player.DEFAULT_MASS_KG
const PIXELS_PER_METER = 100.0

# Notebook 15 cell 7's HoverControl gains. Stated there as tuning, not
# canon -- only the shape of the controller (pull toward the target height,
# oppose vertical speed, clamp to a finite push) is the thing being tested.
const HEIGHT_GAIN_N_PER_M = 2000.0
const SPEED_GAIN_N_PER_M_PER_S = 2200.0
const MAX_CONTROLLED_STRENGTH_N = 8000.0

# Quadratic air drag, ported from sim/air.py: drag force = -0.5 * air
# density * drag coefficient * cross-section area * speed * velocity. Sphere
# drag coefficient and body radius are sim.Body's defaults -- notebook 15
# never overrode either for Wax, so this doesn't either.
const AIR_DENSITY_KG_PER_M3 = 1.225
const DRAG_COEFFICIENT = 0.47
const BODY_RADIUS_M = 0.3

# Below this speed, treat the player as stopped -- keeps drag and the peak
# finder from doing pointless work on numerical noise.
const STOPPED_SPEED_M_PER_S = 1e-6

enum PushMode { STEADY, ACTIVE_CONTROL }

var push_mode: PushMode = PushMode.STEADY
var air_drag_enabled: bool = false

var gravity_m_per_s2: float
var equilibrium_height_m: float
var predicted_period_s: float
var elapsed_seconds: float = 0.0
var start_position: Vector2

# Rolling 3-sample window for finding local peaks in height, the same
# "higher than both neighbours" test find_peak_indices() uses in notebook
# 15, just run one sample at a time instead of over a whole recorded array.
var recent_heights_m: Array[float] = []
var recent_times_s: Array[float] = []
var last_two_peak_times_s: Array[float] = []
var measured_period_s: float = -1.0


func _ready() -> void:
	start_position = position
	# Read gravity from the engine instead of restating 9.81 -- player.gd's
	# comment already measured this project's gravity to equal 9.81 m/s^2;
	# asking the engine keeps that one fact in one place.
	gravity_m_per_s2 = get_gravity().length() / PIXELS_PER_METER

	# Equilibrium height: where the push exactly cancels gravity. From
	# strength * (1 - d/range) = m*g, solved for d (notebook 15, cell 2).
	var weight_n = BASE_MASS_KG * gravity_m_per_s2
	equilibrium_height_m = MAX_RANGE_M * (1.0 - weight_n / BASE_PUSH_FORCE_N)

	var spring_constant_n_per_m = BASE_PUSH_FORCE_N / MAX_RANGE_M
	predicted_period_s = 2.0 * PI * sqrt(BASE_MASS_KG / spring_constant_n_per_m)

	var anchor: Node2D = $"../Anchor"
	var marker: Line2D = $"../EquilibriumMarker"
	var marker_y = anchor.position.y - equilibrium_height_m * PIXELS_PER_METER
	marker.points = PackedVector2Array([
		Vector2(anchor.position.x - 60, marker_y),
		Vector2(anchor.position.x + 60, marker_y),
	])


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Jumping is the "kick" notebook 15's tests give Wax (kick_m_per_s) --
	# reused as-is rather than scripting a separate kick.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if Input.is_action_just_pressed("toggle_control_mode"):
		push_mode = PushMode.ACTIVE_CONTROL if push_mode == PushMode.STEADY else PushMode.STEADY

	if Input.is_action_just_pressed("toggle_air_drag"):
		air_drag_enabled = not air_drag_enabled

	if Input.is_action_just_pressed("reset_hover"):
		_reset()

	if Input.is_action_pressed("hover_push"):
		_apply_hover_push(delta)
	if air_drag_enabled:
		_apply_air_drag(delta)

	var direction := Input.get_axis("move_left", "move_right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()

	elapsed_seconds += delta
	_update_trace()
	_update_peak_measurement()
	_update_hud()


func _height_above_anchor_m() -> float:
	# Godot's Y axis points down; sim/world.py's Y axis points up (its own
	# top comment: "x is horizontal, y is up"). Converting once here means
	# every formula below reads exactly like the notebook's, with "up"
	# meaning positive, instead of sign flips scattered through the push and
	# controller math.
	var anchor: Node2D = $"../Anchor"
	return (anchor.global_position.y - global_position.y) / PIXELS_PER_METER


func _vertical_speed_m_per_s() -> float:
	return -velocity.y / PIXELS_PER_METER


func _apply_hover_push(delta: float) -> void:
	var anchor: Node2D = $"../Anchor"
	var offset_px: Vector2 = global_position - anchor.global_position
	var distance_m: float = offset_px.length() / PIXELS_PER_METER
	if distance_m >= MAX_RANGE_M or distance_m < STOPPED_SPEED_M_PER_S:
		return
	var direction_away_from_anchor: Vector2 = offset_px.normalized()
	var falloff: float = 1.0 - distance_m / MAX_RANGE_M

	var strength_n: float
	if push_mode == PushMode.STEADY:
		# Notebook 15 cell 3: a constant push, exactly what push.active =
		# true holds. This is the one that bobs forever.
		strength_n = BASE_PUSH_FORCE_N
	else:
		# Notebook 15 cell 7's HoverControl: weight plus a pull toward the
		# target height plus a damping of vertical speed, delivered through
		# the same falloff, clamped to a finite push (steel pushes, never
		# pulls -- same clamp the notebook's controller uses).
		var weight_n = BASE_MASS_KG * gravity_m_per_s2
		var height_error_m = equilibrium_height_m - _height_above_anchor_m()
		var desired_force_n = (weight_n
			+ HEIGHT_GAIN_N_PER_M * height_error_m
			- SPEED_GAIN_N_PER_M_PER_S * _vertical_speed_m_per_s())
		strength_n = clamp(desired_force_n / falloff, 0.0, MAX_CONTROLLED_STRENGTH_N)

	# Same unit convention player.gd's existing recoil formula already uses:
	# convert newtons to this project's pixel-force units, divide by mass,
	# multiply by delta, add straight to velocity -- F = ma, one tick at a
	# time.
	var force_px = strength_n * falloff * PIXELS_PER_METER
	velocity += direction_away_from_anchor * force_px / BASE_MASS_KG * delta


func _apply_air_drag(delta: float) -> void:
	var speed_m_per_s = velocity.length() / PIXELS_PER_METER
	if speed_m_per_s < STOPPED_SPEED_M_PER_S:
		return
	var cross_section_area_m2 = PI * BODY_RADIUS_M * BODY_RADIUS_M
	var drag_force_n = (0.5 * AIR_DENSITY_KG_PER_M3 * DRAG_COEFFICIENT
		* cross_section_area_m2 * speed_m_per_s * speed_m_per_s)
	var drag_force_px = drag_force_n * PIXELS_PER_METER
	velocity += -velocity.normalized() * drag_force_px / BASE_MASS_KG * delta


func _reset() -> void:
	position = start_position
	velocity = Vector2.ZERO
	elapsed_seconds = 0.0
	recent_heights_m.clear()
	recent_times_s.clear()
	last_two_peak_times_s.clear()
	measured_period_s = -1.0
	$"../TrajectoryTrace".points = PackedVector2Array()


func _update_trace() -> void:
	# Same trick coin.gd already uses for the coin's flight trace: points is
	# a PackedVector2Array, and reading it through the property getter hands
	# back a copy, so it has to be copied out, appended to, then assigned
	# back -- appending straight to $Node.points would silently mutate a
	# throwaway copy and never touch the real property.
	var trace: Line2D = $"../TrajectoryTrace"
	var trace_points: PackedVector2Array = trace.points
	trace_points.append(global_position)
	trace.points = trace_points


func _update_peak_measurement() -> void:
	recent_heights_m.append(_height_above_anchor_m())
	recent_times_s.append(elapsed_seconds)
	if recent_heights_m.size() > 3:
		recent_heights_m.pop_front()
		recent_times_s.pop_front()
	if recent_heights_m.size() < 3:
		return
	var higher_than_left = recent_heights_m[1] > recent_heights_m[0]
	var higher_than_right = recent_heights_m[1] > recent_heights_m[2]
	if higher_than_left and higher_than_right:
		last_two_peak_times_s.append(recent_times_s[1])
		if last_two_peak_times_s.size() > 2:
			last_two_peak_times_s.pop_front()
		if last_two_peak_times_s.size() == 2:
			measured_period_s = last_two_peak_times_s[1] - last_two_peak_times_s[0]


func _update_hud() -> void:
	var mode_name = "steady push" if push_mode == PushMode.STEADY else "PD-controlled"
	var drag_text = "on" if air_drag_enabled else "off"
	var period_text = "measured -- s" if measured_period_s < 0.0 else "measured %.2f s" % measured_period_s
	$"../HUD/Readout".text = (
		"t = %.2f s\n" % elapsed_seconds
		+ "height above anchor: %.2f m  (equilibrium %.2f m)\n" % [_height_above_anchor_m(), equilibrium_height_m]
		+ "mode: %s   air drag: %s\n" % [mode_name, drag_text]
		+ "period: predicted %.2f s, %s" % [predicted_period_s, period_text]
	)
