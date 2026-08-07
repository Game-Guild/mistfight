extends Node2D

# Drops a small marker at its watched coin's position every fixed slice of
# WORLD time (not local time) -- godot/tests/bubble_drop_test.tscn, issue
# #24's port-fidelity check. Marks are spaced by outside-observer time on
# purpose: since a bubble changes only WHEN a body is somewhere, never
# WHERE (sim/bubbles.py's "when not where" theorem, notebook 07), all three
# coins in this scene should trace the exact same curve -- what should
# differ is only how tightly the marks bunch up along it. A bubbled coin's
# marks packing closer together or spreading farther apart than the
# control coin's, on an otherwise identical path, is that theorem made
# visible, not a shape difference.
#
# Separate from coin.gd's own $TrajectoryTrace (a continuous Line2D the
# real game uses for a different purpose) -- this is a standalone
# diagnostic for this test scene, no changes to shipped gameplay code.

const MARK_INTERVAL_SECONDS: float = 0.15
const MARK_RADIUS_PX: float = 2.0
const MARK_COLOR: Color = Color(1, 1, 1, 0.85)

@export var watched_coin: NodePath

var running: bool = false
var seconds_since_last_mark: float = 0.0
var marks: Array[Vector2] = []

@onready var coin: Node2D = get_node(watched_coin)


func start() -> void:
	running = true
	seconds_since_last_mark = 0.0
	marks.clear()
	queue_redraw()


func reset() -> void:
	running = false
	marks.clear()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not running:
		return
	seconds_since_last_mark += delta
	if seconds_since_last_mark >= MARK_INTERVAL_SECONDS:
		seconds_since_last_mark = 0.0
		marks.append(coin.global_position)
		queue_redraw()


func _draw() -> void:
	for mark_position in marks:
		draw_circle(to_local(mark_position), MARK_RADIUS_PX, MARK_COLOR)
