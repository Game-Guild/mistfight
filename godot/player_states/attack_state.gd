extends PlayerState

# No physics_process override: Attack has no per-tick behavior. It leaves
# on its own via Player's _on_animated_sprite_2d_animation_finished, which
# checks group membership (root_states) rather than this state by name --
# see player.gd.


func enter(_previous_state_name: String) -> void:
	player_body.animated_sprite.play("ATTACK 1")
