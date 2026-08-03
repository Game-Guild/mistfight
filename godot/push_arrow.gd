extends Node2D

# An arrow showing where a push would actually throw the player, drawn before
# they commit to it.
#
# A steelpush shoves you AWAY from metal, so aiming at something and being
# thrown the other way asks the player to think backwards under pressure. Rather
# than invert the aim, this shows the answer: the net force is fully determined
# by geometry, so it can be computed and drawn exactly. Not a hint -- the real
# result.
#
# It reads the same compute_pushes() the physics uses, so the arrow and what
# happens when you press the button cannot disagree.

# Arrow length at full budget. Everything scales linearly against this, so a
# push half as strong draws half as long.
const FULL_STRENGTH_LENGTH_PX = 90.0
const HEAD_LENGTH_PX = 10.0
const HEAD_HALF_WIDTH_PX = 6.0
const LINE_WIDTH_PX = 2.5
const ARROW_COLOR = Color(1.0, 0.85, 0.25, 0.9)

# Below this fraction of full strength the arrow is not drawn at all. Stops a
# jittering stub appearing when everything cancels out -- and "no arrow" is the
# honest reading of that situation anyway.
const MINIMUM_VISIBLE_FRACTION = 0.02

var player: Player


func _ready() -> void:
	player = get_parent() as Player


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var pushes: Array = player.compute_pushes(player.find_metal_in_range(), player.BASE_PUSH_FORCE)
	var net_force: Vector2 = player.net_push_on_player(pushes)

	# The most any push can deliver, used to scale the drawing so arrow length
	# means something absolute rather than being normalised to itself.
	var full_strength: float = player.BASE_PUSH_FORCE * player.PIXELS_PER_METER
	var strength_fraction: float = net_force.length() / full_strength
	if strength_fraction < MINIMUM_VISIBLE_FRACTION:
		return

	var tip: Vector2 = net_force.normalized() * (strength_fraction * FULL_STRENGTH_LENGTH_PX)
	draw_line(Vector2.ZERO, tip, ARROW_COLOR, LINE_WIDTH_PX)

	# Head: a triangle sitting at the tip, pointing the same way.
	var along: Vector2 = net_force.normalized()
	var across: Vector2 = along.orthogonal()
	draw_colored_polygon(
		PackedVector2Array([
			tip,
			tip - along * HEAD_LENGTH_PX + across * HEAD_HALF_WIDTH_PX,
			tip - along * HEAD_LENGTH_PX - across * HEAD_HALF_WIDTH_PX,
		]),
		ARROW_COLOR)
