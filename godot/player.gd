class_name Player
extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -400.0

# How fast a coin leaves your hand when flicked. 1500 px/s is 15 m/s at this
# project's 100 pixels to the metre, about 34 mph -- a hard flick, well short of
# a thrown baseball (~40 m/s). It only has to clear your hand; the push does the
# real work from there.
const THROW_SPEED_PX_PER_S = 1500.0
# Total strength of a Steelpush, in newtons. Matches sim/steelpush.py and
# notebook 15. Both halves of the force pair use it -- the same strength that
# shoves the coin is what lifts the player -- so lowering it weakens the hover
# as much as the shot. Below ~793 N it cannot beat the player's own weight and
# you never leave the ground; 2000 hovers about 9.7 m above the coin.
const BASE_PUSH_FORCE: float = 2000.0
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
@onready var steel_lines: Node2D = $SteelLines
# The coin this player is holding. Deliberately separate from the general
# metal query below: your own held coin is not something you can push off.
# Someone ELSE's held coin is fair game, which is why the exclusion is by
# identity rather than by a global "is anyone carrying this" flag.
@onready var carried_coin: RigidBody2D = $"../Coin"
@onready var push_mode_readout: Label = $"../HUD/PushModeReadout"

var pending_recoil: Vector2 = Vector2.ZERO
var debug_log: FileAccess


# Whole-game toggles, polled every tick in _physics_process so they respond in
# any state rather than only while their own state is running.

# How a held steelpush decides its strength.
#   STEADY         -- full strength every tick; bobs like an undamped spring.
#   ACTIVE_CONTROL -- notebook 15's HoverControl: just enough force to hold a
#                     target height, damped by vertical speed, so it settles.
enum PushMode { STEADY, ACTIVE_CONTROL }
var push_mode: PushMode = PushMode.STEADY

# Whether horizontal speed decays to a stop in midair with no movement key held.
# On, you can brake mid-jump. Off, you keep sailing. An airborne steelpush is
# exempt either way -- see _apply_ground_movement().
var air_braking_enabled: bool = true


func _ready() -> void:
	carried_coin.add_collision_exception_with(self)
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

	# While carried, the player owns the coin's position outright.
	if carried_coin.is_carried:
		carried_coin.global_position = global_position + Vector2(0, 13)

	# States that commit to an animation -- Attack, Hurt -- refuse every entry
	# trigger below until they finish. Everything else can be acted out of
	# freely, so you can still jump or attack out of a push.
	if state_machine.current_state.is_interruptible():
		_poll_state_entry_inputs()

	# Both toggles are polled here, unconditionally, so they respond whatever
	# state you happen to be in.
	if Input.is_action_just_pressed("toggle_control_mode"):
		push_mode = PushMode.ACTIVE_CONTROL if push_mode == PushMode.STEADY else PushMode.STEADY
		# Printed as well as shown on the HUD, so a key that appears to do
		# nothing can be told apart from a key that is not arriving at all.
		print("[toggle] push mode -> ", PushMode.keys()[push_mode])
	if Input.is_action_just_pressed("toggle_air_braking"):
		air_braking_enabled = not air_braking_enabled
		print("[toggle] midair braking -> ", "ON" if air_braking_enabled else "OFF")
	# Testing affordance, not a mechanic -- see coin.gd's recall().
	if Input.is_action_just_pressed("reset_hover"):
		carried_coin.recall()
		print("[toggle] coin recalled to hand")
	_update_toggle_readout()

	state_machine.physics_process(delta)

	if state_machine.current_state.is_in_group("move_states"):
		_apply_ground_movement()
	else:
		velocity.x = 0

	# Added after the movement gate above, so a state that locks velocity.x to 0
	# cannot wipe out recoil produced on the same tick.
	velocity += pending_recoil

	move_and_slide()


func _poll_state_entry_inputs() -> void:
	# Each check guards only against re-entering the state it is already in;
	# whether the CURRENT state will tolerate being left at all is decided by
	# the caller, which asks it.
	var current_state_name: String = state_machine.current_state.name
	if Input.is_action_just_pressed("jump") and is_on_floor() and current_state_name != "Jump":
		state_machine.transition_to("Jump")
	if Input.is_action_just_pressed("attack"):
		state_machine.transition_to("Attack")
	if Input.is_action_just_pressed("coin_target") and current_state_name != "CoinTarget":
		state_machine.transition_to("CoinTarget")
	if Input.is_action_just_pressed("coin_shoot") and current_state_name != "CoinShoot":
		state_machine.transition_to("CoinShoot")


func _apply_ground_movement() -> void:
	# velocity.x updates whether grounded or airborne, so horizontal control is
	# kept during Jump or CoinShoot in midair.
	var direction := Input.get_axis("move_left", "move_right")
	if direction:
		velocity.x = direction * SPEED
	else:
		# No input: horizontal speed decays to a stop. SPEED as the step size
		# means it stops within one tick.
		#
		# Exempt while airborne under a push. Recoil is added to velocity AFTER
		# this function runs, so decaying here would wipe out everything built up
		# so far and leave only the newest tick's worth -- turning real sideways
		# acceleration into a slow creep. On the ground it still decays, since
		# you are standing on friction.
		var drifting_from_a_push: bool = (not is_on_floor()
			and state_machine.current_state.name == "CoinShoot")
		var braking_allowed: bool = is_on_floor() or air_braking_enabled
		if braking_allowed and not drifting_from_a_push:
			velocity.x = move_toward(velocity.x, 0, SPEED)

	# Only Idle and Run may swap into each other here. Firing this from any
	# other move_state would yank you out of it -- holding coin_shoot while
	# standing still would snap back to Idle and cancel the push before it
	# built up. Every other state manages its own exit condition.
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


func find_metal_in_range() -> Array:
	# Every piece of metal close enough to be worth pushing. Anything in the
	# "metal" group counts, so adding metal to a level needs no changes here.
	#
	# Range and its falloff are a stated modelling choice, not canon -- see
	# sim/steelpush.py. Past MAX_RANGE_M a push delivers nothing, so those
	# bodies are not targets at all.
	var range_px: float = MAX_RANGE_M * PIXELS_PER_METER
	var found: Array = []
	for metal in get_tree().get_nodes_in_group("metal"):
		if metal == carried_coin and carried_coin.is_carried:
			continue  # your own hand is not something to push off
		if global_position.distance_to(metal.global_position) <= range_px:
			found.append(metal)
	return found


func take_hit() -> void:
	# No caller yet -- there is no health/hit system built. This just gives
	# one a stable door in later without needing to know FSM internals.
	state_machine.transition_to("Hurt")


func _on_animated_sprite_2d_animation_finished() -> void:
	if state_machine.current_state.is_in_group("root_states"):
		state_machine.transition_to("Idle")


func _update_toggle_readout() -> void:
	# Rebuilt every tick rather than on change, so the display can never fall
	# out of step with the actual setting.
	var push_mode_text: String = "Steady" if push_mode == PushMode.STEADY else "Active control"
	var air_braking_text: String = "On" if air_braking_enabled else "Off"
	push_mode_readout.text = ("Push mode (C): " + push_mode_text
		+ "\nMidair braking (V): " + air_braking_text)
