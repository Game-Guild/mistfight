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
	# Draw a coin from reserve if the hand is empty; draw_coin() just hands
	# back whatever is already held if there is one. Only throw if a coin
	# actually came out of that -- if reserve is empty, or a coin is already
	# lying on the ground or flying, pressing shoot just starts pushing
	# whatever is out there, which is what hovering over a landed coin needs.
	var coin: RigidBody2D = player_body.coin_inventory.draw_coin()
	if coin != null:
		_throw_coin(coin)
		seconds_since_throw = 0.0
	else:
		# Nothing was thrown, so there is nothing to wait for. Start the clock
		# already past the windup and the push engages on the first tick.
		seconds_since_throw = THROW_WINDUP_SECONDS
	# The Steel line stays up through the push, since that is when you most want
	# to see the line the force acts along. The reticle stays hidden.
	player_body.steel_lines.show()
	player_body.push_arrow.show()


func physics_process(delta: float) -> void:
	if not Input.is_action_pressed("coin_shoot"):
		state_machine.transition_to("Idle")
		return

	seconds_since_throw += delta
	if seconds_since_throw < THROW_WINDUP_SECONDS:
		# Mid-windup: the coin flies on the flick alone, no push and so no
		# recoil. Since this runs on held input, tapping the key gives a pure
		# throw and holding it gives throw-then-push.
		return

	_push_against_metal(delta)


func exit() -> void:
	player_body.reticle.hide()
	player_body.steel_lines.hide()
	player_body.push_arrow.hide()


func _throw_coin(coin: RigidBody2D) -> void:
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
	coin.release()
	coin.velocity = throw_direction * player_body.THROW_SPEED_PX_PER_S


func _push_against_metal(delta: float) -> void:
	var targets: Array = player_body.select_targets()
	if targets.is_empty():
		return

	var pushes: Array = player_body.compute_pushes(targets, _push_budget_newtons(targets))
	for push_item in pushes:
		# Anything that can be moved by a push implements receive_push. Anchored
		# metal does not, so the push simply fails to move it -- which is what
		# being anchored means. No check for what kind of thing this is.
		if push_item.target.has_method("receive_push"):
			push_item.target.receive_push(push_item.direction, push_item.force_px)

	# The player's half of every force pair, summed. Targets on opposite sides
	# cancel here, which is the whole reason the arrow is worth drawing.
	var net_force: Vector2 = player_body.net_push_on_player(pushes)
	player_body.pending_recoil += net_force / player_body.mass_kg * delta

	var mode_text: String = "steady" if player_body.push_mode == Player.PushMode.STEADY else "active_control"
	player_body.debug_log.store_line("[coin_shoot] mode=" + mode_text
		+ " targets=" + str(targets.size())
		+ " net_force=" + str(net_force)
		+ " net_magnitude=" + str(net_force.length()))


func _push_budget_newtons(targets: Array) -> float:
	# How strong the whole push is, before it gets divided across targets.
	if player_body.push_mode == Player.PushMode.STEADY:
		# Full strength every tick. Does not ease off near the target height, so
		# a hover bobs like an undamped spring.
		return player_body.BASE_PUSH_FORCE

	# HoverControl from notebook 15: just enough force to hold a target height,
	# damped by vertical speed, so a hover settles instead of oscillating.
	#
	# The controller was derived for a single anchor directly below the player.
	# With several targets it uses the NEAREST one as its height reference,
	# which is a stand-in, not a derivation -- expect it to behave oddly when
	# pushing off several things at once.
	var reference: Node2D = _nearest_target(targets)
	var offset: Vector2 = reference.global_position - player_body.global_position
	var distance_m: float = offset.length() / player_body.PIXELS_PER_METER
	var falloff: float = max(0.0, 1.0 - distance_m / player_body.MAX_RANGE_M)

	var gravity_m_per_s2: float = player_body.get_gravity().length() / player_body.PIXELS_PER_METER
	var weight_n: float = player_body.mass_kg * gravity_m_per_s2
	# Where a STEADY push would exactly cancel gravity: strength * (1 - d/range)
	# = m*g, solved for d.
	var equilibrium_height_m: float = player_body.MAX_RANGE_M * (1.0 - weight_n / player_body.BASE_PUSH_FORCE)
	var height_above_m: float = offset.y / player_body.PIXELS_PER_METER
	var height_error_m: float = equilibrium_height_m - height_above_m
	var vertical_speed_m_per_s: float = -player_body.velocity.y / player_body.PIXELS_PER_METER
	var desired_force_n: float = (weight_n
		+ HEIGHT_GAIN_N_PER_M * height_error_m
		- SPEED_GAIN_N_PER_M_PER_S * vertical_speed_m_per_s)
	# max(falloff, small number) only guards the division as distance approaches
	# MAX_RANGE_M; clamp() would cap a huge result anyway.
	return clamp(desired_force_n / max(falloff, 0.0001), 0.0, MAX_CONTROLLED_STRENGTH_N)


func _nearest_target(targets: Array) -> Node2D:
	var nearest: Node2D = targets[0]
	var nearest_distance: float = player_body.global_position.distance_to(nearest.global_position)
	for candidate in targets:
		var distance: float = player_body.global_position.distance_to(candidate.global_position)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest
