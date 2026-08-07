class_name SpeedBubbleRegion
extends Area2D

# The placeable version of a time bubble. Drop one of these into a scene to
# make a real bendalloy (speeds time up) or cadmium (slows it down) bubble
# -- the same way a coin becomes pushable metal just by sitting in the
# "metal" group (see coin.tscn's groups=["metal"]). One node type covers
# both directions: sim/bubbles.py's SpeedBubble already treats bendalloy
# and cadmium as the same class, only the sign of time_factor differs, so
# this does too.
#
# monitoring and monitorable are both OFF on purpose -- this node does zero
# collision work. Area2D was chosen over a plain Node2D for a later reason,
# not a current one: once this becomes a real scene (issue #26), a
# CollisionShape2D child gives a free draggable circle handle in the 2D
# editor, so a bubble's size can be set by eye instead of typing numbers.
# That scene doesn't exist yet, so there is no shape here yet either --
# whether a position is "inside" this bubble is answered by
# SpeedBubble.contains(), plain distance math, never by Godot's
# collision/physics system.
#
# Visual feedback (a distortion effect at the boundary while a bubble is
# active) is deliberately NOT built here -- Elliott asked for it 2026-08-06,
# recorded on issue #26 rather than built now, since that issue is where
# the actual look gets designed.

@export var radius_px: float = 100.0
@export var time_factor: float = 5.0  # >1 speeds time up (bendalloy), <1 slows it down (cadmium)

# The actual math payload, built once this node enters the tree. Nothing
# outside this file ever touches Godot's Area2D machinery for containment
# -- BubbleClock only ever reads this node's .bubble.
var bubble: SpeedBubble


func _ready() -> void:
	monitoring = false
	monitorable = false
	bubble = SpeedBubble.new(global_position, radius_px, time_factor)
	add_to_group("bubbles")
	queue_redraw()


# Plain placeholder circle so a bubble is visible at all -- gold-ish for
# speeding time up, blue-ish for slowing it down, translucent so a body
# falling through is still visible on top of it. This is NOT the boundary
# distortion effect Elliott asked for on issue #26 -- that is a real design
# question (what should it actually look like) still waiting on a design
# session; this is only enough to see where a bubble is at all.
func _draw() -> void:
	var fill_color: Color = Color(1.0, 0.85, 0.2, 0.18) if time_factor > 1.0 else Color(0.25, 0.55, 1.0, 0.18)
	draw_circle(Vector2.ZERO, radius_px, fill_color)
