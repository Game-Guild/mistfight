class_name PlayerState
extends Node

# Every state script extends this. Methods are named enter/exit/
# physics_process WITHOUT Godot's underscore prefix on purpose: these are
# plain Node children that sit in the tree the whole time the game runs. If
# this were named _physics_process, Godot would call it on every state node
# every tick, active or not -- not just whichever one is current.

var player_body: Player
var state_machine: PlayerStateMachine


func is_interruptible() -> bool:
	# Whether pressing another action button can pull the player out of this
	# state before it has finished. States that commit to an animation override
	# this and return false, so a swing plays out instead of being cancelled
	# halfway. Player._physics_process checks it before any entry trigger.
	return true


func enter(_previous_state_name: String) -> void:
	pass


func exit() -> void:
	pass


func physics_process(_delta: float) -> void:
	pass
