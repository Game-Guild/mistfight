extends Node

# Unattended reproduction of issue #11: the coin punching through solid
# geometry under a sustained steelpush.
#
# This runs the exact scenario from the 2026-08-01/02 playtest -- stand on the
# floor with a caught coin sitting just below you, hold the shoot button, never
# let go -- with nobody at the keyboard, and prints one verdict line at the
# end. The point is not automation for its own sake. It is that every
# experiment gets measured the same way, so that two runs differing in exactly
# one variable can actually be compared. A human holding a key for ten seconds
# cannot hold it the same way twice.
#
# Run it like this (from the repo root), one variable changed per run:
#
#   godot --headless --path godot res://tests/tunnel_test.tscn -- --label=baseline
#   godot --headless --path godot res://tests/tunnel_test.tscn -- --label=big-coin --coin-shape-scale=10
#
# Everything after the bare "--" is read by parse_command_line_settings()
# below. Anything not passed keeps the default written next to it.


# --- Settings, each overridable from the command line -----------------------

# Physics ticks to let the scene settle before the push starts. The player
# spawns one pixel above the floor and needs a moment to land and register as
# grounded before the test scenario is actually the scenario.
var settle_ticks: int = 60

# Physics ticks to hold the push for before calling the run a survival. At the
# project's 240 ticks/second this default is 10 seconds of continuous push --
# far longer than the playtest runs that triggered the explosion by hand.
var hold_ticks: int = 2400

# Multiplier on the coin's collision shape size. 1.0 is the shipped 1x3 pixel
# rectangle. This is the knob for the "is the shape simply too small for
# Godot's 2D solver to resolve" hypothesis: it changes ONLY the collision
# shape, never the mass and never the drawn polygon, so any change in outcome
# is attributable to shape size alone.
var coin_shape_scale: float = 1.0

# Continuous collision detection mode on the coin. -1 means "leave whatever
# the scene file set", which is currently 1 (CCD_MODE_CAST_RAY). 0 disables
# it, 2 is CCD_MODE_CAST_SHAPE.
var continuous_collision_mode: int = -1

# Ticks before the push starts to unfreeze the coin and let it fall. Zero
# means the shipped behavior: the coin is still riding on the player, 22
# pixels clear of the floor, when the push begins -- so it gets 22 pixels of
# free runway to accelerate across before anything can stop it. A non-zero
# value drops it first and lets it come to rest on the floor, which is the
# situation sim/steelpush.py describes: "a coin pinned against the ground
# cannot move, so the pusher takes the full launch."
var drop_ticks: int = 0

# Physics ticks per second for this run. -1 keeps the project setting (240).
# This is the knob for "is a faster clock enough", asked properly: if the
# failure is a timestep problem, outcome should improve steadily with rate.
var tick_rate: int = -1

# Pixels to move the player sideways just before the push begins, so the line
# from player to coin is no longer vertical. This is how the grip-versus-skid
# rule gets tested. The coin sits 32.01 px below the player, and grip holds
# while the sideways share of the push stays under 0.6 of the downward share --
# so it should break at 32.01 * 0.6 = 19.2 px of offset. Measured 2026-08-02:
# 18 px grips, 19 px skids.
#
# Keep the push SHORT when testing this (--hold-ticks=20). Recoil throws the
# player up and sideways, which shallows the angle on its own within a fraction
# of a second, so a long hold measures the drift rather than the grip.
var player_offset_x: float = 0.0

# Speed in pixels per second to fire the coin sideways with, instead of pushing
# it. This tests the other half of the problem: a coin already travelling fast
# in open air meeting a wall. There is no throw mechanic in the game yet, so
# this is the only way to produce that situation at all.
var launch_speed_x: float = 0.0

# Switch off the two infinite-plane walls, leaving only the ordinary 50px-wide
# rectangle walls. Those planes were added on 2026-08-02 to stop the coin
# escaping sideways; this checks whether they are still needed.
var disable_infinite_walls: bool = false

# Run a scripted jump instead of a steelpush: jump, hold "move right" for a
# while, let go, and see how far the player coasts afterwards. This is the only
# way to measure what the midair-braking toggle actually does, since the whole
# effect only exists in the moment AFTER the movement key is released.
var jump_test: bool = false

# Force the midair-braking toggle on (1) or off (0) for this run. -1 leaves it
# at whatever player.gd defaults to.
var air_braking: int = -1

# Free-text name for this run, printed in the verdict line so a batch of runs
# can be told apart in the output.
var label: String = "unlabeled"


# --- Where the sealed play area is ------------------------------------------
#
# Read off main.tscn directly rather than guessed. Floor is a
# WorldBoundaryShape2D (an infinite, zero-thickness plane) at y = 270. LeftWall
# sits at x = -150 and RightWall at x = 500, each carrying a 50-pixel-wide
# RectangleShape2D, so each wall spans 25 pixels either side of its centre.
#
# The thresholds below are the FAR side of each surface plus a small margin,
# so "escaped" means the coin came out the other side of something solid, not
# that it dipped a pixel into a contact. No ambiguity about what counts.
const FLOOR_PLANE_Y = 270.0
const LEFT_WALL_FAR_EDGE_X = -175.0
const RIGHT_WALL_FAR_EDGE_X = 525.0
const ESCAPE_MARGIN_PX = 5.0


