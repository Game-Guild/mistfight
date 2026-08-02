extends PlayerState


func enter(_previous_state_name: String) -> void:
	player_body.animated_sprite.play("RUN")
