class_name Player
extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -400.0

# How fast a coin leaves your hand when you flick it, in pixels per second.
# 1500 px/s is 15 metres per second at this project's 100 pixels to the metre,
# or about 34 miles per hour -- a hard flick, well short of a thrown baseball
# (roughly 40 m/s from a professional pitcher).
#
# Stated modelling choice, not canon: the books describe Coinshots flicking or
# dropping a coin and then pushing it, but never say how hard the flick is.
# What matters mechanically is only that it clears your hand -- the steelpush
# does all the real work from there, and reaches thousands of metres per second
# on its own. This number just decides which way the coin is heading when the
# push takes over.
const THROW_SPEED_PX_PER_S = 1500.0
# The total strength of a Steelpush, in newtons. Was a fixed 2000.0, matching
# sim/steelpush.py and notebook 15 exactly. Made adjustable from the inspector
# (select the Player node, look under "Player") so this can be tuned by hand
# without a code change -- lowered here to 1000 to test whether the coin is
# simply being pushed too hard to stay inside the level.
#
# Useful landmarks when turning this dial, all worked out from the numbers
# already in this file (80 kg player, gravity 9.81 m/s^2, max range 16 m):
#
#   below ~793 : the push is weaker than the player's own weight (785 N), so
#                you never leave the ground at all
#          850 : hovers, but only about 1.2 m above the coin
#         1000 : hovers about 3.4 m up
#         2000 : hovers about 9.7 m up  (the original value)
#
# Warning worth reading before spending time here: BOTH halves of the push use
# this one number, because a Steelpush is a force pair -- the same strength
# that shoves the coin is what lifts the player. The coin weighs 0.03 kg and
# the player weighs 80 kg, so the coin always gets 2,667 times the acceleration
# no matter what this is set to. Halving it halves both sides equally, which
# means there is no value that is gentle on the coin and still strong enough to
# lift a person. The whole range that keeps hovering working (roughly 850 to
# 2000) still accelerates the coin by millions of pixels per second squared.
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
@onready var steel_line: Line2D = $"Steel line"
@onready var coin: RigidBody2D = $"../Coin"
@onready var push_mode_readout: Label = $"../HUD/PushModeReadout"

var pending_recoil: Vector2 = Vector2.ZERO
var debug_log: FileAccess


# --- Toggles, both live here on purpose ---------------------------------------
#
# These are whole-game settings, not per-state ones, so they are polled every
# tick from _physics_process below no matter which state is active.
#
# The push mode toggle used to live inside coin_shoot_state.gd, which only runs
# while you are actually mid-push -- so pressing C at any other moment did
# nothing at all, and the only way to change mode was to change it while
# already pushing. That was issue #13.

# How a held steelpush decides its strength.
#   STEADY         -- full strength every tick, whatever the distance formula
#                     allows. Simple, and bobs forever like an undamped spring.
#   ACTIVE_CONTROL -- notebook 15's HoverControl: compute just enough force to
#                     hold a target height, damped by your own vertical speed,
#                     so the hover settles instead of oscillating.
enum PushMode { STEADY, ACTIVE_CONTROL }
var push_mode: PushMode = PushMode.STEADY

