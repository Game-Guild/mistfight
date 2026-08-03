extends SceneTree

# One-off check: does the engine actually know about our input actions, and
# which physical key is each one bound to? Run with:
#   godot --headless --path godot --script res://tests/check_input.gd
func _init() -> void:
	for action_name in ["jump", "coin_shoot", "toggle_control_mode", "toggle_air_braking"]:
		if not InputMap.has_action(action_name):
			print("%-22s MISSING FROM INPUTMAP" % action_name)
			continue
		var key_names: Array = []
		for event in InputMap.action_get_events(action_name):
			if event is InputEventKey:
				key_names.append("physical_keycode=%d (%s)"
					% [event.physical_keycode, OS.get_keycode_string(event.physical_keycode)])
		print("%-22s ok  %s" % [action_name, ", ".join(key_names)])
	quit()
