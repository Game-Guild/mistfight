extends PlayerState


func enter(_previous_state_name: String) -> void:
	player_body.animated_sprite.play("COIN_TARGET")
	player_body.reticle.show()
	player_body.steel_lines.show()
	player_body.push_arrow.show()


func physics_process(_delta: float) -> void:
	if not Input.is_action_pressed("coin_target"):
		state_machine.transition_to("Idle")
		return
	# The reticle is a pure aim indicator now: it no longer feeds the push
	# force in any way (see coin_shoot_state.gd for why). It orbits the
	# player's visible sprite center at a fixed 20px radius, following the
	# mouse, and its job from here on is to say which direction you would
	# FLICK a coin -- the throw mechanic that has yet to be built.
	var sprite_center_offset_y := player_body.compute_animation_offset_y()
	var mouse_vector := player_body.get_local_mouse_position()
	player_body.reticle.position = mouse_vector.normalized() * player_body.AIM_RADIUS_PX + Vector2(0, sprite_center_offset_y)

	# TODO (carried over from the old player.gd): more targeting behavior --
	# e.g. showing what's actually reachable/hittable -- was intended to go
	# here. Tracked as a GitHub issue rather than implemented blind.


func exit() -> void:
	player_body.reticle.hide()
	player_body.steel_lines.hide()
	player_body.push_arrow.hide()
