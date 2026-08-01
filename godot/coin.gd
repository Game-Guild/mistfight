extends RigidBody2D
@export var SPEED = 0
var debug_log: FileAccess

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	debug_log = FileAccess.open("res://coin_debug.log", FileAccess.WRITE)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if freeze:
		# Still riding along, not fired yet -- keep the trace empty.
		$"../TrajectoryTrace".points = PackedVector2Array()
	else:
		# In flight -- append this frame's position so the trace grows into
		# the path actually flown, even though the coin itself moves too
		# fast this tick to see clearly on its own.
		# NOTE: "points" is a PackedVector2Array. Reading it through the
		# property getter hands back a COPY, not the live array -- calling
		# .append() straight on $Node.points silently mutates a throwaway
		# copy and never touches the real property. Has to be copied out,
		# appended to, then assigned back.
		var trace_points: PackedVector2Array = $"../TrajectoryTrace".points
		trace_points.append(global_position)
		$"../TrajectoryTrace".points = trace_points

func _on_character_body_2d_push(angle: float, force: float) -> void:
	var coin_push = Vector2.from_angle(angle)*force
	apply_central_force(coin_push)
	debug_log.store_line("[coin push received] angle=" + str(angle) + " force=" + str(force) + " coin_push=" + str(coin_push) + " my_global_pos=" + str(global_position) + " my_linear_velocity=" + str(linear_velocity) + " my_mass=" + str(mass))
