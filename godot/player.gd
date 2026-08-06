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
# The player's mass in kilograms. A var, not a const, because Iron feruchemy
# (issue #21) will need to change it at runtime -- storing or tapping weight
# rewrites this field, conserving momentum the way sim/bodies.py's
# change_mass() does. Nothing does that yet; this just makes the field able
# to hold a live value instead of being baked into the script text, and
# gives hover_pusher.gd's own copy (see that file) one place to read from.
const DEFAULT_MASS_KG = 80.0
var mass_kg: float = DEFAULT_MASS_KG
const AIM_RADIUS_PX = 20
const MAX_RANGE_M = 16.0
# This project's world runs at Godot's default gravity, 980 px/s^2 (measured
# directly from this project's own fall data: velocity climbed 16.333 px/s
# per tick at 60 ticks/second = 980). Real gravity is 9.81 m/s^2 (sim/world.py).
# 980 / 9.81 = ~100, so 1 meter in the sim equals ~100 pixels here.
const PIXELS_PER_METER = 100.0

# Quadratic air drag, ported from sim/air.py (issue #18): drag force = -0.5 *
# air density * drag coefficient * cross-section area * speed * velocity.
# DRAG_COEFFICIENT and BODY_RADIUS_M are sim.Body's own defaults for a
# sphere -- the same choice hover_pusher.gd already made for this same body,
# and notebook 15 never overrode either for Wax, so this doesn't either.
const AIR_DENSITY_KG_PER_M3 = 1.225
const DRAG_COEFFICIENT = 0.47
const BODY_RADIUS_M = 0.3

@onready var state_machine: PlayerStateMachine = $StateMachine
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var reticle: Polygon2D = $Reticle
@onready var steel_lines: Node2D = $SteelLines
@onready var push_arrow: Node2D = $PushArrow
# Which coins the player has, and which one (if any) is in hand right now.
# Issue #5.
@onready var coin_inventory: CoinInventory = $CoinInventory
@onready var push_mode_readout: Label = $"../HUD/Readouts/PushModeReadout"

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

# Half-angle of the selection wedge, in degrees. Metal within this many degrees
# of where you are aiming gets pushed; metal outside it is ignored even though
# it is in range and still has a steel line.
#
# Width is a real trade, not a convenience. The push divides a fixed total
# budget across everything selected and those contributions add as vectors, so a
# narrow wedge concentrates on a few aligned anchors and launches hard, while a
# wide one spreads across anchors that partly cancel and gives a weaker net push
# from a more braced stance.
var cone_half_angle_degrees: float = 30.0
const CONE_MIN_HALF_ANGLE_DEGREES = 5.0
# 180 selects everything in range, which is the same as having no wedge at all.
const CONE_MAX_HALF_ANGLE_DEGREES = 180.0
const CONE_STEP_DEGREES = 5.0


# --- Three ways of choosing what to push --------------------------------------
#
# All three sit on top of identical physics and none is more faithful than the
# others, because canon has no controller in it. They differ only in how many
# inputs it takes to say what you mean. Cycle with M and compare.
#
#   FREE_WEDGE -- aim a wedge with the mouse, scroll to change its width.
#                 Continuous and precise, but it takes a whole aim to operate.
#
#   QUADRANTS  -- four fixed 90-degree sectors, toggled with 1-4. A quadrant is
#                 just a wedge with a snapped direction and a fixed width, and
#                 turning on 2 and 3 together makes one 180-degree wedge
#                 pointing down. Far faster to state a rough direction, and it
#                 scales to a sphere if this ever goes 3D.
#
#   PAINTED    -- pick metal by identity rather than direction. Hold P and sweep
#                 the wedge over things to add them; X clears. They stay
#                 selected wherever they go, because you chose that object, not
#                 that direction. This is the one that supports throwing a coin
#                 and riding it, or pushing one specific mechanism in a puzzle.
#
# Note the asymmetry, and that it is deliberate. The first two select by WHERE
# something is, so they must be re-evaluated every frame: the direction to a
# target decides which way the force goes, so metal drifting behind you would
# silently invert your push. The third selects by WHICH thing it is, so no
# amount of drifting changes what you meant, and it never re-evaluates.
enum SelectionMode { FREE_WEDGE, QUADRANTS, PAINTED }
var selection_mode: SelectionMode = SelectionMode.FREE_WEDGE

