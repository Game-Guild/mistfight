class_name SpeedBubble
extends RefCounted

# A bubble is a circle where time runs at a different rate for anything
# standing inside it. time_factor > 1 is a bendalloy speed bubble (more
# local seconds pass per real second spent inside); time_factor < 1 is a
# cadmium slow bubble. This class only holds that data and answers
# "is this point inside me" -- nothing here touches gameplay yet.
#
# Ported from sim/bubbles.py's SpeedBubble: same math, but this project's
# pixel units instead of the sim's meters (see PIXELS_PER_METER in
# player.gd). Placing a bubble in an actual scene, and computing a body's
# local delta-time from one, are later steps (issue #23 and on) -- this
# step is just the data and the boundary check.

var center: Vector2
var radius_px: float
var time_factor: float


func _init(bubble_center: Vector2, bubble_radius_px: float, bubble_time_factor: float) -> void:
	# Ported guard from sim/bubbles.py, which raises ValueError for the same
	# case. GDScript has no exceptions to raise here, so assert() is the
	# closest match: it stops a debug/editor/headless run immediately, same
	# as the Python original would. Note this is compiled OUT of release
	# exports, so it is a development-time safety net, not a guard that
	# survives into a shipped build.
	assert(bubble_time_factor > 0, "time factor must be positive")
	center = bubble_center
	radius_px = bubble_radius_px
	time_factor = bubble_time_factor


# True if position is inside the circle, including exactly on the edge --
# matches sim/bubbles.py's "<=" so the two implementations agree at the
# boundary instead of disagreeing by one edge case.
func contains(position: Vector2) -> bool:
	return center.distance_to(position) <= radius_px
