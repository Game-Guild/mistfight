class_name CoinInventory
extends Node

# How many coins the player has available to shoot, separate from any
# physical Coin node that happens to exist in the world right now. A coin's
# node only exists while it is in hand, in flight, or lying on the ground --
# once it is picked back up, the node is freed and the count here goes up by
# one instead. Issue #5.
#
# Only one coin is ever in play at a time. Pressing shoot draws a fresh one
# from reserve ONLY once the last one has been recovered; while an earlier
# coin is still out there -- thrown, landed, being hovered on -- pressing
# shoot again resumes pushing that same coin instead of drawing a second one.
# That is what keeps the existing hover mechanic (throw once, then tap or
# hold shoot to keep bouncing on the one landed coin) working unchanged.

# 1 in hand plus this many in reserve. Not a canon number -- there is no
# canon count for how many coins an Allomancer carries -- chosen so there is
# enough to throw a few in a row before running dry.
const STARTING_COINS_IN_RESERVE = 4

const COIN_SCENE: PackedScene = preload("res://coin.tscn")

# Coins waiting to be drawn into hand. Does not include coin_in_play below.
var coins_in_reserve: int = STARTING_COINS_IN_RESERVE

# The one coin currently out in the world -- in hand, thrown, or lying on the
# ground -- or null once it has been picked back up (or before the first one
# is ever drawn). Not the same as "in hand": check coin_in_play.is_carried
# for that.
var coin_in_play: RigidBody2D = null

var player: Player

# Where newly spawned coins get added. Has to be a sibling of Player, not a
# child of it -- a coin parented under Player would inherit Player's position
# and get dragged around as the player moves, instead of flying free.
var level_root: Node


func _ready() -> void:
	player = get_parent() as Player
	level_root = player.get_parent()
	# main.tscn ships with one coin already in the player's hand, at the fixed
	# node path "../Coin" -- tests/tunnel_test.gd relies on that same path, so
	# the first coin is placed in the scene rather than spawned here.
	coin_in_play = player.get_node("../Coin")
	_take_ownership_of(coin_in_play)


func draw_coin() -> RigidBody2D:
	# The coin to throw right now, if any.
	#
	# If a coin is already in play, hands it back UNTHROWN only while it is
	# still in hand (is_carried) -- once it has left the hand, returns null,
	# so the caller falls through to pushing whatever is already out there
	# instead of drawing a second coin on top of it.
	#
	# If nothing is in play, spawns a fresh one from reserve and returns it,
	# or returns null if reserve is empty.
	if coin_in_play != null:
		return coin_in_play if coin_in_play.is_carried else null
	if coins_in_reserve <= 0:
		return null
	coins_in_reserve -= 1
	coin_in_play = COIN_SCENE.instantiate()
	level_root.add_child(coin_in_play)
	_take_ownership_of(coin_in_play)
	return coin_in_play


func _take_ownership_of(coin: RigidBody2D) -> void:
	# The setup every coin drawn into play needs, whether it is the one
	# main.tscn starts with or one draw_coin() just spawned -- one place for
	# both paths so neither can forget a step the other remembers.
	coin.is_carried = true
	coin.add_collision_exception_with(player)
	coin.picked_up.connect(_on_coin_picked_up)


func _on_coin_picked_up(coin: RigidBody2D) -> void:
	coin.picked_up.disconnect(_on_coin_picked_up)
	coin.queue_free()
	coin_in_play = null
	coins_in_reserve += 1
