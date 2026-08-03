extends Node2D

# The blue lines an Allomancer burning steel sees to every piece of metal
# nearby. One node draws all of them, so the number of lines on screen is not
# tied to how many nodes exist in the scene -- add metal to the level and it
# gets a line with no scene changes here.
#
# Lines fade and thin with distance, matching the push's own falloff, so what
# you see is a picture of how much leverage each piece of metal actually gives
# you rather than a flat list of what exists.

const NEAR_COLOR = Color(0.2, 0.75, 1.0, 0.9)
const FAR_COLOR = Color(0.2, 0.75, 1.0, 0.08)
const NEAR_WIDTH_PX = 2.0
const FAR_WIDTH_PX = 0.5

var player: Player


func _ready() -> void:
	player = get_parent() as Player


func _process(_delta: float) -> void:
	# Both ends move constantly, so the lines are redrawn every frame rather
	# than only when something changes.
	if visible:
		queue_redraw()


func _draw() -> void:
	var range_px: float = player.MAX_RANGE_M * player.PIXELS_PER_METER
	for metal in player.find_metal_in_range():
		var to_metal: Vector2 = to_local(metal.global_position)
		# 1 at the player's feet, 0 at the edge of range -- the same shape as
		# the push's linear falloff.
		var nearness: float = 1.0 - (to_metal.length() / range_px)
		draw_line(
			Vector2.ZERO,
			to_metal,
			FAR_COLOR.lerp(NEAR_COLOR, nearness),
			lerp(FAR_WIDTH_PX, NEAR_WIDTH_PX, nearness))
