extends SceneTree

# Headless check for SpeedBubble.contains() -- issue #22. Confirms the
# circle-and-point math is right before anything in the engine depends on
# it. No scene, no physics tick, over in one frame. Run from the repo root,
# with the exe path swapped for wherever your Godot binary actually lives
# (it is not on PATH by default -- "godot" alone will not resolve):
#
#   C:\path\to\Godot_v4.7.1-stable_win64.exe --headless --path godot --script res://tests/bubble_test.gd

func _init() -> void:
	# Two bubbles far enough apart that a point near one is nowhere near the
	# other -- catches any accidental cross-contamination between them.
	var speed_bubble: SpeedBubble = SpeedBubble.new(Vector2(0, 0), 100.0, 5.0)    # bendalloy-style: speeds time up
	var slow_bubble: SpeedBubble = SpeedBubble.new(Vector2(1000, 0), 50.0, 0.2)  # cadmium-style: slows time down

	assert(speed_bubble.contains(Vector2(0, 0)), "center of a bubble must be inside it")
	assert(speed_bubble.contains(Vector2(100, 0)), "a point exactly on the radius must be inside it (boundary is inclusive)")
	assert(not speed_bubble.contains(Vector2(101, 0)), "a point one pixel past the radius must be outside")
	assert(not speed_bubble.contains(Vector2(1000, 0)), "a point inside the other bubble must not register in this one")
	assert(slow_bubble.contains(Vector2(1000, 0)), "center of the second bubble must be inside it")

	print("bubble_test: all checks passed")
	quit()
