extends PlayerState

enum PushMode { STEADY, ACTIVE_CONTROL }
var push_mode: PushMode = PushMode.STEADY

# Notebook 15 cell 7's HoverControl gains (notebooks/15_the_coinshot_hover.ipynb),
# reused as-is from hover_pusher.gd's reproduction of that experiment --
# same validated tuning, not reinvented here. Shape being tested: pull
# toward the target height, oppose vertical speed, clamp to a finite push
# (steel pushes, never pulls).
const HEIGHT_GAIN_N_PER_M = 2000.0
const SPEED_GAIN_N_PER_M_PER_S = 2200.0
const MAX_CONTROLLED_STRENGTH_N = 8000.0


func enter(_previous_state_name: String) -> void:
	player_body.animated_sprite.play("COIN_SHOOT")
	player_body.coin.freeze = false


func physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_control_mode"):
		push_mode = PushMode.ACTIVE_CONTROL if push_mode == PushMode.STEADY else PushMode.STEADY
	if not Input.is_action_pressed("coin_shoot"):
		state_machine.transition_to("Idle")
		return
	_push_against_coin(delta)


func exit() -> void:
	player_body.reticle.hide()
	player_body.steel_line.hide()


func _push_against_coin(delta: float) -> void:
	var angle: float = player_body.reticle.position.angle()
	var coin_offset: Vector2 = player_body.coin.global_position - player_body.global_position
	var coin_distance_m: float = coin_offset.length() / player_body.PIXELS_PER_METER
	var falloff: float = max(0.0, 1.0 - coin_distance_m / player_body.MAX_RANGE_M)

	var strength_n: float
	if push_mode == PushMode.STEADY:
		# The original behavior: full strength every tick, whatever the
		# formula allows at this distance. Simple, and exactly what made
		# the coin explosively hard to hold in place -- full force doesn't
		# ease off just because you're already where you want to be.
		strength_n = player_body.BASE_PUSH_FORCE
	else:
		# PD control ported from hover_pusher.gd's HoverControl: rather than
		# always pushing at full strength, compute just enough force to
		# hold the player at the height above the coin where a steady push
		# would balance gravity, damped by the player's own vertical speed
		# so it settles instead of bobbing forever. "Height above the coin"
		# plays the role hover_pusher.gd's fixed Anchor does -- the coin
		# isn't literally fixed, but while it's caught and resting, it's
		# close enough to stand in for one.
		var gravity_m_per_s2: float = player_body.get_gravity().length() / player_body.PIXELS_PER_METER
		var weight_n: float = player_body.BASE_MASS_KG * gravity_m_per_s2
		# Same derivation as hover_pusher.gd's equilibrium_height_m: where a
		# STEADY push would exactly cancel gravity. strength * (1 - d/range)
		# = m*g, solved for d.
		var equilibrium_height_m: float = player_body.MAX_RANGE_M * (1.0 - weight_n / player_body.BASE_PUSH_FORCE)
		var height_above_coin_m: float = coin_offset.y / player_body.PIXELS_PER_METER
		var height_error_m: float = equilibrium_height_m - height_above_coin_m
		var vertical_speed_m_per_s: float = -player_body.velocity.y / player_body.PIXELS_PER_METER
		var desired_force_n: float = (weight_n
			+ HEIGHT_GAIN_N_PER_M * height_error_m
			- SPEED_GAIN_N_PER_M_PER_S * vertical_speed_m_per_s)
		# max(falloff, small number) guards the division as distance
		# approaches MAX_RANGE_M -- clamp() below would cap a huge or
		# infinite result anyway, this just keeps the intermediate value
		# from ever reading as infinity.
		strength_n = clamp(desired_force_n / max(falloff, 0.0001), 0.0, MAX_CONTROLLED_STRENGTH_N)

	var force: float = strength_n * falloff * player_body.PIXELS_PER_METER
	var recoil: Vector2 = -Vector2.from_angle(angle) * force / player_body.BASE_MASS_KG * delta
	var mode_text: String = "steady" if push_mode == PushMode.STEADY else "active_control"
	player_body.debug_log.store_line("[coin_shoot] mode=" + mode_text + " angle=" + str(angle) + " coin_distance_m=" + str(coin_distance_m) + " force=" + str(force) + " coin_global_pos=" + str(player_body.coin.global_position) + " coin_linear_velocity=" + str(player_body.coin.linear_velocity))
	player_body.push.emit(angle, force)
	player_body.pending_recoil += recoil
	player_body.update_push_mode_readout(mode_text)
