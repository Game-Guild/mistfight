extends Node2D

# A reusable per-coin stopwatch for godot/tests/bubble_drop_test.tscn --
# issue #24's port-fidelity check (the sim already proved bendalloy/cadmium
# work; this scene proves the Godot PORT of that mechanism didn't break it).
#
# Runs on RAW world time -- the un-scaled _physics_process delta -- on
# purpose. This is the outside observer's stopwatch, deliberately NOT run
# through BubbleClock: the whole point of the scene is comparing how much
# OUTSIDE time three different local-time experiences take to cover the
# same fall, matching sim/probe_check.py's check_bubble_compresses_time,
# which measures the same thing the same way.
#
# start() is called once, by bubble_drop_trigger.gd, in the same frame it
# releases this stopwatch's paired coin. FloorSensor (a child Area2D
# positioned at the floor line, under that coin's landing spot) stops the
# clock the instant that specific coin's body enters it -- the same
# body_entered pattern coin.gd's own PickupArea already uses
# (coin.gd:102-103), just external to that file; nothing here touches
# coin.gd.

@export var watched_coin: NodePath
@export var result_label: String = "unlabeled"  # printed in the RESULT line so a batch of coins can be told apart

var elapsed_seconds: float = 0.0
var running: bool = false
var display_text: String = "ready"

@onready var floor_sensor: Area2D = $FloorSensor
@onready var coin: Node2D = get_node(watched_coin)


func _ready() -> void:
	floor_sensor.body_entered.connect(_on_floor_sensor_body_entered)


func start() -> void:
	elapsed_seconds = 0.0
	running = true
	display_text = "0.000s"
	queue_redraw()


func reset() -> void:
	elapsed_seconds = 0.0
	running = false
	display_text = "ready"
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not running:
		return
	elapsed_seconds += delta
	display_text = "%.3fs" % elapsed_seconds
	queue_redraw()


func _on_floor_sensor_body_entered(body: Node2D) -> void:
	if body != coin or not running:
		return
	running = false
	display_text = "%.3fs LANDED" % elapsed_seconds
	queue_redraw()
	print("RESULT label=%s elapsed_seconds=%.3f" % [result_label, elapsed_seconds])


func _draw() -> void:
	# Drawn well above the floor sensor's own position, near where the
	# matching coin actually starts its fall, so the number reads next to
	# the lane it belongs to instead of buried down at the floor line.
	# ThemeDB.fallback_font is Godot's built-in default font -- no Theme
	# resource needed just to put a number on screen.
	var text_offset: Vector2 = Vector2(-24, -240)
	draw_string(ThemeDB.fallback_font, text_offset, display_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, ThemeDB.fallback_font_size)