# Whether horizontal speed decays to a stop while you are in midair with no
# movement key held.
#   true  -- yes. Ordinary platformer feel: you can brake mid-jump. The default,
#            and how this game has always played.
#   false -- no. Once moving sideways in the air you keep going, which is more
#            physically honest (nothing in midair stops you sideways) but takes
#            away mid-jump control.
# Either way, an airborne steelpush is exempt: braking there would delete the
# recoil drift before it could build. See _apply_ground_movement().
var air_braking_enabled: bool = true


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

	# While the coin is being carried, the player owns its position outright.
	# This used to test coin.freeze, but freeze now means something different:
	# the coin is frozen permanently so Godot's solver never moves it, and
	# coin.gd drives every pixel itself. "Am I still holding it" is its own
	# flag now (see coin.gd's is_carried).
	if coin.is_carried:
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

	# Both toggles are polled here, unconditionally, so they respond whatever
	# state you happen to be in.
	if Input.is_action_just_pressed("toggle_control_mode"):
		push_mode = PushMode.ACTIVE_CONTROL if push_mode == PushMode.STEADY else PushMode.STEADY
		# Printed as well as shown on the HUD so there is a second, independent
		# place to look when a key appears to do nothing. If this line does not
		# appear in the editor's Output panel, the key press is not reaching the
		# game at all and no amount of staring at the HUD will show why.
		print("[toggle] push mode -> ", PushMode.keys()[push_mode])
	if Input.is_action_just_pressed("toggle_air_braking"):
		air_braking_enabled = not air_braking_enabled
		print("[toggle] midair braking -> ", "ON" if air_braking_enabled else "OFF")
	# Testing affordance, not a mechanic -- see coin.gd's recall(). There is one
	# coin and no way to pick it up, so without this you get one throw per run.
	if Input.is_action_just_pressed("reset_hover"):
		coin.recall()
		print("[toggle] coin recalled to hand")
	_update_toggle_readout()

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
		# With no input, horizontal speed decays straight to a stop -- on the
		# ground AND in midair. That is ordinary platformer feel and it is how
		# jumping has always worked here: you can brake mid-jump. SPEED as the
		# step size means "stop within one tick", i.e. instantly.
		#
		# One exception, and only one: while a steelpush is actually happening.
		# Recoil is added to velocity AFTER this function runs (see
		# _physics_process), so this line would wipe out all the sideways recoil
		# built up so far and leave only the single newest tick's worth. At 240
		# ticks a second that turns real sideways acceleration into a constant
		# ~10px/s creep, which is why hovering off to one side of the coin used
		# to give a clean vertical bounce with no drift at all. While airborne
		# under a push, horizontal speed is left alone so the recoil can build.
		# Feet on the ground it still decays, because friction is real and you
		# are standing on it.
		var drifting_from_a_push: bool = (not is_on_floor()
			and state_machine.current_state.name == "CoinShoot")
		# Feet on the ground, friction always stops you -- the air_braking
		# toggle has no say there, because that toggle is about what midair
		# does, and standing on the floor is not midair.
		var braking_allowed: bool = is_on_floor() or air_braking_enabled
		if braking_allowed and not drifting_from_a_push:
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


func update_steel_line_to_coin() -> void:
	# The blue line an Allomancer sees to nearby metal. It now runs from the
	# player to where the coin ACTUALLY is -- the same line the push force acts
	# along in coin_shoot_state.gd -- so what you see on screen and what the
	# physics does are one thing, and cannot drift apart.
	#
	# It used to be drawn to the Reticle instead. The Reticle is an aim
	# direction clamped to a 20px radius: it carried no information about where
	# the coin was or how far away, and pointed somewhere else entirely the
	# moment you aimed away from the coin.
	#
	# Both ends are in the player's own local coordinates, because "Steel line"
	# is a child of Player. Vector2.ZERO is the player's own origin -- the
	# exact point coin_offset is measured from -- and to_local() converts the
	# coin's position in the world into that same local frame.
	steel_line.points = [Vector2.ZERO, to_local(coin.global_position)]


func take_hit() -> void:
	# No caller yet -- there is no health/hit system built. This just gives
	# one a stable door in later without needing to know FSM internals.
	state_machine.transition_to("Hurt")


func _on_animated_sprite_2d_animation_finished() -> void:
	if state_machine.current_state.is_in_group("root_states"):
		state_machine.transition_to("Idle")


func _update_toggle_readout() -> void:
	# One HUD line per toggle, always showing the live value. Rebuilt every tick
	# rather than only when something changes -- it is two string joins, and it
	# means the display can never fall out of step with the actual setting.
	var push_mode_text: String = "Steady" if push_mode == PushMode.STEADY else "Active control"
	var air_braking_text: String = "On" if air_braking_enabled else "Off"
	push_mode_readout.text = ("Push mode (C): " + push_mode_text
		+ "\nMidair braking (V): " + air_braking_text)