# Which quadrants are switched on, indexed 0-3 for quadrants 1-4. Numbered
# clockwise from top-right, so 2 and 3 are the bottom pair and 1 and 4 the top.
# Defaults to the bottom half, which is the one you want for launching upward.
var quadrant_enabled: Array = [false, true, true, false]

# Metal picked by identity in PAINTED mode. Survives anything except being
# cleared, or the node itself ceasing to exist.
var painted_targets: Array = []

# Whether horizontal speed decays to a stop in midair with no movement key held.
# On, you can brake mid-jump. Off, you keep sailing. An airborne steelpush is
# exempt either way -- see _apply_ground_movement().
var air_braking_enabled: bool = true


func _ready() -> void:
	# res:// is read-only in an exported build, so logging there works from the
	# editor and crashes anywhere else. OS.has_feature("editor") is true when
	# running the project directly with the Godot binary -- including headless
	# test runs -- and false in an export, which is exactly the distinction
	# needed. user:// resolves to the app data folder and is always writable.
	var log_directory: String = "res://" if OS.has_feature("editor") else "user://"
	debug_log = FileAccess.open(log_directory + "player_debug.log", FileAccess.WRITE)
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
	_apply_air_drag(delta)

	# While carried, the player owns the coin's position outright. coin_in_play
	# can be null (nothing left in reserve to hold), so this has to check
	# before it reads anything off it.
	if coin_inventory.coin_in_play != null and coin_inventory.coin_in_play.is_carried:
		coin_inventory.coin_in_play.global_position = global_position + Vector2(0, 13)

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
	_poll_selection_inputs()
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


func _unhandled_input(event: InputEvent) -> void:
	# The wedge is resized here rather than in _physics_process because a mouse
	# wheel press and release land in the same instant -- polling for it on a
	# fixed tick misses most of them.
	if event.is_action_pressed("widen_cone"):
		cone_half_angle_degrees = min(
			cone_half_angle_degrees + CONE_STEP_DEGREES, CONE_MAX_HALF_ANGLE_DEGREES)
	elif event.is_action_pressed("narrow_cone"):
		cone_half_angle_degrees = max(
			cone_half_angle_degrees - CONE_STEP_DEGREES, CONE_MIN_HALF_ANGLE_DEGREES)


func _poll_selection_inputs() -> void:
	if Input.is_action_just_pressed("cycle_selection_mode"):
		selection_mode = ((selection_mode + 1) % SelectionMode.size()) as SelectionMode
		print("[selection] mode -> ", SelectionMode.keys()[selection_mode])

	# Quadrant toggles are live in every mode, not just QUADRANTS. Leaving them
	# settable while you are in another mode means you can set up the quadrants
	# you want before switching to them.
	for quadrant_number in range(1, 5):
		if Input.is_action_just_pressed("quadrant_%d" % quadrant_number):
			var index: int = quadrant_number - 1
			quadrant_enabled[index] = not quadrant_enabled[index]
			print("[selection] quadrant %d -> %s"
				% [quadrant_number, "on" if quadrant_enabled[index] else "off"])

	# Painting runs while held, so sweeping the mouse paints a swathe rather
	# than picking one thing per press.
	if Input.is_action_pressed("paint_targets"):
		paint_targets_under_wedge()
	if Input.is_action_just_pressed("clear_targets"):
		painted_targets.clear()
		print("[selection] painted targets cleared")


