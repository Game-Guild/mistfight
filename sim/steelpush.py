"""Allomantic steel: the Steelpush.

A push is a force PAIR along the line between the pusher's center and a metal
target's center -- Newton's third law, no exceptions. The pusher is shoved
away from the metal and the metal is shoved away from the pusher, with equal
and opposite force.

Whether anything dramatic happens depends entirely on the bodies involved,
not on this class. A coin in midair rockets off and absorbs almost no
reaction before leaving range; a coin pinned against the ground cannot move,
so the pusher takes the full launch. None of that is special-cased -- it
falls out of the force pair plus the world's ground constraint.

Multiple targets: a Coinshot can push on several metals at once (a tripod of
coins to fly, a spray of coins at a target). One Steelpush can hold a list
of targets. How the push divides across them is NOT settled by canon
(checked 2026-06-12; the only "split" rule in the wild is the Mistborn
Adventure Game RPG, and it splits metal CONSUMPTION, not force). Stated
modeling choice, grounded in the canon that IS clear (push tracks the
Allomancer's weight; force reflects onto them, so they brace a bounded
total): strength_newtons is the TOTAL push budget. Each target demands the
force a lone push would give it; if the demands sum past the budget, every
target scales down equally so the total delivered equals the budget. One
target reduces exactly to the old behavior, so earlier results are unchanged.

Metal reserve and flaring (steel as a consumed resource):

  - steel_grams is the Coinshot's metal supply. None means unlimited (the
    default, so every experiment written before this still behaves the
    same). A finite supply burns down while the pusher is burning and the push
    dies when it hits zero.
  - burn_grams_per_second is the base consumption rate, charged on the
    pusher's LOCAL clock -- burning is flesh-bound chemistry, so a Coinshot
    inside a bendalloy bubble burns through their metal faster in world
    time, like healing and poison (notebooks 04, 06).
  - flare is a multiplier (>= 1) for burning the metal harder. Stated
    modeling choice: flaring multiplies the push by `flare` but the burn
    rate by `flare` SQUARED -- double your push, quadruple your burn. So
    flaring is a burst, not a cruising mode; canon says flaring "burns
    brighter for more power, faster," and the square is our cost curve.

Push strength falls off linearly with distance, reaching zero at max_range.
Canon says pushes weaken with distance (roughly as 1/distance); the LINEAR
shape is our modeling choice, stated so nobody mistakes it for lore.
"""

import numpy as np


class Steelpush:
    def __init__(self, pusher, targets, strength_newtons, max_range_m=16.0,
                 steel_grams=None, burn_grams_per_second=0.0, flare=1.0):
        # `targets` may be a single Body or a list of them.
        target_list = list(targets) if isinstance(targets, (list, tuple)) else [targets]
        for target in target_list:
            if not target.is_metal:
                raise ValueError(f"{target.name} is not metal; steel can't touch it")
        self.pusher = pusher
        self.targets = target_list
        self.strength_newtons = float(strength_newtons)
        self.max_range_m = float(max_range_m)
        self.steel_grams = steel_grams          # None = unlimited
        self.burn_grams_per_second = float(burn_grams_per_second)
        self.flare = float(flare)
        self.active = False

    @property
    def target(self):
        """Backward-compatible accessor for the single-target case."""
        return self.targets[0]

    @property
    def out_of_metal(self):
        return self.steel_grams is not None and self.steel_grams <= 0.0

    def apply_forces(self):
        if not self.active or self.out_of_metal:
            return

        # Flaring scales the whole push budget.
        effective_strength = self.strength_newtons * self.flare

        # 1. Each in-range target demands the force a lone push would give it.
        demands = []  # (target, direction_to_pusher, demand_magnitude)
        total_demand = 0.0
        for target in self.targets:
            offset = self.pusher.position - target.position
            distance = float(np.linalg.norm(offset))
            if distance >= self.max_range_m:
                continue  # out of range, this line finds nothing
            if distance < 1e-9:
                direction_to_pusher = np.array([0.0, 1.0])  # coincident: push up
            else:
                direction_to_pusher = offset / distance
            demand = effective_strength * (1.0 - distance / self.max_range_m)
            demands.append((target, direction_to_pusher, demand))
            total_demand += demand

        # Burn metal while the pusher is burning, whether or not a target is in range.
        self._burn_metal()

        if not demands:
            return

        # 2. Cap the total delivered force at the (flared) strength budget.
        scale = min(1.0, effective_strength / total_demand)
        for target, direction_to_pusher, demand in demands:
            force_on_pusher = direction_to_pusher * (demand * scale)
            self.pusher.apply_force(force_on_pusher)
            target.apply_force(-force_on_pusher)

    def _burn_metal(self):
        if self.steel_grams is None or self.burn_grams_per_second == 0.0:
            return
        local_dt = self.pusher.local_dt_seconds
        if local_dt is None:
            return
        burned = self.burn_grams_per_second * (self.flare ** 2) * local_dt
        self.steel_grams = max(0.0, self.steel_grams - burned)
