extends PlayerState

# Which push mode is active lives on Player, not here, so the key that changes
# it works in any state rather than only mid-push.

# HoverControl gains from notebook 15 (notebooks/15_the_coinshot_hover.ipynb),
# reused as-is: pull toward the target height, oppose vertical speed, clamp to a
# finite push, since steel pushes and never pulls.
const HEIGHT_GAIN_N_PER_M = 2000.0
const SPEED_GAIN_N_PER_M_PER_S = 2200.0
const MAX_CONTROLLED_STRENGTH_N = 8000.0

# How long the throw takes before the push engages. A carried coin sits 13 px
# below the player, so the push line points almost straight down and is ~150x
# stronger than the flick -- with no pause the coin is driven into the ground at
# your feet and aiming does nothing. 0.1s at 1500 px/s carries the coin 150 px
# clear, by which point the line to it is within ~8 degrees of where you aimed.
#
# Alternative if this feels wrong: separate throw and push buttons. Set this to
# 0.0 and move the _throw_coin() call out of enter() onto its own input action
# polled in player.gd.
const THROW_WINDUP_SECONDS = 0.1

# Seconds since the coin left the hand. Starts past the windup when nothing was
# thrown, since pushing a coin already on the ground waits for nothing.
var seconds_since_throw: float = 0.0


func enter(_previous_state_name: String) -> void:
	player_body.animated_sprite.play("COIN_SHOOT")
	# Only throw if the coin is still in hand. If it is already lying on the
	# ground or flying, pressing shoot just starts pushing whatever is out
	# there -- which is what hovering over a landed coin needs.
	if player_body.coin.is_carried:
		_throw_coin()
		seconds_since_throw = 0.0
	else:
		# Nothing was thrown, so there is nothing to wait for. Start the clock
		# already past the windup and the push engages on the first tick.
		seconds_since_throw = THROW_WINDUP_SECONDS
	# The Steel line stays up through the push, since that is when you most want
	# to see the line the force acts along. The reticle stays hidden.
	player_body.steel_line.show()


func physics_process(delta: float) -> void:
	if not Input.is_action_pressed("coin_shoot"):
		state_machine.transition_to("Idle")
		return

	seconds_since_throw += delta
	if seconds_since_throw < THROW_WINDUP_SECONDS:
		# Mid-windup: the coin flies on the flick alone, no push and so no
		# recoil. Since this runs on held input, tapping the key gives a pure
		# throw and holding it gives throw-then-push.
		player_body.update_steel_line_to_coin()
		return

	_push_against_coin(delta)


func exit() -> void:
	player_body.reticle.hide()
	player_body.steel_line.hide()


func _throw_coin() -> void:
	# A push acts along the line between the two bodies, so a coin held against
	# your chest can only be shoved at your feet. The flick sets which direction
	# it leaves in; the push takes over from there.
	#
	# Direction is read from the mouse now rather than the reticle's stored
	# position, so throwing works whether or not the aim key was held first.
	var throw_direction: Vector2 = player_body.get_local_mouse_position().normalized()
	if throw_direction == Vector2.ZERO:
		# Mouse sitting exactly on the player leaves no direction to throw in.
		# Drop it at your feet, which is the hovering case anyway.
		throw_direction = Vector2.DOWN
	player_body.coin.release()
	player_body.coin.velocity = throw_direction * player_body.THROW_SPEED_PX_PER_S


func _push_against_coin(delta: float) -> void:
	# Where the coin actually is, relative to the player. Everything below is
	# derived from this one vector -- how hard the push is (distance) AND which
	# way it points (direction).
	var coin_offset: Vector2 = player_body.coin.global_position - player_body.global_position
	var coin_distance_m: float = coin_offset.length() / player_body.PIXELS_PER_METER
	var falloff: float = max(0.0, 1.0 - coin_distance_m / player_body.MAX_RANGE_M)

	# A steelpush is a force pair along the real line joining the two bodies:
	# the coin is shoved directly away from the player and the player directly
	# away from the coin. sim/steelpush.py does the same and has no concept of
	# aim at all -- an Allomancer picks which metal to push, not which direction
	# to push it, so the reticle never feeds this.
	var push_direction: Vector2
	if coin_offset.length() < 0.001:
		# Coincident player and coin leave no line to push along. Guard only;
		# a carried coin always rides 13px below the player.
		push_direction = Vector2.DOWN
	else:
		push_direction = coin_offset.normalized()
	var angle: float = push_direction.angle()

	var strength_n: float
	if player_body.push_mode == Player.PushMode.STEADY:
		# Full strength every tick, whatever the distance formula allows. Does
		# not ease off near the target height, so a hover bobs forever.
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
		# Limitation: this asks how much UPWARD force is needed, but applies it
		# along push_direction, which only points straight up when the coin sits
		# directly below. Off to one side it under-lifts and swings.

	var force: float = strength_n * falloff * player_body.PIXELS_PER_METER
	# Newton's third law: the coin goes one way along the line, the player goes
	# the other. Same magnitude, divided by the player's much larger mass.
	var recoil: Vector2 = -push_direction * force / player_body.BASE_MASS_KG * delta
	var mode_text: String = "steady" if player_body.push_mode == Player.PushMode.STEADY else "active_control"
	player_body.debug_log.store_line("[coin_shoot] mode=" + mode_text + " angle=" + str(angle) + " coin_distance_m=" + str(coin_distance_m) + " force=" + str(force) + " coin_global_pos=" + str(player_body.coin.global_position) + " coin_velocity=" + str(player_body.coin.velocity))
	player_body.push.emit(angle, force)
	player_body.pending_recoil += recoil
	# Redraw the line every tick so it tracks the coin as it moves away.
	player_body.update_steel_line_to_coin()