func aim_direction() -> Vector2:
	# Where the wedge points. Read from the mouse directly rather than from the
	# reticle, so aiming works whether or not the reticle happens to be on
	# screen.
	var to_mouse: Vector2 = get_local_mouse_position()
	if to_mouse.length() < 0.001:
		return Vector2.DOWN
	return to_mouse.normalized()


func select_targets() -> Array:
	# The metal a push actually acts on, under whichever model is active.
	#
	# Everything in range still gets a steel line regardless, because an
	# Allomancer sees all of it. Seeing metal and choosing to push it are
	# different things and the display keeps them visually separate.
	match selection_mode:
		SelectionMode.QUADRANTS:
			return _select_by_quadrant()
		SelectionMode.PAINTED:
			return _select_painted()
		_:
			return _select_by_wedge(aim_direction(), cone_half_angle_degrees)


func _select_by_wedge(direction: Vector2, half_angle_degrees: float) -> Array:
	var half_angle: float = deg_to_rad(half_angle_degrees)
	var selected: Array = []
	for metal in find_metal_in_range():
		var to_metal: Vector2 = metal.global_position - global_position
		# angle_to() is signed, so either side of the aim counts the same.
		if abs(direction.angle_to(to_metal)) <= half_angle:
			selected.append(metal)
	return selected


func _select_by_quadrant() -> Array:
	var selected: Array = []
	for metal in find_metal_in_range():
		if quadrant_enabled[quadrant_index_of(metal.global_position - global_position)]:
			selected.append(metal)
	return selected


func quadrant_index_of(offset: Vector2) -> int:
	# Quadrants numbered clockwise from top-right, returned zero-based. Godot's
	# y axis points DOWN the screen, so a negative y is up.
	#   0 -> quadrant 1, top-right      1 -> quadrant 2, bottom-right
	#   3 -> quadrant 4, top-left       2 -> quadrant 3, bottom-left
	if offset.x >= 0.0:
		return 0 if offset.y < 0.0 else 1
	return 3 if offset.y < 0.0 else 2


func _select_painted() -> Array:
	# Painted metal stays selected wherever it goes. The only thing that removes
	# it is clearing, or the node being freed -- which has to be checked, because
	# holding a reference to a deleted node crashes on access.
	var still_alive: Array = []
	for metal in painted_targets:
		if is_instance_valid(metal):
			still_alive.append(metal)
	painted_targets = still_alive
	return painted_targets


func paint_targets_under_wedge() -> void:
	# Add whatever the wedge is currently over to the painted set. Called every
	# tick the paint key is held, so sweeping the mouse paints a swathe.
	for metal in _select_by_wedge(aim_direction(), cone_half_angle_degrees):
		if not painted_targets.has(metal):
			painted_targets.append(metal)


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


func _apply_air_drag(delta: float) -> void:
	# Same formula and constants hover_pusher.gd already uses for this same
	# body, ported to the live game (issue #18). Runs every tick, grounded or
	# not, matching sim/air.py's AirDrag power: it applies to every non-fixed
	# body unconditionally, not just falling ones. At ground running speed
	# (3 m/s) the force this produces is under a newton, so it's harmless
	# there -- it only starts to matter at the speeds a real fall reaches.
	var speed_m_per_s: float = velocity.length() / PIXELS_PER_METER
	if speed_m_per_s < 0.001:
		return
	var cross_section_area_m2: float = PI * BODY_RADIUS_M * BODY_RADIUS_M
	var drag_force_n: float = (0.5 * AIR_DENSITY_KG_PER_M3 * DRAG_COEFFICIENT
		* cross_section_area_m2 * speed_m_per_s * speed_m_per_s)
	var drag_force_px: float = drag_force_n * PIXELS_PER_METER
	velocity += -velocity.normalized() * drag_force_px / mass_kg * delta


