extends PlayerState

# Which push mode is active is NOT stored here. It lives on Player, alongside
# the other whole-game toggles, because the C key that changes it has to work
# whether or not a push is currently happening. It used to be a variable on
# this state polled from this state's physics_process, which meant the key only
# ever did anything during the fraction of a second you were mid-push -- that
# was issue #13.

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
	player_body.coin.release()
	# Keep the blue Steel line up while the push is actually happening. It used
	# to vanish the instant you left CoinTarget, which meant it was only ever
	# visible while holding the aim key and never during the push itself --
	# the one moment you most want to see the line the force is acting along.
	# The reticle stays hidden: it points where you would flick a coin, and no
	# flick is happening mid-push.
	player_body.steel_line.show()


func physics_process(delta: float) -> void:
	if not Input.is_action_pressed("coin_shoot"):
		state_machine.transition_to("Idle")
		return
	_push_against_coin(delta)


func exit() -> void:
	player_body.reticle.hide()
	player_body.steel_line.hide()


func _push_against_coin(delta: float) -> void:
	# Where the coin actually is, relative to the player. Everything below is
	# derived from this one vector -- how hard the push is (distance) AND which
	# way it points (direction).
	var coin_offset: Vector2 = player_body.coin.global_position - player_body.global_position
	var coin_distance_m: float = coin_offset.length() / player_body.PIXELS_PER_METER
	var falloff: float = max(0.0, 1.0 - coin_distance_m / player_body.MAX_RANGE_M)

	# The push points along the real line joining the two bodies. A Steelpush
	# is a force PAIR along that line -- the coin is shoved directly away from
	# the player, the player directly away from the coin, equal and opposite.
	# sim/steelpush.py does exactly this and has no concept of "aim" at all:
	#   offset = self.pusher.position - target.position
	#   direction_to_pusher = offset / distance
	# An Allomancer picks WHICH metal to push and where on it to push. They
	# cannot push it in a direction unrelated to where the metal is.
	#
	# This line used to read `player_body.reticle.position.angle()` -- the
	# reticle's aim direction -- which broke in two separate ways:
	#   1. Aim somewhere the coin is NOT and the coin flew that way anyway.
	#   2. Even as an aim reading it was wrong. coin_target_state.gd builds
	#      the reticle position as (mouse direction * 20px) + (0, offset_y),
	#      where offset_y is the sprite's visible center -- measured at 16px
	#      for the IDLE frames. Taking .angle() of that sum bakes the sprite
	#      offset into the direction: aiming dead horizontal produced the
	#      vector (20, 16), which is 38.7 degrees BELOW horizontal.
	# Deriving direction from coin_offset removes both problems at once,
	# because the reticle stops feeding the physics entirely.
	var push_direction: Vector2
	if coin_offset.length() < 0.001:
		# Player and coin occupying the same point has no "line between them"
		# to push along. sim/steelpush.py hits the same degenerate case and
		# resolves it by pushing the pusher straight up; the equivalent here is
		# shoving the coin straight down, since our direction points at the
		# coin and the recoil is its opposite. Should never happen in practice
		# (a carried coin rides 13px below the player) -- this is a guard, not
		# a behavior anyone is meant to see.
		push_direction = Vector2.DOWN
	else:
		push_direction = coin_offset.normalized()
	var angle: float = push_direction.angle()

	var strength_n: float
	if player_body.push_mode == Player.PushMode.STEADY:
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
		# Known limitation, stated rather than patched: every line above asks
		# "how much UPWARD force do I need", but the force is then applied
		# along push_direction, which only points straight up when the coin is
		# directly below the player. Stand off to one side and the upward part
		# of the push is only cos(lean angle) of what the controller asked
		# for, so it under-lifts and swings. That is arguably the honest
		# outcome -- you genuinely cannot hover cleanly off a coin that is not
		# under you -- so it is left alone until playtesting says otherwise.

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
