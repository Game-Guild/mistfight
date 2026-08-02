class_name Player
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

@onready var state_machine: PlayerStateMachine = $StateMachine
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var reticle: Polygon2D = $Reticle
@onready var steel_line: Line2D = $"Steel line"
@onready var coin: RigidBody2D = $"../Coin"
@onready var push_mode_readout: Label = $"../HUD/PushModeReadout"

var pending_recoil: Vector2 = Vector2.ZERO
var debug_log: FileAccess


func _ready() -> void:
	coin.add_collision_exception_with(self)
	debug_log = FileAccess.open("res://player_debug.log", FileAccess.WRITE)
	# Last line on purpose: the @onready vars above (animated_sprite,
	# reticle, and so on) must already be set before the first state's
	# enter() runs, since Idle.enter() calls player_body.animated_sprite.play(...).
	# StateMachine is Player's child, so its own _ready() already ran by
	# this point -- it only built its state dictionary and groups there, it
	# never entered a state itself, for exactly this reason.
	state_machine.start("Idle")


func _physics_process(delta: float) -> void:
	pending_recoil = Vector2.ZERO

	if not is_on_floor():
		velocity += get_gravity() * delta

	if coin.freeze:
		coin.global_position = global_position + Vector2(0, 13)

	# These four checks are carried over unchanged from the original
	# flat-if version of this file: none of them look at what state is
	# currently active, except each one's own guard against re-triggering
	# itself. Jump, Attack, and CoinTarget can all interrupt almost any
	# other state today -- that is existing behavior this refactor
	# preserved on purpose, not something it changed. See the open issues
	# tracking whether that should be narrowed.
	if Input.is_action_just_pressed("jump") and is_on_floor() and state_machine.current_state.name != "Jump":
		state_machine.transition_to("Jump")
	if Input.is_action_just_pressed("attack"):
		state_machine.transition_to("Attack")
	if Input.is_action_just_pressed("coin_target"):
		state_machine.transition_to("CoinTarget")
	if Input.is_action_just_pressed("coin_shoot") and state_machine.current_state.name != "CoinShoot":
		state_machine.transition_to("CoinShoot")

	state_machine.physics_process(delta)

	if state_machine.current_state.is_in_group("move_states"):
		_apply_ground_movement()
	else:
		velocity.x = 0

	# Recoil is added after the movement gate above, so a state that locks
	# velocity.x to 0 (the "else" branch) can never wipe out recoil that a
	# state produced this same tick. Coin_shoot's push recoil is the only
	# source of this today, but it's written generally for whatever else
	# needs it later.
	velocity += pending_recoil

	move_and_slide()


func _apply_ground_movement() -> void:
	# Faithful port of the original movement block: velocity.x updates
	# whether grounded or airborne, so horizontal control is kept during
	# Jump or CoinShoot in mid-air.
	var direction := Input.get_axis("move_left", "move_right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	# The Run/Idle swap below must only ever fire BETWEEN Idle and Run
	# themselves -- never away from some other move_state (Jump, CoinShoot).
	# It used to fire unconditionally whenever grounded, which meant
	# holding coin_shoot while standing still on the ground (true for at
	# least the first tick of every hover, before the push has lifted you
	# at all) forced an immediate transition back to Idle, canceling the
	# push before it ever had a chance to build up -- that's what broke
	# hovering. Only Idle and Run are allowed to swap into each other here;
	# every other state manages its own exit condition (Jump watches the
	# floor itself, CoinShoot/CoinTarget watch their own input release).
	if not is_on_floor():
		return
	var current_state_name: String = state_machine.current_state.name
	if current_state_name != "Idle" and current_state_name != "Run":
		return
	if direction and current_state_name != "Run":
		state_machine.transition_to("Run")
	elif not direction and current_state_name != "Idle":
		state_machine.transition_to("Idle")


func compute_animation_offset_y() -> float:
	# The vertical anchor point used by aiming: half the height of the
	# current animation frame's visible (non-transparent) pixels, offset
	# from the frame's true center. Only CoinTarget reads this today, so
	# it's computed on demand there instead of unconditionally every tick.
	var texture: Texture2D = animated_sprite.sprite_frames.get_frame_texture(animated_sprite.animation, animated_sprite.frame)
	var visible_area: Rect2i = texture.get_image().get_used_rect()  # box around the actual non-transparent pixels
	var frame_height: float = texture.get_height()
	return (visible_area.position.y + visible_area.position.y + visible_area.size.y) / 2.0 - frame_height / 2.0


func take_hit() -> void:
	# No caller yet -- there is no health/hit system built. This just gives
	# one a stable door in later without needing to know FSM internals.
	state_machine.transition_to("Hurt")


func _on_animated_sprite_2d_animation_finished() -> void:
	if state_machine.current_state.is_in_group("root_states"):
		state_machine.transition_to("Idle")


func update_push_mode_readout(mode_text: String) -> void:
	push_mode_readout.text = "Push mode: " + mode_text.replace("_", " ").capitalize()