func compute_animation_offset_y() -> float:
	# The vertical anchor point used by aiming: half the height of the
	# current animation frame's visible (non-transparent) pixels, offset
	# from the frame's true center. Only CoinTarget reads this today, so
	# it's computed on demand there instead of unconditionally every tick.
	var texture: Texture2D = animated_sprite.sprite_frames.get_frame_texture(animated_sprite.animation, animated_sprite.frame)
	var visible_area: Rect2i = texture.get_image().get_used_rect()  # box around the actual non-transparent pixels
	var frame_height: float = texture.get_height()
	return (visible_area.position.y + visible_area.position.y + visible_area.size.y) / 2.0 - frame_height / 2.0


func compute_pushes(targets: Array, total_budget_n: float) -> Array:
	# How a push divides across several pieces of metal at once. Ported from
	# sim/steelpush.py, whose docstring records that this split is NOT settled
	# by canon and explains the reasoning behind the choice made there.
	#
	# The rule: total_budget_n is the whole push, not a per-target amount. Each
	# target demands the force a lone push would give it at its distance; if the
	# demands add up to more than the budget, everything scales down equally so
	# the total delivered equals the budget. One target reduces exactly to the
	# single-target behaviour, so nothing changes for a lone coin.
	#
	# Each entry is { target, direction, force_px }, where direction points from
	# the player TOWARD the target -- so the target is shoved along it and the
	# player recoils against it. Equal and opposite, as a force pair must be.
	var demands: Array = []
	var total_demand_n: float = 0.0
	for target in targets:
		var offset: Vector2 = target.global_position - global_position
		var distance_m: float = offset.length() / PIXELS_PER_METER
		if distance_m >= MAX_RANGE_M or distance_m < 0.0001:
			continue
		var demand_n: float = total_budget_n * (1.0 - distance_m / MAX_RANGE_M)
		demands.append({"target": target, "direction": offset.normalized(), "demand_n": demand_n})
		total_demand_n += demand_n

	if demands.is_empty():
		return []

	var scale: float = min(1.0, total_budget_n / total_demand_n)
	var pushes: Array = []
	for demand in demands:
		pushes.append({
			"target": demand.target,
			"direction": demand.direction,
			"force_px": demand.demand_n * scale * PIXELS_PER_METER,
		})
	return pushes


func net_push_on_player(pushes: Array) -> Vector2:
	# What the player actually feels: every target's reaction added as a vector.
	# The total is capped in magnitude by the budget, but these are directions,
	# so targets on opposite sides cancel. Push off two things either side of you
	# and you go nowhere while still spending the same steel.
	var net: Vector2 = Vector2.ZERO
	for push_item in pushes:
		net -= push_item.direction * push_item.force_px
	return net


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
		# Your own held coin is not something you can push off. Someone ELSE's
		# held coin is fair game (once that exists), which is why this is an
		# identity check against the one coin you hold, not a general "is
		# anyone carrying this" flag.
		if metal == coin_inventory.coin_in_play and metal.is_carried:
			continue
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
	var held_coin_count: int = 1 if (coin_inventory.coin_in_play != null and coin_inventory.coin_in_play.is_carried) else 0
	push_mode_readout.text = ("Push mode (C): " + push_mode_text
		+ "\nMidair braking (V): " + air_braking_text
		+ "\nCoins: %d in hand, %d in reserve" % [held_coin_count, coin_inventory.coins_in_reserve]
		+ "\nSelect (M): " + SelectionMode.keys()[selection_mode] + "   " + _selection_detail()
		+ "\n%d of %d metal in range selected"
			% [select_targets().size(), find_metal_in_range().size()])


func _selection_detail() -> String:
	# The one extra fact that matters for whichever model is running.
	match selection_mode:
		SelectionMode.QUADRANTS:
			var on: Array = []
			for quadrant_number in range(1, 5):
				if quadrant_enabled[quadrant_number - 1]:
					on.append(str(quadrant_number))
			return "(1-4) on: " + ("none" if on.is_empty() else ", ".join(on))
		SelectionMode.PAINTED:
			return "(hold P to paint, X to clear) %d painted" % painted_targets.size()
		_:
			return "(scroll) %d deg wide" % (cone_half_angle_degrees * 2)
