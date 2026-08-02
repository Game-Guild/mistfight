class_name PlayerStateMachine
extends Node

# Which named categories each state belongs to. Read this one table to
# answer "what states are in move_states" instead of hunting through every
# state script for it. Godot's built-in Groups do the actual membership
# check (add_to_group / is_in_group) -- not class inheritance, because
# GDScript only allows single inheritance and a state can belong to more
# than one category (CoinShoot is a move_state here, and may end up in a
# targeting_states category too later). Add a state to a category: add its
# name to the array below. Add a whole new category later: one more line
# here, nothing else changes structurally.
const STATE_CATEGORIES := {
	"move_states": ["Idle", "Run", "Jump", "CoinShoot"],
	"root_states": ["Attack", "Hurt"],
}

var current_state: PlayerState
var states_by_name: Dictionary = {}


func _ready() -> void:
	var player_body := get_parent() as Player
	for child in get_children():
		if child is PlayerState:
			states_by_name[child.name] = child
			child.player_body = player_body
			child.state_machine = self
	for category_name in STATE_CATEGORIES:
		for state_name in STATE_CATEGORIES[category_name]:
			states_by_name[state_name].add_to_group(category_name)
	# Does NOT enter a starting state here. StateMachine is Player's child,
	# and Godot runs a child's _ready() before its parent's -- Player's own
	# @onready vars (animated_sprite, reticle, and so on) are not set yet at
	# this point, and Idle.enter() needs them. Player calls start() itself,
	# as the last line of its own _ready(), once those are ready.


func start(initial_state_name: String) -> void:
	current_state = states_by_name[initial_state_name]
	current_state.enter("")


func physics_process(delta: float) -> void:
	current_state.physics_process(delta)


func transition_to(new_state_name: String) -> void:
	if not states_by_name.has(new_state_name):
		push_error("PlayerStateMachine: no state named " + new_state_name)
		return
	var previous_state_name: String = current_state.name
	current_state.exit()
	current_state = states_by_name[new_state_name]
	current_state.enter(previous_state_name)
