extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -400.0
const BASE_PUSH_FORCE = 2000.0
const BASE_MASS_KG = 80.0
const AIM_RADIUS_PX = 20
const MAX_RANGE_M = 16.0
# This project's world runs at Godot's default gravity, 980 px/s^2 (measured
# directly from this project's own fall data: velocity climbed 16.333 px/s
# per tick at 60 ticks/second = 980). Real gravity is 9.81 m/s^2 (sim/world.py).
# 980 / 9.81 = ~100, so 1 meter in the sim equals ~100 pixels here.
const PIXELS_PER_METER = 100.0

signal push(angle: float, force: float)

enum State { IDLE, RUN, JUMP, ATTACK, HURT, COIN_TARGET, COIN_SHOOT}
#Claude one day I'd like help with seeing how I can use enums or whatever type to make subtypes of it so I can like have a master list and makea  bunch of sublists of said list
#var still_states = [State.ATTACK, State.HURT, State.COIN_TARGET, State.COIN_SHOOT]
var state: State = State.IDLE
var debug_log: FileAccess

func _ready() -> void:
	$"../Coin".add_collision_exception_with(self)
	debug_log = FileAccess.open("res://player_debug.log", FileAccess.WRITE)

func _physics_process(delta: float) -> void:
	var recoil := Vector2.ZERO
	var texture: Texture2D = $AnimatedSprite2D.sprite_frames.get_frame_texture($AnimatedSprite2D.animation, $AnimatedSprite2D.frame)
	var visible_area: Rect2i = texture.get_image().get_used_rect()  # box around the actual non-transparent pixels
	var frame_height: float = texture.get_height()
	var offset_y: float = (visible_area.position.y + visible_area.position.y + visible_area.size.y) / 2.0 - frame_height / 2.0
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	if $"../Coin".freeze:
		$"../Coin".global_position = global_position + Vector2(0, 13)

	if state == State.JUMP and is_on_floor():
		state = State.IDLE
	# Handle jump.
	elif Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		state = State.JUMP

	if state == State.COIN_TARGET and not Input.is_action_pressed("coin_target"):
		state = State.IDLE
		$Reticle.hide()
		$"Steel line".hide()

	if state == State.COIN_SHOOT and not Input.is_action_pressed("coin_shoot"):
		state = State.IDLE
		$Reticle.hide()
		$"Steel line".hide()

	if Input.is_action_just_pressed("attack"):
		$AnimatedSprite2D.play("ATTACK 1")
		state = State.ATTACK

	if Input.is_action_just_pressed("coin_target"):
		$AnimatedSprite2D.play("COIN_TARGET")
		state = State.COIN_TARGET
		$Reticle.show()
		$"Steel line".show()

	if Input.is_action_pressed("coin_target") and state == State.COIN_TARGET:
		var reticle_vector = $Reticle.position
		var mouse_vector = get_local_mouse_position()
		$Reticle.position = mouse_vector.normalized() * AIM_RADIUS_PX + Vector2(0, offset_y)
		$"Steel line".points = [Vector2(0, offset_y), $Reticle.position]
		
	# Get the input direction and handle the movement/deceleration.
	if Input.is_action_just_pressed("coin_shoot") and state != State.COIN_SHOOT:
		$AnimatedSprite2D.play("COIN_SHOOT")
		state = State.COIN_SHOOT
		$"../Coin".freeze = false
		var angle = $Reticle.position.angle()
		var coin_distance_m = ($"../Coin".global_position - global_position).length() / PIXELS_PER_METER
		# Same formula as sim/steelpush.py: force falls off linearly with
		# distance, reaching zero at MAX_RANGE_M. Computed in real meters,
		# then converted back to this project's pixel-based force units.
		var force = BASE_PUSH_FORCE * max(0.0, 1.0 - coin_distance_m / MAX_RANGE_M) * PIXELS_PER_METER
		recoil = -Vector2.from_angle(angle) * force / BASE_MASS_KG * delta
		debug_log.store_line("[coin_shoot start] angle=" + str(angle) + " coin_distance_m=" + str(coin_distance_m) + " force=" + str(force) + " coin_global_pos=" + str($"../Coin".global_position))
		push.emit(angle, force)
	if Input.is_action_pressed("coin_shoot") and state == State.COIN_SHOOT:
		var angle = $Reticle.position.angle()
		var coin_distance_m = ($"../Coin".global_position - global_position).length() / PIXELS_PER_METER
		var force = BASE_PUSH_FORCE * max(0.0, 1.0 - coin_distance_m / MAX_RANGE_M) * PIXELS_PER_METER
		recoil = -Vector2.from_angle(angle) * force / BASE_MASS_KG * delta
		debug_log.store_line("[coin_shoot held] angle=" + str(angle) + " coin_distance_m=" + str(coin_distance_m) + " force=" + str(force) + " coin_global_pos=" + str($"../Coin".global_position) + " coin_linear_velocity=" + str($"../Coin".linear_velocity))
		push.emit(angle, force)
	if state == State.COIN_TARGET:
		var reticle_vector = $Reticle.position
#		TODO: do more of the other target stuff but this one is as if we're ste'll targeting tho maybe that won't matter
	var direction := Input.get_axis("move_left", "move_right")
	if state in [State.IDLE, State.RUN, State.JUMP] :
		if direction:
			velocity.x = direction * SPEED
			if is_on_floor():
	#			set animation to RUN
				$AnimatedSprite2D.play("RUN")
				pass
		if not direction:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			if is_on_floor():
	#			set animation to IDLE
				$AnimatedSprite2D.play("IDLE")
				pass
	else:
		velocity.x = 0

	# Recoil is applied here, after the state-based velocity handling above,
	# so the "lock movement during coin_shoot" branch (the "else" just above,
	# which zeroes velocity.x) can't wipe it out on the same tick.
	velocity += recoil

	move_and_slide()


func _on_animated_sprite_2d_animation_finished() -> void:
	if state == State.ATTACK:
		state = State.IDLE
