extends Node2D

# Single trigger for godot/tests/bubble_drop_test.tscn. Two-phase: while the
# coins are held (a fresh scene, or after a reset), pressing
# drop_test_coins releases all three at once and starts their stopwatches
# and trajectory trackers. Once they're falling or have landed, pressing it
# again resets the whole experiment back to the held state instead of
# restarting the clocks on coins that are already moving or already down --
# Elliott's catch (2026-08-06): re-pressing mid-drop was silently resetting
# each stopwatch's timer while the coin underneath it kept falling
# untouched, which reads as a real measurement but isn't one.
#
# coin.release() (coin.gd:106-116) is the same method the player uses to
# let go of a coin -- nothing new added there, this just calls it on three
# coins at once instead of one. The reset path sets coin.is_carried back to
# true directly (coin.gd:151-153 already treats that as "frozen, do
# nothing" -- no coin.gd change needed for that either) and restores each
# coin's position from what was recorded here in _ready(), before anything
# had a chance to move.

var original_coin_positions: Dictionary = {}  # coin -> Vector2, captured once in _ready(), before any physics has run


func _ready() -> void:
	for coin in get_tree().get_nodes_in_group("test_coins"):
		original_coin_positions[coin] = coin.position


func _physics_process(_delta: float) -> void:
	if not Input.is_action_just_pressed("drop_test_coins"):
		return

	var coins: Array = get_tree().get_nodes_in_group("test_coins")
	var coins_are_held: bool = coins.size() > 0 and coins.all(func(coin): return coin.is_carried)

	if coins_are_held:
		print("[bubble_drop_trigger] drop -- releasing %d coin(s)" % coins.size())
		for coin in coins:
			coin.release()
		for stopwatch in get_tree().get_nodes_in_group("test_stopwatches"):
			stopwatch.start()
		for dots in get_tree().get_nodes_in_group("test_trajectory_dots"):
			dots.start()
	else:
		print("[bubble_drop_trigger] reset")
		for coin in coins:
			coin.velocity = Vector2.ZERO
			coin.position = original_coin_positions[coin]
			coin.is_carried = true
		for stopwatch in get_tree().get_nodes_in_group("test_stopwatches"):
			stopwatch.reset()
		for dots in get_tree().get_nodes_in_group("test_trajectory_dots"):
			dots.reset()