# --- Live state -------------------------------------------------------------

var coin: RigidBody2D
var player: Node2D
var tick_count: int = 0
var push_started: bool = false
var previous_coin_position: Vector2 = Vector2.ZERO

# Everything worth reporting at the end, gathered as the run goes.
var fastest_speed_seen: float = 0.0

# Horizontal speed tracked on its own, not folded into fastest_speed_seen.
# The push in this scenario points straight down at a flat, horizontal floor,
# so the correct amount of sideways motion is zero. Any horizontal speed at all
# was manufactured by the contact solver, and how much of it there is, is the
# whole question. Mixing it into a single speed number hides exactly the
# quantity being measured.
var fastest_horizontal_speed_seen: float = 0.0
var deepest_penetration_below_floor: float = 0.0
var biggest_single_tick_jump: float = 0.0
var biggest_jump_at_tick: int = 0


func _ready() -> void:
	parse_command_line_settings()
	coin = get_node("../Main/Coin")
	player = get_node("../Main/Player")
	if coin_shape_scale != 1.0:
		apply_coin_shape_scale()
	if continuous_collision_mode >= 0:
		coin.continuous_cd = continuous_collision_mode
	if tick_rate > 0:
		Engine.physics_ticks_per_second = tick_rate
	if disable_infinite_walls:
		# Switch off the two infinite-plane walls so the only things left on the
		# sides are the ordinary 50px-wide rectangle walls. This answers whether
		# the infinite planes are still doing necessary work, or were a
		# workaround for a problem that no longer exists.
		for wall_name in ["Wall", "Wall2"]:
			var wall: StaticBody2D = get_node("../Main/" + wall_name)
			wall.get_node("CollisionShape2D").set_deferred("disabled", true)
		print("[tunnel_test] infinite plane walls disabled; only the 50px rectangle walls remain")
	if air_braking >= 0:
		player.air_braking_enabled = air_braking == 1
	print("[tunnel_test] label=%s settle_ticks=%d hold_ticks=%d coin_shape_scale=%s continuous_cd=%d"
		% [label, settle_ticks, hold_ticks, coin_shape_scale, coin.continuous_cd])


func parse_command_line_settings() -> void:
	# get_cmdline_user_args() returns only the arguments that came after a bare
	# "--" on the command line, so Godot's own flags (--headless and friends)
	# never end up in here. Each one looks like "--name=value".
	for argument in OS.get_cmdline_user_args():
		var name_and_value: PackedStringArray = argument.lstrip("-").split("=")
		if name_and_value.size() != 2:
			continue
		var setting_name: String = name_and_value[0]
		var setting_value: String = name_and_value[1]
		match setting_name:
			"settle-ticks": settle_ticks = int(setting_value)
			"hold-ticks": hold_ticks = int(setting_value)
			"coin-shape-scale": coin_shape_scale = float(setting_value)
			"ccd": continuous_collision_mode = int(setting_value)
			"drop-ticks": drop_ticks = int(setting_value)
			"tick-rate": tick_rate = int(setting_value)
			"player-offset-x": player_offset_x = float(setting_value)
			"launch-speed-x": launch_speed_x = float(setting_value)
			"disable-infinite-walls": disable_infinite_walls = setting_value == "1"
			"jump-test": jump_test = setting_value == "1"
			"air-braking": air_braking = int(setting_value)
			"label": label = setting_value
			_: push_warning("[tunnel_test] ignoring unknown setting: " + argument)


func apply_coin_shape_scale() -> void:
	# duplicate() first: a shape defined in a scene file can be shared between
	# nodes, and resizing a shared resource would silently resize whatever else
	# points at it. Duplicating guarantees this run only touches the coin.
	var collision_shape: CollisionShape2D = coin.get_node("CollisionShape2D")
	var private_shape: RectangleShape2D = collision_shape.shape.duplicate()
	private_shape.size = private_shape.size * coin_shape_scale
	collision_shape.shape = private_shape
	print("[tunnel_test] coin collision shape resized to %s (mass and drawn polygon unchanged)"
		% private_shape.size)


