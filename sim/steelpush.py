"""Allomantic steel: the Steelpush.

A push is a force PAIR along the line between the pusher's center and a metal
target's center — Newton's third law, no exceptions. The pusher is shoved
away from the metal and the metal is shoved away from the pusher, with equal
and opposite force.

Whether anything dramatic happens depends entirely on the bodies involved,
not on this class. A coin in midair rockets off and absorbs almost no
reaction before leaving range; a coin pinned against the ground cannot move,
so the pusher takes the full launch. None of that is special-cased — it
falls out of the force pair plus the world's ground constraint.

Multiple targets: a Coinshot can push on several metals at once (a tripod of
coins to fly, a spray of coins at a target). One Steelpush can hold a list
of targets. How the push divides across them is NOT settled by canon —
Coppermind and Word of Brandon are silent on multi-target force division
(checked 2026-06-12; the only "split" rule in the wild is the Mistborn
Adventure Game RPG, and that splits metal CONSUMPTION, not force). So this
is a stated modeling choice, grounded in the canon that IS clear:

  Canon: push strength is proportional to the Allomancer's weight, and if an
  anchor holds, the force reflects back onto the Allomancer. So the
  Allomancer can only brace against a bounded total reaction.

  Our choice: strength_newtons is the Allomancer's TOTAL push budget. Each
  target demands the force a lone push would give it (full strength times the
  distance falloff); if the demands sum to more than the budget, every target
  is scaled down by the same factor so the total delivered force equals the
  budget. Push one point-blank anchor and it gets the whole budget; push
  three and they share it. A single target reduces exactly to the old
  behavior, so every earlier push result is unchanged.

Push strength falls off linearly with distance, reaching zero at max_range.
Canon says pushes weaken with distance (≈ inversely with distance); the
LINEAR shape is our modeling choice, stated here so nobody mistakes it for
lore.
"""

import numpy as np


class Steelpush:
    def __init__(self, pusher, targets, strength_newtons, max_range_m=16.0):
        # `targets` may be a single Body or a list of them.
        target_list = list(targets) if isinstance(targets, (list, tuple)) else [targets]
        for target in target_list:
            if not target.is_metal:
                raise ValueError(f"{target.name} is not metal; steel can't touch it")
        self.pusher = pusher
        self.targets = target_list
        self.strength_newtons = float(strength_newtons)
        self.max_range_m = float(max_range_m)
        self.active = False

    @property
    def target(self):
        """Backward-compatible accessor for the single-target case."""
        return self.targets[0]

    def apply_forces(self):
        if not self.active:
            return

        # 1. Each in-range target demands the force a lone push would give it:
        #    full strength scaled by the linear distance falloff.
        demands = []  # (target, direction_to_pusher, demand_magnitude)
        total_demand = 0.0
        for target in self.targets:
            offset = self.pusher.position - target.position
            distance = float(np.linalg.norm(offset))
            if distance >= self.max_range_m:
                continue  # out of range, this line finds nothing
            if distance < 1e-9:
                # Degenerate: bodies coincident. Push straight up so the math
                # stays finite.
                direction_to_pusher = np.array([0.0, 1.0])
            else:
                direction_to_pusher = offset / distance
            demand = self.strength_newtons * (1.0 - distance / self.max_range_m)
            demands.append((target, direction_to_pusher, demand))
            total_demand += demand

        if not demands:
            return

        # 2. Cap the total delivered force at the Allomancer's strength budget.
        #    With one target this scale is always 1 (a lone demand never
        #    exceeds the budget), so single-target pushes are unchanged.
        scale = min(1.0, self.strength_newtons / total_demand)

        for target, direction_to_pusher, demand in demands:
            force_on_pusher = direction_to_pusher * (demand * scale)
            self.pusher.apply_force(force_on_pusher)
            target.apply_force(-force_on_pusher)
