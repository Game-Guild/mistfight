extends Node

# BubbleClock -- the one place any script asks "what is my local time this
# tick." Registered as an autoload (see project.godot's [autoload] section)
# so any script, regardless of what it extends, can call
# BubbleClock.local_dt(delta, my_position) the same way.
#
# Mirrors sim/world.py's time_factor_at(): walk every live bubble, return
# the first one that contains the given position, or no scaling at all if
# none do. Bubbles never move once placed (sim/bubbles.py: "anchored where
# they're cast"), and this walks whatever is currently in the "bubbles"
# group fresh on every call -- the same pattern player.gd's
# find_metal_in_range() already uses for the "metal" group -- so there is
# nothing to cache and no requirement on when in a tick this gets called.
# Each caller reads its OWN position at whatever point in its OWN
# _physics_process it chooses, the same way the sim reads a body's position
# from the end of the previous tick before scaling this tick's delta.


func local_dt(world_delta: float, position: Vector2) -> float:
	for bubble_region in get_tree().get_nodes_in_group("bubbles"):
		if bubble_region.bubble.contains(position):
			return world_delta * bubble_region.bubble.time_factor
	return world_delta