func _physics_process(_delta: float) -> void:
	tick_count += 1

	# Unfreeze the coin early so it falls and comes to rest on the floor before
	# the push begins. player.gd only pins the coin to the player while it is
	# frozen, so clearing the flag is all it takes to let go of it.
	if drop_ticks > 0 and tick_count == settle_ticks - drop_ticks:
		coin.release()
		print("[tunnel_test] coin released at tick %d to fall and settle" % tick_count)

	if jump_test:
		_run_jump_test()
		return

	# Let the player land and settle before starting, then press the shoot
	# button once and never release it. Input.action_press() sets the action as
	# held from the engine's point of view, so player.gd's ordinary
	# is_action_just_pressed / is_action_pressed checks see it exactly as they
	# would see a real key -- the test drives the real code path, not a
	# shortcut around it.
	if tick_count == settle_ticks:
		if player_offset_x != 0.0:
			# Step the player sideways so the push line runs at an angle to the
			# floor instead of straight down at it.
			player.global_position.x += player_offset_x
			print("[tunnel_test] player stepped %s px sideways, now at %s"
				% [player_offset_x, player.global_position])
		if launch_speed_x != 0.0:
			# Fire the coin sideways as a free projectile. It is let go of first,
			# because a carried coin has its position overwritten by the player
			# every tick and would never get to move on its own.
			coin.release()
			coin.velocity = Vector2(launch_speed_x, 0.0)
			print("[tunnel_test] coin launched sideways at %s px/s" % launch_speed_x)
			push_started = true
			previous_coin_position = coin.global_position
			return
		Input.action_press("coin_shoot")
		push_started = true
		previous_coin_position = coin.global_position
		print("[tunnel_test] push started at tick %d, coin at %s" % [tick_count, coin.global_position])
		return
	if not push_started:
		return

	measure_this_tick()

	if coin_has_escaped():
		report_and_quit("escaped")
		return
	if tick_count >= settle_ticks + hold_ticks:
		report_and_quit("survived")


func measure_this_tick() -> void:
	var coin_position: Vector2 = coin.global_position

	var speed: float = coin.velocity.length()
	if speed > fastest_speed_seen:
		fastest_speed_seen = speed

	var horizontal_speed: float = abs(coin.velocity.x)
	if horizontal_speed > fastest_horizontal_speed_seen:
		fastest_horizontal_speed_seen = horizontal_speed

	# How far past the floor plane the coin's centre got. Small values are
	# ordinary contact penetration; large ones mean it is inside the ground.
	var penetration: float = coin_position.y - FLOOR_PLANE_Y
	if penetration > deepest_penetration_below_floor:
		deepest_penetration_below_floor = penetration

	# The signature failure in the logs is a single tick where position leaps
	# hundreds of pixels. Recording the largest such leap, and when it happened,
	# separates "drifted through gradually" from "teleported through in one
	# tick" -- two different bugs that look the same from the outside.
	var jump_this_tick: float = coin_position.distance_to(previous_coin_position)
	if jump_this_tick > biggest_single_tick_jump:
		biggest_single_tick_jump = jump_this_tick
		biggest_jump_at_tick = tick_count
	previous_coin_position = coin_position


func coin_has_escaped() -> bool:
	var coin_position: Vector2 = coin.global_position
	if coin_position.y > FLOOR_PLANE_Y + ESCAPE_MARGIN_PX:
		return true
	if coin_position.x < LEFT_WALL_FAR_EDGE_X - ESCAPE_MARGIN_PX:
		return true
	if coin_position.x > RIGHT_WALL_FAR_EDGE_X + ESCAPE_MARGIN_PX:
		return true
	return false


func report_and_quit(outcome: String) -> void:
	# One line, fixed field order, "RESULT" as the first word so a batch of runs
	# can be pulled out of the output with a single grep.
	var ticks_under_push: int = tick_count - settle_ticks
	print("RESULT label=%s outcome=%s ticks_under_push=%d seconds_under_push=%.3f"
		% [label, outcome, ticks_under_push, ticks_under_push / 240.0]
		+ " coin_position=%s coin_velocity=%s" % [coin.global_position, coin.velocity]
		+ " fastest_speed=%.1f fastest_HORIZONTAL_speed=%.1f deepest_below_floor=%.2f"
			% [fastest_speed_seen, fastest_horizontal_speed_seen, deepest_penetration_below_floor]
		+ " biggest_single_tick_jump=%.2f at_tick=%d" % [biggest_single_tick_jump, biggest_jump_at_tick])
	get_tree().quit()


func _run_jump_test() -> void:
	# Tick-by-tick script: jump and start running right, hold it for a quarter of
	# a second, then let go of everything and watch. With midair braking ON the
	# player should stop dead sideways the instant the key is released. With it
	# OFF they should keep sailing at full running speed.
	var ticks_after_start: int = tick_count - settle_ticks
	if ticks_after_start == 0:
		Input.action_press("jump")
		Input.action_press("move_right")
		print("[jump_test] jumped and holding right, player at %s" % player.global_position)
	elif ticks_after_start == 1:
		Input.action_release("jump")
	elif ticks_after_start == 60:
		Input.action_release("move_right")
		print("[jump_test] released right at tick %d, player at %s velocity.x=%.1f"
			% [ticks_after_start, player.global_position, player.velocity.x])
	elif ticks_after_start == 61:
		print("[jump_test] ONE TICK after release: velocity.x=%.1f" % player.velocity.x)
	elif ticks_after_start >= 180:
		print("RESULT label=%s air_braking=%s final_player_x=%.2f final_velocity_x=%.1f"
			% [label, player.air_braking_enabled, player.global_position.x, player.velocity.x])
		get_tree().quit()
