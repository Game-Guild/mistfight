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

# --- The windup, and how to abandon it ----------------------------------------
#
# After the coin is flicked out of your hand, the push waits this long before
# it engages. A tenth of a second.
#
# Why it has to wait at all. A carried coin sits 13 pixels below the player, so
# the line between the two points almost straight down, and the push acts along
# that line. Measured 2026-08-02: on the very first tick after a throw, the
# flick contributed 702 px/s sideways and the push contributed 108,882 px/s
# downward -- 155 times more. Without a pause the push wins instantly, the coin
# is slammed into the ground at your feet, and which way you aimed makes no
# difference at all. The flick needs a moment to carry the coin clear before
# there is a meaningful direction to push along. At 1500 px/s a tenth of a
# second puts the coin 150 pixels out, by which point the line to it is within
# about 8 degrees of where you aimed.
#
# What this costs, stated plainly: it is a rule about how Allomancy works that
# is not in the books, and sim/steelpush.py has no equivalent. A push there
# acts at any distance, right down to zero. Elliott chose it 2026-08-03 with
# the fallback below written in deliberately.
#
# IF IT FEELS WRONG, the fallback is separate buttons -- one to throw, one to
# push -- which invents nothing. To switch:
#   1. set THROW_WINDUP_SECONDS to 0.0
#   2. move the _throw_coin() call out of enter() and onto its own input action
#      polled in player.gd, next to the coin.recall() line
# CoinShoot then only ever pushes what is already out in the world, which is
# what it did before any of this, and no waiting rule exists anywhere.
const THROW_WINDUP_SECONDS = 0.1

# Seconds since the coin left the hand this time round. Starts already past the
# windup when there was no throw -- pushing a coin that is lying on the ground
# has nothing to wait for.
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

	seconds_since_throw += delta
	if seconds_since_throw < THROW_WINDUP_SECONDS:
		# Mid-windup. The coin is flying on the flick alone and no push is
		# applied yet, which also means no recoil -- you do not get launched
		# during the throw itself.
		#
		# Worth knowing while playing: because the windup runs on held input,
		# TAPPING this key gives a pure throw with no push at all, and HOLDING
		# it gives throw-then-push. Both behaviours out of one button, without
		# either being written as a special case.
		player_body.update_steel_line_to_coin()
		return

	_push_against_coin(delta)


func exit() -> void:
	player_body.reticle.hide()
	player_body.steel_line.hide()


func _throw_coin() -> void:
	# A Coinshot does not push a coin straight out of their own hand. They flick
	# or drop it first, and then push what is already in the air -- because a
	# push can only ever act along the line between the two bodies, so a coin
	# held against your chest can only be shoved straight down at your feet.
	# The flick is what decides which direction the coin sets off in; the push
	# takes over from there and does all the real work.
	#
	# Direction comes from where the mouse is RIGHT NOW rather than from the
	# reticle's stored position, so throwing works whether or not you were
	# holding the aim key first. The reticle is the picture of this; the mouse
	# is the thing itself.
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
