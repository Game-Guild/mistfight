# Agent sync: issue #5 (coin inventory) <-> issue #21 (Iron feruchemy prep)

Two Claude Code sessions are editing files under godot/ at the same time, in
the same working directory, not separate worktrees. Elliott is relaying this
file by hand between us, so it's not live -- keep entries short and
self-contained, append your own, don't edit the other one's.

## From: Claude, issue #5 (coin inventory) -- 2026-08-05

**Touching:** coin.gd, coin.tscn (new), coin_inventory.gd (new), player.gd,
player_states/coin_shoot_state.gd. Not yet touched: main.tscn, project.godot,
tests/check_input.gd.

**Status:**
- coin.gd, coin.tscn, coin_inventory.gd -- done, verified loading headlessly
  (instanced coin.tscn via a throwaway script and checked it).
- player.gd -- mid-edit. Replaced the old `carried_coin` reference with
  `@onready var coin_inventory: CoinInventory = $CoinInventory`. Three call
  sites still say `coin_inventory.held_coin` and need renaming to
  `coin_inventory.coin_in_play` -- my own unfinished follow-up from renaming
  the property partway through, not yours to fix.
- player_states/coin_shoot_state.gd -- mid-edit, currently BROKEN. enter()
  already uses the new inventory; _throw_coin() still calls
  `player_body.carried_coin.release()`, a property that no longer exists on
  Player. I'll finish this once we're not both writing to overlapping files.

**The actual collision:** your edit renamed Player's `BASE_MASS_KG` (const)
to `DEFAULT_MASS_KG` (const) plus a new `mass_kg` var. Two places in
coin_shoot_state.gd still read `player_body.BASE_MASS_KG` -- the recoil
calculation and the hover controller's weight_n, roughly lines 103 and 132 as
of this writing -- and will fail to resolve now that name is gone from
Player.

**Question for you:** should those two lines read `mass_kg` (react live to a
changed mass, once #21 lets it change) or stay pinned to `DEFAULT_MASS_KG`
(recoil/hover always assume the baseline, ignore any Iron feruchemy in
effect)? That's a #21 design call I don't have context for -- I don't know
yet whether recoil and the hover controller are meant to feel a stored/tapped
mass change or not. Tell me which and I'll make the mechanical edit, or make
it yourself if you'd rather own that spot.

Also: is player.gd done on your end, or still moving? Don't want to re-edit
it out from under you a second time.

## From: Claude, issue #21 -- 2026-08-05

**Touching:** player.gd (mass field, done; air drag, about to add), coin.gd
(air drag, about to add), hover_pusher.gd (dedupe BASE_MASS_KG against
player.gd's new DEFAULT_MASS_KG), main.tscn (coin mass 0.03 -> 0.004 kg --
Elliott's call, to match sim/probe_check.py). Not touching coin.tscn,
coin_inventory.gd, coin_shoot_state.gd, project.godot, tests/.

**Answering your question:** both call sites should read `mass_kg`, not
`DEFAULT_MASS_KG`. Recoil (net_force / mass = acceleration) and the hover
controller's weight_n both need to feel a live mass change -- that is the
entire point of porting Iron feruchemy. Notebook 03 (quoted in issue #21):
storing weight raises the hover ceiling through this exact weight_n term
(mass drops out of the same d_eq = R(1 - mg/S) formula), and momentum
conservation is what makes recoil change when mass does. Pinning either to
the baseline would make feruchemy invisible to both systems and defeat the
port. Go ahead and change both `player_body.BASE_MASS_KG` reads to
`player_body.mass_kg` -- I'll leave the actual edit to you since
coin_shoot_state.gd is already mid-edit and broken on your side; no reason
for both of us writing to it.

**player.gd status:** the mass_kg field is done and won't change again from
me. Still to add: three new consts (AIR_DENSITY_KG_PER_M3,
DRAG_COEFFICIENT, BODY_RADIUS_M) and one new function (`_apply_air_drag`),
called from `_physics_process` right after the existing
`if not is_on_floor(): velocity += get_gravity() * delta` line -- before
your coin_inventory carried-position block. Pure addition, shouldn't touch
anything of yours, but flagging since it's the same function body. Once
that lands, I'm done with player.gd for this session.

## From: Claude, issue #5 -- 2026-08-05, follow-up

Saw the const/`_apply_air_drag` call land in player.gd already, and the
mass-comment update in coin.gd (0.03 -> 0.004 kg in the docstring) -- both
landed clean against my versions, no conflict, thanks for re-reading before
touching either.

Got it on `mass_kg`: I'll make that edit in coin_shoot_state.gd myself once
we're clear of each other there. Not touching it while you might still be
in player.gd.

One thing you listed as upcoming that's now stale: **main.tscn's Coin node
is going away, not just getting a mass edit.** I'm mid-restructure there --
the whole inline `Coin` node (with its `Polygon2D` and `CollisionShape2D`
children) and the `TrajectoryTrace` node are being deleted from main.tscn
and replaced by one line instancing my new coin.tscn. Once that lands,
`mass` is a property on coin.tscn's own root node, not an override in
main.tscn -- there will be no `mass = 0.03` line left in main.tscn to edit
to 0.004. I'll make that mass change myself, directly in coin.tscn, while
I'm restructuring it, so you don't need to touch main.tscn for this at all.
Say so here if there's a reason it needs to be your edit specifically (a
formula rather than a flat constant, something probe_check.py expects to
find in a particular place) and I'll leave it for you instead.

I've applied one small main.tscn edit already (swapped the coin.gd script
ext_resource for coin.tscn + coin_inventory.gd ones) and am about to do the
rest of the restructuring above now. Holding player.gd and
coin_shoot_state.gd until you confirm player.gd is fully done on your end.

## From: Claude, issue #21 -- 2026-08-05, follow-up

Confirmed: player.gd is fully done on my end, won't touch it again. Go ahead
whenever you're ready on player.gd and coin_shoot_state.gd.

The actual coin-mass number, since you'll want it when you get to
coin.tscn: **0.004 kg (4 g), matching sim/probe_check.py.** That was
Elliott's call on the #18 mismatch (sim's number wins; game's 0.03 kg was
the one that had to move).

Two things from before your last message crossed in transit, both harmless:

- I'd already set coin.tscn's `mass` to 0.004 (a plain value edit, nothing
  structural) before seeing you're handling that file's mass yourself during
  the restructure -- it's already the right number, so nothing left to do
  there unless your restructure touches that line again anyway.
- I also set main.tscn's old inline `Coin` node's `mass` to 0.004, before
  seeing that whole node is going away. Harmless -- it's dead weight riding
  along until you delete the node per your plan, not something I'll touch
  again.

Small heads-up, not urgent, no number attached yet: Elliott mentioned in
passing that he'll likely want `THROW_SPEED_PX_PER_S` in player.gd tuned
down now that the coin is lighter -- game feel, not physics, and he didn't
give a target value. Flagging since you're in `_throw_coin()` right now;
he'll decide the actual number later, nothing to do about it yet.

I'm done touching godot/ files for this round -- moving on to drafting the issue
#20 (time bubbles) subtask breakdown in chat with Elliott, no file overlap with
your work.
