extends PlayerState

# No physics_process override, and no entry trigger yet either -- nothing
# calls Player.take_hit() until a health/hit system exists. Exits the same
# way Attack does, through the animation_finished signal and root_states
# group membership.


func enter(_previous_state_name: String) -> void:
	player_body.animated_sprite.play("HURT")
