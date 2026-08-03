extends Node2D

# The targeting overlay: the blue lines an Allomancer burning steel sees to
# nearby metal, plus the wedge showing which of it a push would actually act on.
#
# One node draws all of it, so the number of lines on screen is not tied to how
# many nodes exist in the scene -- add metal to a level and it gets a line with
# no changes here.
#
# Two levels of emphasis, and the difference matters. Every piece of metal in
# range gets a line, because an Allomancer sees all of it. Only metal inside the
# wedge is drawn bright, because only that gets pushed. Seeing and selecting are
# different things.

# Unselected lines fade and thin with distance, matching the push's own falloff,
# so the display shows how much leverage each piece of metal offers rather than
# just listing what exists.
const NEAR_COLOR = Color(0.2, 0.75, 1.0, 0.55)
const FAR_COLOR = Color(0.2, 0.75, 1.0, 0.06)
const SELECTED_COLOR = Color(0.55, 0.9, 1.0, 1.0)
const NEAR_WIDTH_PX = 1.5
const FAR_WIDTH_PX = 0.5
const SELECTED_WIDTH_PX = 2.5

# How far the wedge's edges are drawn. Range is 16 m, which is 1600 px and far
# off screen, so the edges are drawn as short guides rather than to their real
# extent -- they show a direction, not a boundary you could see the end of.
const WEDGE_GUIDE_LENGTH_PX = 110.0
const WEDGE_COLOR = Color(0.55, 0.9, 1.0, 0.25)
const WEDGE_WIDTH_PX = 1.0

var player: Player


func _ready() -> void:
	player = get_parent() as Player


func _process(_delta: float) -> void:
	# Both ends move constantly, so this is redrawn every frame rather than only
	# when something changes.
	if visible:
		queue_redraw()


func _draw() -> void:
	var selected: Array = player.select_metal_in_cone()
	var range_px: float = player.MAX_RANGE_M * player.PIXELS_PER_METER

	for metal in player.find_metal_in_range():
		var to_metal: Vector2 = to_local(metal.global_position)
		if metal in selected:
			draw_line(Vector2.ZERO, to_metal, SELECTED_COLOR, SELECTED_WIDTH_PX)
			continue
		# 1 at the player's feet, 0 at the edge of range -- the same shape as the
		# push's linear falloff.
		var nearness: float = 1.0 - (to_metal.length() / range_px)
		draw_line(
			Vector2.ZERO,
			to_metal,
			FAR_COLOR.lerp(NEAR_COLOR, nearness),
			lerp(FAR_WIDTH_PX, NEAR_WIDTH_PX, nearness))

	_draw_wedge_edges()


func _draw_wedge_edges() -> void:
	# At the widest setting the wedge covers everything, so edges would be
	# meaningless -- there is nothing outside them to exclude.
	if player.cone_half_angle_degrees >= player.CONE_MAX_HALF_ANGLE_DEGREES:
		return
	var aim: Vector2 = player.aim_direction()
	var half_angle: float = deg_to_rad(player.cone_half_angle_degrees)
	for side in [-1.0, 1.0]:
		var edge: Vector2 = aim.rotated(half_angle * side) * WEDGE_GUIDE_LENGTH_PX
		draw_line(Vector2.ZERO, edge, WEDGE_COLOR, WEDGE_WIDTH_PX)
