extends PlayerState

# No physics_process override, and no entry trigger yet either -- nothing
# calls Player.take_hit() until a health/hit system exists. Exits the same
# way Attack does, through the animation_finished signal and root_states
# group membership.


func is_interruptible() -> bool:
	# Getting hit commits. Acting your way out of a hit reaction is the thing
	# hitstun exists to prevent.
	#
	# This only holds because the HURT animation is one-shot. It used to loop,
	# which meant animation_finished never fired -- the only reason Hurt ever
	# ended was that anything could interrupt it. With that door closed, a
	# looping HURT would trap the player in this state forever.
	return false


func enter(_previous_state_name: String) -> void:
	player_body.animated_sprite.play("HURT")
