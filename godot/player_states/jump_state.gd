extends PlayerState

# Godot's is_on_floor() reflects last tick's move_and_slide() result. On the
# very tick Jump is entered, the player hasn't actually left the ground yet
# in the physics engine's eyes -- checking is_on_floor() on that same tick
# would read "still grounded" and bounce straight back to Idle before
# move_and_slide() ever lifts the player. _frame_entered records which
# physics tick we entered on so physics_process can skip the floor check
# for exactly that one tick.
var _frame_entered: int = -1


func enter(_previous_state_name: String) -> void:
	player_body.velocity.y = player_body.JUMP_VELOCITY
	_frame_entered = Engine.get_physics_frames()


func physics_process(_delta: float) -> void:
	if Engine.get_physics_frames() == _frame_entered:
		return
	if player_body.is_on_floor():
		state_machine.transition_to("Idle")
