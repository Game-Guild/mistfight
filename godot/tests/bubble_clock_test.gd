extends Node

# Headless check for BubbleClock.local_dt() -- issue #23. Confirms a body
# gets a scaled local delta when it's inside a bubble, and gets its own
# world delta straight back when it's outside every bubble. Run with:
#
#   godot --headless --path godot res://tests/bubble_clock_test.tscn
#
# This is a real scene (bubble_clock_test.tscn), not a bare --script run,
# on purpose: --script mode runs a script as the entire program and skips
# Godot's normal project bootstrap, which is also what instances autoloads
# -- confirmed directly, printing SceneTree.root's children at startup
# under --script came back empty. Loading an actual scene goes through
# that bootstrap for real, the same as any real playtest of the game does,
# so BubbleClock below is the genuine autoload singleton, not a stand-in.

const WORLD_DELTA_SECONDS: float = 1.0 / 240.0  # this project's fixed physics tick


func _ready() -> void:
	# Two bubbles, placed far enough apart that a point near one is nowhere
	# near the other -- catches any accidental cross-contamination. Each one
	# has to actually enter the tree (add_child) for its own _ready() to
	# run, since that is what builds its SpeedBubble and joins the
	# "bubbles" group BubbleClock reads.
	var speed_up_bubble := SpeedBubbleRegion.new()
	speed_up_bubble.position = Vector2(0, 0)
	speed_up_bubble.radius_px = 100.0
	speed_up_bubble.time_factor = 5.0  # bendalloy-style: speeds time up
	add_child(speed_up_bubble)

	var slow_down_bubble := SpeedBubbleRegion.new()
	slow_down_bubble.position = Vector2(1000, 0)
	slow_down_bubble.radius_px = 50.0
	slow_down_bubble.time_factor = 0.2  # cadmium-style: slows time down
	add_child(slow_down_bubble)

	var inside_speed_up: float = BubbleClock.local_dt(WORLD_DELTA_SECONDS, Vector2(0, 0))
	assert(is_equal_approx(inside_speed_up, WORLD_DELTA_SECONDS * 5.0),
		"a body at the center of the speed-up bubble should experience 5x local dt")

	var inside_slow_down: float = BubbleClock.local_dt(WORLD_DELTA_SECONDS, Vector2(1000, 0))
	assert(is_equal_approx(inside_slow_down, WORLD_DELTA_SECONDS * 0.2),
		"a body at the center of the slow-down bubble should experience 0.2x local dt")

	var outside_every_bubble: float = BubbleClock.local_dt(WORLD_DELTA_SECONDS, Vector2(500, 500))
	assert(is_equal_approx(outside_every_bubble, WORLD_DELTA_SECONDS),
		"a body outside every bubble should get its world delta back unscaled")

	print("bubble_clock_test: all checks passed")
	get_tree().quit()
