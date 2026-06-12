"""Quick numerical probe of the engine before the notebooks lean on it.

Run from the mistfight folder:  python -m sim.probe_check
"""

import math

import numpy as np

from sim import (Body, World, Steelpush, Ironpull, IronFeruchemy, GoldFeruchemy,
                 SteelFeruchemy, Legs, GoldCompounding, Health, Poison,
                 SpeedBubble, RigidConstraint, RigidFrame, AirDrag,
                 AIR_DENSITY_KG_PER_M3, GRAVITY_M_PER_S2)


def check_free_fall():
    world = World()
    guy = world.add_body(Body("guy", mass_kg=80, position=(0, 20)))
    world.run(3.0)
    data = world.history.body("guy")
    landed_tick = np.argmax(data["on_ground"])
    simulated = data["t"][landed_tick]
    analytic = math.sqrt(2 * (20 - guy.radius_m) / GRAVITY_M_PER_S2)
    print(f"free fall: landed at {simulated:.3f} s, analytic {analytic:.3f} s")
    assert abs(simulated - analytic) < 0.02


def check_momentum_conserving_mass_change():
    body = Body("test", mass_kg=80, position=(0, 10), velocity=(0, -10))
    body.change_mass(40)
    print(f"mass 80->40 kg: velocity {body.velocity[1]:.1f} m/s (expect -20)")
    assert abs(body.velocity[1] + 20) < 1e-9


def check_anchored_launch():
    world = World()
    coin = world.add_body(Body("coin", 0.004, (0, 0.01), radius_m=0.01, is_metal=True))
    wax = world.add_body(Body("wax", 80, (0, 1.0)))
    push = world.add_power(Steelpush(wax, coin, strength_newtons=2000))
    push.active = True
    world.run(12.0)
    data = world.history.body("wax")
    equilibrium = push.max_range_m * (1 - 80 * GRAVITY_M_PER_S2 / 2000) + coin.position[1]
    mean_height = data["y"][len(data["y"]) // 2:].mean()  # after transient
    peak = data["y"].max()
    print(f"anchored launch: peak {peak:.2f} m, late-run mean {mean_height:.2f} m, "
          f"analytic equilibrium {equilibrium:.2f} m")
    assert peak > 5.0, "Wax should launch well off the ground"
    assert abs(mean_height - equilibrium) < 1.5, "should oscillate around equilibrium"


def check_midair_coin_is_no_anchor():
    # High altitude on purpose: near the ground a downward-pushed coin lands
    # almost instantly and BECOMES an anchor (the classic coin-drop launch),
    # so "unanchored coins give you nothing" is only testable in open air.
    world = World()
    coin = world.add_body(Body("coin", 0.004, (0, 49.5), radius_m=0.01, is_metal=True))
    wax = world.add_body(Body("wax", 80, (0, 50.0)))
    push = world.add_power(Steelpush(wax, coin, strength_newtons=2000))
    push.active = True
    world.run(1.0)
    data = world.history.body("wax")
    upward_kick = (data["vy"] + GRAVITY_M_PER_S2 * data["t"]).max()  # gravity removed
    print(f"midair coin: Wax's total upward kick {upward_kick:.2f} m/s (should be small)")
    assert upward_kick < 1.0, "an unanchored coin should give Wax almost nothing"


def check_coin_drop_launch():
    world = World()
    coin = world.add_body(Body("coin", 0.004, (0, 2.5), radius_m=0.01, is_metal=True))
    wax = world.add_body(Body("wax", 80, (0, 3.0)))
    push = world.add_power(Steelpush(wax, coin, strength_newtons=2000))
    push.active = True
    world.run(6.0)
    coin_data = world.history.body("coin")
    wax_data = world.history.body("wax")
    coin_grounded_at = coin_data["t"][np.argmax(coin_data["on_ground"])]
    print(f"coin drop: coin grounded at {coin_grounded_at:.3f} s, "
          f"Wax peak {wax_data['y'].max():.2f} m")
    assert coin_grounded_at < 0.3, "pushed coin should slam down almost instantly"
    assert wax_data["y"].max() > 5.0, "grounded coin becomes an anchor; Wax launches"


def check_feruchemy_is_zero_sum():
    # Store half your mass for 2 s -> 80 kg-s banked. Tapping at +1.0 base
    # mass (160 kg total) drains 80 kg-s per second -> should last exactly 1 s.
    world = World()
    wax = world.add_body(Body("wax", 80, (0, 0.3)))  # standing on the ground
    ironmind = world.add_power(IronFeruchemy(wax))

    ironmind.store(0.5)
    world.run(2.0)
    banked = ironmind.reserve_kg_seconds
    print(f"feruchemy: stored half weight for 2 s -> {banked:.1f} kg-s banked (expect 80)")
    assert abs(banked - 80.0) < 0.5
    assert abs(wax.mass_kg - 40.0) < 1e-9, "actively lighter the whole time storing"

    ironmind.tap(1.0)
    world.run(0.9)
    assert abs(wax.mass_kg - 160.0) < 1e-9, "carrying double mass while tapping"
    world.run(0.2)  # past the 1 s mark: the ironmind should have run dry
    print(f"feruchemy: after over-tapping, mass back to {wax.mass_kg:.0f} kg, "
          f"reserve {ironmind.reserve_kg_seconds:.2f} kg-s")
    assert abs(wax.mass_kg - 80.0) < 1e-9, "snaps back to base when the ironmind empties"
    assert ironmind.reserve_kg_seconds == 0.0


def check_storing_midfall_speeds_you_up():
    # The counterintuitive canon consequence: momentum is conserved, so
    # halving your mass mid-fall DOUBLES your fall speed.
    world = World()
    wax = world.add_body(Body("wax", 80, (0, 200)))
    ironmind = world.add_power(IronFeruchemy(wax))
    world.run(2.0)
    speed_before = wax.velocity[1]
    ironmind.store(0.5)
    world.step()
    speed_after = wax.velocity[1]
    print(f"mid-fall store: {speed_before:.1f} m/s -> {speed_after:.1f} m/s "
          f"(expect roughly doubled)")
    assert abs(speed_after - 2 * speed_before) < 0.5


def check_bubble_compresses_time():
    # Two identical balls dropped from 5 m; one falls inside a 5x bendalloy
    # bubble. It should land in one fifth the EXTERNAL time.
    world = World()
    free_ball = world.add_body(Body("free", 1.0, (0, 5), radius_m=0.1))
    fast_ball = world.add_body(Body("fast", 1.0, (10, 5), radius_m=0.1))
    world.add_bubble(SpeedBubble(center=(10, 3), radius_m=3.5, time_factor=5.0))
    world.run(1.5)
    free_landing = world.history.body("free")
    fast_landing = world.history.body("fast")
    free_time = free_landing["t"][np.argmax(free_landing["on_ground"])]
    fast_time = fast_landing["t"][np.argmax(fast_landing["on_ground"])]
    print(f"bubble drop: free ball lands at {free_time:.3f} s, "
          f"bubbled ball at {fast_time:.3f} s (ratio {free_time / fast_time:.1f}, expect ~5)")
    assert abs(free_time / fast_time - 5.0) < 0.3


def check_exit_speed_is_emergent():
    # A ball crossing a speed bubble covers ground fast WHILE INSIDE but
    # exits at its original velocity, with no reset code anywhere — its
    # velocity state never changed, only its experienced time.
    # The ball falls while crossing, so it cuts a descending chord through
    # the circular bubble — chord length varies. The robust invariant: while
    # inside, horizontal ground covered per EXTERNAL second should be
    # vx * time_factor = 100 m/s, and the exit velocity should be untouched.
    world = World(dt_seconds=1.0 / 1000.0)
    ball = world.add_body(Body("ball", 1.0, (-15, 100), velocity=(20, 0), radius_m=0.1))
    world.add_bubble(SpeedBubble(center=(0, 100), radius_m=5, time_factor=5.0))
    inside_external_seconds = 0.0
    inside_distance_m = 0.0
    while ball.position[0] < 15:
        inside_before = world.time_factor_at(ball.position) > 1.0
        x_before = ball.position[0]
        world.step()
        if inside_before:
            inside_external_seconds += world.dt_seconds
            inside_distance_m += ball.position[0] - x_before
    effective_speed = inside_distance_m / inside_external_seconds
    print(f"bubble crossing: while inside, {inside_distance_m:.1f} m covered in "
          f"{inside_external_seconds:.3f} s external = {effective_speed:.0f} m/s effective "
          f"(expect ~100); exit vx = {ball.velocity[0]:.1f} m/s (expect 20, untouched)")
    assert abs(effective_speed - 100.0) < 5.0
    assert abs(ball.velocity[0] - 20.0) < 1e-9


def check_wayne_heals_fast_in_a_bubble():
    # THE emergence test. Two identical Wayne setups: 60 damage, tapping
    # gold at 10 HP/s. One stands inside a 5x bubble. Neither the health
    # nor the gold code knows bubbles exist; the bubbled Wayne should
    # nevertheless be fully healed ~5x sooner in external time.
    def wounded_wayne(world):
        wayne = world.add_body(Body("wayne", 70, (0, 0.3)))
        health = world.add_power(Health(wayne, max_health=100, natural_regen_per_second=0))
        goldmind = world.add_power(GoldFeruchemy(health, initial_reserve_health_points=100))
        health.damage(60)
        goldmind.tap(10)
        return health

    plain_world = World()
    plain_health = wounded_wayne(plain_world)
    bubble_world = World()
    bubble_health = wounded_wayne(bubble_world)
    bubble_world.add_bubble(SpeedBubble(center=(0, 0.3), radius_m=2, time_factor=5.0))

    bubble_world.run(1.3)
    plain_world.run(1.3)
    healed_in_bubble = bubble_health.current
    healed_outside = plain_health.current
    plain_world.run(4.8)  # out to ~6.1 s total
    print(f"wayne: after 1.3 s external — bubbled {healed_in_bubble:.0f}/100, "
          f"plain {healed_outside:.0f}/100; plain full at ~6 s: {plain_health.current:.0f}/100")
    assert healed_in_bubble >= 99.9, "bubbled Wayne should be fully healed"
    assert healed_outside < 60, "plain Wayne should still be wounded"
    assert plain_health.current >= 99.9


def check_cadmium_stretches_time():
    # The mirror of the bendalloy probe: a ball falling inside a 0.2x
    # cadmium bubble should take five times LONGER to land, external.
    world = World()
    free_ball = world.add_body(Body("free", 1.0, (0, 5), radius_m=0.1))
    slow_ball = world.add_body(Body("slow", 1.0, (10, 5), radius_m=0.1))
    world.add_bubble(SpeedBubble(center=(10, 3), radius_m=3.5, time_factor=0.2))
    world.run(6.0)
    free_data = world.history.body("free")
    slow_data = world.history.body("slow")
    free_time = free_data["t"][np.argmax(free_data["on_ground"])]
    slow_time = slow_data["t"][np.argmax(slow_data["on_ground"])]
    print(f"cadmium drop: free ball lands at {free_time:.3f} s, slowed ball at "
          f"{slow_time:.3f} s (ratio {slow_time / free_time:.1f}, expect ~5)")
    assert abs(slow_time / free_time - 5.0) < 0.3


def check_compounding_breaks_zero_sum():
    # Miles banks 20 charge points of misery, takes a near-lethal wound,
    # and burns the goldmind: 99 HP healed for 9.9 charge — a 10x return
    # that plain feruchemy (notebook 04's Wayne) could never show.
    world = World()
    miles = world.add_body(Body("miles", 90, (0, 0.3)))
    health = world.add_power(Health(miles, max_health=100, natural_regen_per_second=0))
    goldmind = world.add_power(GoldFeruchemy(health, initial_reserve_health_points=20))
    compounder = world.add_power(GoldCompounding(health, goldmind, metal_supply_grams=10))

    health.damage(99)
    compounder.active = True
    world.run(2.0)
    charge_spent = 20 - goldmind.reserve_health_points
    print(f"compounding: healed {health.current - 1:.1f} HP for {charge_spent:.1f} "
          f"charge points (10x return)")
    assert abs(health.current - 100) < 0.1
    assert abs(charge_spent - 9.9) < 0.1


def check_miles_dies_when_the_metal_runs_out():
    # Under steady 30 HP/s damage Miles holds the line easily — until the
    # gold is gone, and then he dies like anyone else.
    world = World()
    miles = world.add_body(Body("miles", 90, (0, 0.3)))
    health = world.add_power(Health(miles, max_health=100, natural_regen_per_second=0))
    goldmind = world.add_power(GoldFeruchemy(health, initial_reserve_health_points=50))
    compounder = world.add_power(GoldCompounding(health, goldmind, metal_supply_grams=1.5))
    world.add_power(Poison(health, damage_per_second=30))
    goldmind.store(0)  # he's busy being shot; charge comes from the bank
    compounder.active = True

    world.run(8.0)
    mid_run_health = health.current
    world.run(8.0)
    print(f"miles: at 8 s health {mid_run_health:.0f}/100 (tanking 30 HP/s), "
          f"at 16 s health {health.current:.0f}/100, metal {compounder.metal_supply_grams:.2f} g")
    assert mid_run_health > 90, "with metal, 30 HP/s should barely scratch him"
    assert health.is_dead, "without metal, Hundredlives runs out of lives"


def make_runner(world, x=0.0, tap=None, store=None, reserve=50.0):
    body = world.add_body(Body("runner", 80, (x, 0.3)))
    legs = world.add_power(Legs(body, top_speed_m_per_s=8))
    steelmind = SteelFeruchemy(legs, initial_reserve_speed_seconds=reserve)
    world.powers.insert(0, steelmind)  # multiplier set before legs use it
    if tap is not None:
        steelmind.tap(tap)
    if store is not None:
        steelmind.store(store)
    legs.direction = 1
    return body, legs, steelmind


def check_steelrunner_footrace():
    # Tapping +4 means five times normal speed; storing 0.5 means molasses.
    distances = {}
    for label, kwargs in [("normal", {}), ("tapping +4", {"tap": 4.0}),
                          ("storing 0.5", {"store": 0.5})]:
        world = World()
        body, _, _ = make_runner(world, **kwargs)
        world.run(10.0)
        distances[label] = body.position[0]
    print(f"footrace 10 s: normal {distances['normal']:.0f} m, "
          f"tapping {distances['tapping +4']:.0f} m, "
          f"storing {distances['storing 0.5']:.0f} m")
    assert abs(distances["tapping +4"] / distances["normal"] - 5.0) < 0.2
    assert abs(distances["storing 0.5"] / distances["normal"] - 0.5) < 0.05


def check_steelmind_is_zero_sum():
    # Store half your speed for 10 s -> 5 speed-seconds banked; tapping +4
    # drains 4/s -> 1.25 s of glory, then the steelmind runs dry mid-stride.
    world = World()
    body, legs, steelmind = make_runner(world, reserve=0.0)
    steelmind.store(0.5)
    world.run(10.0)
    banked = steelmind.reserve_speed_seconds
    steelmind.tap(4.0)
    world.run(1.0)
    still_fast = legs.speed_multiplier
    world.run(0.5)
    print(f"steelmind: banked {banked:.2f} speed-seconds (expect 5); at 1.0 s of "
          f"tapping x{still_fast:.0f}, at 1.5 s x{legs.speed_multiplier:.0f} (ran dry)")
    assert abs(banked - 5.0) < 0.05
    assert still_fast == 5.0
    assert legs.speed_multiplier == 1.0


def check_steel_speed_is_not_a_bubble():
    # THE distinction. Two poisoned men at "5x speed": the Steelrunner's
    # chemistry runs at normal rate (dies at the normal 20 s), while the
    # bubble man's whole local clock is compressed (dies at 4 s external).
    world_steel = World()
    runner, _, _ = make_runner(world_steel, tap=4.0, reserve=500)
    steel_health = world_steel.add_power(Health(runner, 100, natural_regen_per_second=0))
    world_steel.add_power(Poison(steel_health, damage_per_second=5))

    world_bubble = World()
    bystander = world_bubble.add_body(Body("man", 80, (0, 0.3)))
    bubble_health = world_bubble.add_power(Health(bystander, 100, natural_regen_per_second=0))
    world_bubble.add_power(Poison(bubble_health, damage_per_second=5))
    world_bubble.add_bubble(SpeedBubble(center=(0, 0.3), radius_m=2, time_factor=5.0))

    for world in (world_steel, world_bubble):
        while not (steel_health if world is world_steel else bubble_health).is_dead:
            world.step()
    print(f"poisoned at 5x speed: Steelrunner dead at {world_steel.time_seconds:.1f} s "
          f"(normal schedule), bubble man at {world_bubble.time_seconds:.1f} s")
    assert abs(world_steel.time_seconds - 20.0) < 0.1
    assert abs(world_bubble.time_seconds - 4.0) < 0.1


def check_steel_velocity_is_kept_but_bubble_velocity_is_not():
    # A leap at steel-speed carries real kinetic state; a leap "at speed"
    # inside a bubble lands exactly where an unaided leap would (the
    # when-not-where theorem applied to a person).
    def long_jump(tap=None, bubble=False):
        world = World()
        body, legs, _ = make_runner(world, tap=tap, reserve=500)
        if bubble:
            world.add_bubble(SpeedBubble(center=(30, 0.3), radius_m=6, time_factor=5.0))
        while body.position[0] < 30:
            world.step()
        legs.jump(6.0)
        world.step()
        while not body.on_ground:
            world.step()
        return body.position[0] - 30

    plain = long_jump()
    steel = long_jump(tap=4.0)
    bubbled = long_jump(bubble=True)
    print(f"long jump: plain {plain:.1f} m, steel x5 {steel:.1f} m, "
          f"inside 5x bubble {bubbled:.1f} m (bubble should match plain)")
    assert abs(steel / plain - 5.0) < 0.2
    assert abs(bubbled - plain) < 0.5


def check_pulled_coins_never_anchor():
    # The Lurcher asymmetry. Identical overhead geometry that anchored the
    # PUSHED coin (its grip grew with the push): pulled instead, the force
    # lifts the coin and destroys its grip — it flies straight to Wax.
    world = World()
    coin = world.add_body(Body("coin", 0.004, (3, 0.01), radius_m=0.01, is_metal=True))
    wax = world.add_body(Body("wax", 80, (3, 1.0)))
    pull = world.add_power(Ironpull(wax, coin, 2000))
    pull.active = True
    # The coin moves tick-jumps faster than any catch radius, so detect the
    # moment it reaches/passes Wax's height (catching is a hands problem,
    # and the engine has no hands).
    reached_him_at = None
    for _ in range(int(0.5 / world.dt_seconds)):
        world.step()
        if reached_him_at is None and coin.position[1] >= wax.position[1]:
            reached_him_at = world.time_seconds
            pull.active = False
    print(f"lurcher: overhead pull frees the coin instantly; it reaches his hand "
          f"height in {reached_him_at * 1000:.0f} ms (the same geometry PUSHED anchors it)")
    assert reached_him_at is not None and reached_him_at < 0.05


def check_grapple_to_fixed_metal():
    # The Lurcher's real transport: pull against the bones of the world.
    # A beam 10 m up and 15 m out; Wax breaks his own grip and arcs toward
    # it, releasing on approach (no body-body collision in this engine).
    world = World()
    beam = world.add_body(Body("beam", 50, (10, 8), radius_m=0.2,
                               is_metal=True, is_fixed=True))
    wax = world.add_body(Body("wax", 80, (0, 0.3)))
    pull = world.add_power(Ironpull(wax, beam, 5000))  # flared: he must break
    pull.active = True                                  # his own boot-grip first
    for _ in range(int(4.0 / world.dt_seconds)):
        world.step()
        if np.linalg.norm(beam.position - wax.position) < 1.5:
            pull.active = False
    data = world.history.body("wax")
    peak_height = data["y"].max()
    peak_speed = np.sqrt(data["vx"]**2 + data["vy"]**2).max()
    print(f"grapple: Wax arcs to {peak_height:.1f} m at up to {peak_speed:.1f} m/s; "
          f"beam unmoved: {np.linalg.norm(beam.position - [10, 8]):.4f} m")
    assert peak_height > 5, "the grapple should genuinely lift him"
    assert np.linalg.norm(beam.position - [10, 8]) == 0.0


def check_iron_is_an_energy_pump():
    # Forced by the canon momentum rule: KE = p^2 / 2m, p fixed. Tapping
    # (mass up) DELETES kinetic energy from the physical world; storing
    # (mass down) CREATES it. The magic pays the difference.
    body = Body("skimmer", 80, (0, 50), velocity=(0, -10))
    energy_before = 0.5 * body.mass_kg * body.velocity[1] ** 2
    body.change_mass(160)  # tap 2x
    energy_after_tap = 0.5 * body.mass_kg * body.velocity[1] ** 2
    body.change_mass(40)   # then store hard
    energy_after_store = 0.5 * body.mass_kg * body.velocity[1] ** 2
    print(f"energy pump: {energy_before:.0f} J -> tap 2x -> {energy_after_tap:.0f} J "
          f"(half) -> store to 40 kg -> {energy_after_store:.0f} J (quadrupled back)")
    assert abs(energy_after_tap - energy_before / 2) < 1e-9
    assert abs(energy_after_store - energy_after_tap * 4) < 1e-9


class ForceRamp:
    """Test helper: a steadily growing horizontal shove."""

    def __init__(self, body, newtons_per_second):
        self.body = body
        self.newtons_per_second = newtons_per_second
        self.elapsed_seconds = 0.0

    def tick(self, dt_seconds):
        self.elapsed_seconds += dt_seconds
        self.body.apply_force([self.newtons_per_second * self.elapsed_seconds, 0.0])


def check_static_grip_breaks_then_falls_off():
    # Elliott's phrasing, as physics: grip gets stronger until overwhelmed,
    # then drastically falls off. A 10 kg block under a growing shove should
    # not move a hair until ~mu_s*m*g = 58.9 N (t = 1.18 s at 50 N/s), then
    # break loose against only the weaker kinetic friction.
    world = World()
    block = world.add_body(Body("block", 10, (0, 0.1), radius_m=0.1))
    world.run(0.1)  # settle onto the ground first
    world.add_power(ForceRamp(block, newtons_per_second=50))
    world.run(1.0)
    displacement_before_breakaway = abs(block.position[0])
    world.run(0.5)
    print(f"breakaway: moved {displacement_before_breakaway * 1000:.3f} mm by 1.0 s "
          f"(expect 0), sliding at {block.velocity[0]:.2f} m/s by 1.5 s")
    assert displacement_before_breakaway < 1e-6, "static grip should hold completely"
    assert block.velocity[0] > 0.3, "past breakaway it should be properly moving"


def check_shallow_push_skitters_steep_push_anchors():
    # Steep (Wax overhead): the push presses the coin into the ground,
    # GROWING its grip — the coin anchors and Wax launches. Shallow (Wax
    # nearly level): the mostly-horizontal force overwhelms static grip and
    # the coin skitters away, wasting the push.
    def push_the_coin(wax_position):
        world = World()
        coin = world.add_body(Body("coin", 0.004, (3, 0.01), radius_m=0.01, is_metal=True))
        wax = world.add_body(Body("wax", 80, wax_position))
        push = world.add_power(Steelpush(wax, coin, 2000))
        push.active = True
        world.run(1.0)
        wax_data = world.history.body("wax")
        return abs(coin.position[0] - 3), wax_data["vy"].max()

    coin_moved_steep, wax_rise_steep = push_the_coin((3, 1.0))
    coin_moved_shallow, wax_rise_shallow = push_the_coin((0, 0.6))
    print(f"steep push: coin moved {coin_moved_steep * 100:.2f} cm, Wax rises at "
          f"{wax_rise_steep:.1f} m/s; shallow push: coin skitters {coin_moved_shallow:.0f} m, "
          f"Wax rises at {wax_rise_shallow:.1f} m/s")
    assert coin_moved_steep < 0.01 and wax_rise_steep > 5
    assert coin_moved_shallow > 2 and wax_rise_shallow < 1


def check_fixed_anchor_gives_horizontal_launch():
    # The canon move our old hack couldn't express: pushing off a rail spike
    # sideways. The spike is part of the world; Wax breaks his own grip and
    # slides away fast. The same shallow geometry against a loose coin
    # (probe above) gave him almost nothing.
    world = World()
    spike = world.add_body(Body("rail spike", 1.0, (3, 0.1), radius_m=0.1,
                                is_metal=True, is_fixed=True))
    wax = world.add_body(Body("wax", 80, (0, 0.3)))
    push = world.add_power(Steelpush(wax, spike, 2000))
    push.active = True
    world.run(2.0)
    wax_data = world.history.body("wax")
    top_speed = np.abs(wax_data["vx"]).max()
    print(f"rail spike: Wax reaches {top_speed:.1f} m/s horizontally; "
          f"spike moved {np.linalg.norm(spike.position - [3, 0.1]):.4f} m")
    assert top_speed > 8, "a fixed anchor should give a real horizontal launch"
    assert np.linalg.norm(spike.position - [3, 0.1]) == 0.0


def check_multi_target_push_shares_one_budget():
    # A Coinshot pushing several anchors can't exceed their total push
    # strength: the reaction on the pusher is capped at strength_newtons, so
    # two coins do not give twice the launch of one. Non-canon modeling
    # choice (canon is silent on how multi-target pushes divide; we cap the
    # total budget). One target must behave exactly as a lone push.
    def first_tick_upward_speed(coin_xs):
        world = World()
        wax = world.add_body(Body("wax", 80, (0, 1.0)))
        coins = [world.add_body(Body(f"coin{i}", 0.004, (x, 0.01),
                                     radius_m=0.01, is_metal=True))
                 for i, x in enumerate(coin_xs)]
        push = world.add_power(Steelpush(wax, coins, 2000))
        push.active = True
        world.step()  # one tick, before the grounded coins can move
        return wax.velocity[1]

    one = first_tick_upward_speed([0.0])
    two = first_tick_upward_speed([-0.3, 0.3])
    net_force_two = 80 * two / (1.0 / 240.0)  # mass * dv / dt
    print(f"multi-target: one coin -> {one:.4f} m/s up, two coins -> {two:.4f} "
          f"m/s up; two-coin net force {net_force_two:.0f} N (cap 2000, not doubled)")
    assert two < 1.15 * one, "two anchors must not double the push (shared budget)"
    assert net_force_two <= 2000.0 + 1.0, "total reaction can't exceed the strength budget"


def check_steel_reserve_runs_dry():
    # A finite steel supply burns down while the flame is lit and the push
    # dies when it hits zero. 2 grams at 0.5 g/s lasts exactly 4 s; after
    # that Wax gets no push and falls.
    world = World()
    wax = world.add_body(Body("wax", 80, (0, 1.0)))
    anchor = world.add_body(Body("anchor", 0.004, (0, 0.05), radius_m=0.01,
                                 is_metal=True, is_fixed=True))
    push = world.add_power(Steelpush(wax, anchor, 2000, steel_grams=2.0,
                                     burn_grams_per_second=0.5))
    push.active = True
    world.run(3.9)
    assert push.steel_grams > 0.0, "should still have metal just before 4 s"
    world.run(0.2)  # past the 4 s mark
    print(f"steel reserve: empty after ~4 s (now {push.steel_grams:.3f} g), "
          f"out_of_metal={push.out_of_metal}")
    assert push.out_of_metal, "2 g at 0.5 g/s must run dry by 4 s"
    # with the flame dead, the next tick delivers no push: Wax only feels gravity
    speed_before = wax.velocity[1]
    world.step()
    fell = wax.velocity[1] < speed_before
    assert fell, "no push once the metal is gone; Wax should be falling"


def check_flaring_trades_push_for_metal():
    # Flaring multiplies the push by `flare` but the burn rate by flare^2:
    # flare 2 gives twice the force and burns four times as fast (a burst,
    # not a cruising mode).
    from sim import GRAVITY_M_PER_S2 as g

    def first_tick_push_force(flare):
        world = World()
        wax = world.add_body(Body("wax", 80, (0, 1.0)))
        anchor = world.add_body(Body("anchor", 0.004, (0, 0.05), radius_m=0.01,
                                     is_metal=True, is_fixed=True))
        push = world.add_power(Steelpush(wax, anchor, 2000, flare=flare))
        push.active = True
        world.step()
        return 80 * wax.velocity[1] / world.dt_seconds + 80 * g

    def seconds_to_empty(flare):
        world = World()
        wax = world.add_body(Body("wax", 80, (0, 1.0)))
        anchor = world.add_body(Body("anchor", 0.004, (0, 0.05), radius_m=0.01,
                                     is_metal=True, is_fixed=True))
        push = world.add_power(Steelpush(wax, anchor, 2000, steel_grams=2.0,
                                         burn_grams_per_second=0.5, flare=flare))
        push.active = True
        for step in range(int(10 / world.dt_seconds)):
            world.step()
            if push.out_of_metal:
                return (step + 1) * world.dt_seconds
        return None

    force_ratio = first_tick_push_force(2.0) / first_tick_push_force(1.0)
    life_ratio = seconds_to_empty(1.0) / seconds_to_empty(2.0)
    print(f"flaring x2: push force x{force_ratio:.2f} (expect 2), "
          f"metal drains x{life_ratio:.2f} faster (expect 4)")
    assert abs(force_ratio - 2.0) < 0.02, "flare should multiply push by flare"
    assert abs(life_ratio - 4.0) < 0.05, "flare should multiply burn by flare squared"


def check_rigid_constraint_stability():
    # A 10cm bullet (20g) fired at 100 m/s. It should maintain its length
    # and total momentum (accounting for gravity).
    world = World()
    nose = world.add_body(Body("nose", 0.01, (0, 10), velocity=(100, 0), radius_m=0.01))
    tail = world.add_body(Body("tail", 0.01, (-0.1, 10), velocity=(100, 0), radius_m=0.01))
    world.add_power(RigidConstraint(nose, tail, 0.1))
    
    world.run(0.5)
    dist = np.linalg.norm(nose.position - tail.position)
    # Momentum: p_y should be m * g * t = 0.02 * 9.81 * 0.5 = 0.0981
    total_momentum_y = nose.mass_kg * nose.velocity[1] + tail.mass_kg * tail.velocity[1]
    expected_p_y = -0.02 * GRAVITY_M_PER_S2 * 0.5
    
    print(f"rigid bullet: dist {dist:.6f} m (expect 0.1), "
          f"p_y {total_momentum_y:.4f} (expect {expected_p_y:.4f})")
    assert abs(dist - 0.1) < 1e-7
    assert abs(total_momentum_y - expected_p_y) < 1e-9


class _AntiGravity:
    # Test fixture: cancels gravity so a bullet's heading is a clean signal.
    def __init__(self, bodies):
        self.bodies = bodies

    def apply_forces(self):
        for body in self.bodies:
            body.apply_force([0.0, GRAVITY_M_PER_S2 * body.mass_kg])


def check_bubble_slows_rigid_bullets():
    # Notebook 12: an aligned rigid bullet crossing a bubble keeps its
    # heading EXACTLY (all internal forces act along the rod; nothing can turn it)
    # and is slowed: each boundary crossing multiplies stored speed by
    # (1+f)^2 / (2(1+f^2)), so a 5x bubble in-and-out leaves 81/169 of the
    # launch speed. Verified against a 200 kHz stiff-spring ground truth.
    world = World(dt_seconds=1.0 / 1000.0)
    nose = world.add_body(Body("nose", 0.01, (0.1, 10), velocity=(50, 0), radius_m=0.01))
    tail = world.add_body(Body("tail", 0.01, (-0.1, 10), velocity=(50, 0), radius_m=0.01))
    world.add_power(RigidConstraint(nose, tail, 0.2))
    world.add_power(_AntiGravity([nose, tail]))
    world.add_bubble(SpeedBubble(center=(10, 10), radius_m=5, time_factor=5.0))
    world.run(0.6)
    center_of_mass_velocity = (nose.velocity + tail.velocity) / 2
    exit_speed = np.linalg.norm(center_of_mass_velocity)
    expected_speed = 50 * 81 / 169
    print(f"bubbled bullet: exits at {exit_speed:.3f} m/s "
          f"(expect {expected_speed:.3f} = 81/169 of 50), "
          f"sideways velocity {center_of_mass_velocity[1]:.2e} (expect 0: no deflection)")
    assert abs(exit_speed - expected_speed) < 1e-3
    assert abs(center_of_mass_velocity[1]) < 1e-9


def check_tilted_bullet_turns_and_spins():
    # Notebook 12: a bullet whose long axis is TILTED away from its motion
    # gets a repeatable turn and a hard spin-up at the entry boundary
    # (10 deg tilt into a 5x bubble: -4.17 deg; ground truth -4.168 deg).
    # The full trip then depends on the spin angle at exit, so the probe
    # pins the settled entry numbers only, measured while both ends are
    # inside.
    world = World(dt_seconds=1.0 / 4000.0)
    rod = np.array([np.cos(np.radians(10)), np.sin(np.radians(10))])
    nose = world.add_body(Body("nose", 0.01, rod * 0.1 + [0, 10],
                               velocity=(50, 0), radius_m=0.01))
    tail = world.add_body(Body("tail", 0.01, -rod * 0.1 + [0, 10],
                               velocity=(50, 0), radius_m=0.01))
    world.add_power(RigidConstraint(nose, tail, 0.2))
    world.add_power(_AntiGravity([nose, tail]))
    world.add_bubble(SpeedBubble(center=(10, 10), radius_m=5, time_factor=5.0))
    world.run(0.115)
    assert all(np.linalg.norm(body.position - [10, 10]) < 5 for body in (nose, tail)), \
        "bullet should be fully inside the bubble at measurement time"
    center_of_mass_velocity = (nose.velocity + tail.velocity) / 2
    heading = np.degrees(np.arctan2(center_of_mass_velocity[1], center_of_mass_velocity[0]))
    relative = nose.velocity - tail.velocity
    rod_now = nose.position - tail.position
    rod_now /= np.linalg.norm(rod_now)
    tangential = relative - np.dot(relative, rod_now) * rod_now
    spin = np.degrees(np.linalg.norm(tangential) / 0.2)
    print(f"tilted bullet: entry turn {heading:+.3f} deg (expect ~-4.17), "
          f"spin {spin:.0f} deg/s (expect thousands)")
    assert abs(heading - (-4.17)) < 0.2
    assert spin > 3000


def check_rigid_frame_holds_shape_and_momentum():
    # Notebook 12B: a 4-point rigid frame (20 cm x 5 cm bullet) in plain
    # flight keeps its shape to numerical precision and conserves momentum
    # exactly: the repeated edge-by-edge corrections must not leak anything.
    world = World(dt_seconds=1.0 / 1000.0)
    spots = [(0.1, 30), (-0.1, 30), (0.0, 30.025), (0.0, 29.975)]
    bodies = [world.add_body(Body(f"corner{i}", 0.005, spot,
                                  velocity=(50, 0), radius_m=0.005))
              for i, spot in enumerate(spots)]
    frame = world.add_power(RigidFrame(bodies))
    world.run(0.5)
    momentum = sum(body.mass_kg * body.velocity for body in bodies)
    expected_p_y = -0.02 * GRAVITY_M_PER_S2 * 0.5
    print(f"rigid frame: shape error {frame.max_shape_error_m():.2e} m, "
          f"p ({momentum[0]:.6f}, {momentum[1]:.6f}) expect (1, {expected_p_y:.4f})")
    assert frame.max_shape_error_m() < 1e-9
    assert abs(momentum[0] - 1.0) < 1e-9
    assert abs(momentum[1] - expected_p_y) < 1e-9


def check_dead_center_crossing_is_symmetric():
    # Notebook 12B: a transverse pair crossing the bubble dead-center (the
    # flight line through the bubble's center) must exit with zero spin and
    # zero heading change — the two tips cross simultaneously by mirror
    # symmetry, so there is nothing to wrench. The founding sanity check
    # for the off-center experiments.
    world = World(dt_seconds=1.0 / 4000.0)
    up = world.add_body(Body("up", 0.01, (0, 10.05), velocity=(50, 0), radius_m=0.01))
    down = world.add_body(Body("down", 0.01, (0, 9.95), velocity=(50, 0), radius_m=0.01))
    world.add_power(RigidConstraint(up, down, 0.1))
    world.add_power(_AntiGravity([up, down]))
    world.add_bubble(SpeedBubble(center=(10, 10), radius_m=5, time_factor=5.0))
    world.run(0.6)
    center_of_mass_velocity = (up.velocity + down.velocity) / 2
    relative = up.velocity - down.velocity
    print(f"dead-center pair: sideways v {center_of_mass_velocity[1]:.2e}, "
          f"relative |v| {np.linalg.norm(relative):.2e} (both expect 0)")
    assert abs(center_of_mass_velocity[1]) < 1e-9
    assert np.linalg.norm(relative) < 1e-6


def check_off_center_crossing_turns_and_spins():
    # Notebook 12B, Elliott's question: the same pair crossing OFF-center
    # (miss distance 2 m) gets turned away from the bubble's center and
    # spun up hard at entry. Ground truth (200 kHz spring): +23.6 deg and
    # ~26000 deg/s; the projection climbs toward that from below, so the
    # probe pins the 8 kHz values loosely.
    world = World(dt_seconds=1.0 / 8000.0)
    up = world.add_body(Body("up", 0.01, (0, 12.05), velocity=(50, 0), radius_m=0.01))
    down = world.add_body(Body("down", 0.01, (0, 11.95), velocity=(50, 0), radius_m=0.01))
    world.add_power(RigidConstraint(up, down, 0.1))
    world.add_power(_AntiGravity([up, down]))
    world.add_bubble(SpeedBubble(center=(10, 10), radius_m=5, time_factor=5.0))
    bubble_center = np.array([10.0, 10.0])
    report_time = None
    for _ in range(int(0.3 * 8000)):
        world.step()
        both_inside = all(np.linalg.norm(body.position - bubble_center) < 5
                          for body in (up, down))
        if both_inside and report_time is None:
            report_time = world.time_seconds + 0.004
        if report_time is not None and world.time_seconds >= report_time:
            break
    center_of_mass_velocity = (up.velocity + down.velocity) / 2
    heading = np.degrees(np.arctan2(center_of_mass_velocity[1], center_of_mass_velocity[0]))
    relative = up.velocity - down.velocity
    rod = up.position - down.position
    rod /= np.linalg.norm(rod)
    tangential = relative - np.dot(relative, rod) * rod
    spin = np.degrees(np.linalg.norm(tangential) / 0.1)
    print(f"off-center pair: entry turn {heading:+.1f} deg (truth +23.6, "
          f"climbing from below), spin {spin:.0f} deg/s (truth ~26000)")
    assert 13 < heading < 24
    assert spin > 9000


def check_wide_bullet_slows_at_each_crossing():
    # Notebook 12B: the 4-point wide bullet crossing dead-center is slowed
    # at four separate crossing events and exits at 14.653 m/s, confirmed
    # by an independent 50 kHz spring-frame ground truth (14.651). Slower
    # than the two-point rod's 23.964: more structure, more slow-down.
    world = World(dt_seconds=1.0 / 4000.0)
    spots = [(0.1, 10.0), (-0.1, 10.0), (0.0, 10.025), (0.0, 9.975)]
    bodies = [world.add_body(Body(f"corner{i}", 0.005, spot,
                                  velocity=(50, 0), radius_m=0.005))
              for i, spot in enumerate(spots)]
    world.add_power(RigidFrame(bodies))
    world.add_power(_AntiGravity(bodies))
    world.add_bubble(SpeedBubble(center=(10, 10), radius_m=5, time_factor=5.0))
    world.run(0.8)
    center_of_mass_velocity = sum(body.velocity for body in bodies) / 4
    exit_speed = np.linalg.norm(center_of_mass_velocity)
    print(f"wide bullet: exits dead-center crossing at {exit_speed:.3f} m/s "
          f"(spring ground truth 14.651; rod managed 23.964)")
    assert abs(exit_speed - 14.653) < 0.05


def check_terminal_velocity_matches_paper():
    # Notebook 13: with AirDrag in the world, a falling body settles at
    # terminal velocity = sqrt(2 m g / (air_density * drag_coefficient *
    # pi r^2)). 15 s of fall puts a body within a fraction of a percent of
    # terminal speed.
    world = World()
    ball = world.add_body(Body("ball", 1.0, (0, 600), radius_m=0.1))
    world.add_power(AirDrag(world))
    world.run(15.0)
    area = np.pi * ball.radius_m ** 2
    expected = np.sqrt(2 * ball.mass_kg * GRAVITY_M_PER_S2
                       / (AIR_DENSITY_KG_PER_M3 * ball.drag_coefficient * area))
    measured = -ball.velocity[1]
    print(f"terminal velocity: {measured:.2f} m/s (paper {expected:.2f})")
    assert abs(measured - expected) / expected < 0.002


def check_lighter_bodies_fall_slower():
    # The Skimmer story in one assertion: terminal velocity grows with the
    # square root of mass, so a body at quarter weight falls at half speed.
    world = World()
    # The heavy ball settles at ~66 m/s and needs ~30 s of fall to get
    # within a fraction of a percent of terminal, covering ~1900 m; both
    # start high enough that neither lands during the run.
    heavy = world.add_body(Body("heavy", 4.0, (0, 2200), radius_m=0.1))
    light = world.add_body(Body("light", 1.0, (10, 2200), radius_m=0.1))
    world.add_power(AirDrag(world))
    world.run(30.0)
    ratio = heavy.velocity[1] / light.velocity[1]
    print(f"quarter weight: falls at 1/{ratio:.3f} of the heavy body's speed "
          f"(expect 1/2.000)")
    assert abs(ratio - 2.0) < 0.02


def check_bubbled_faller_lands_sooner_not_harder():
    # Drag is computed from stored velocity and integrated over local time,
    # so the air inside a bubble shares the bubble's clock. Consequence: a
    # faller inside a 5x bubble lands in about a fifth of the outside time
    # but at the same speed.
    world = World()
    outside = world.add_body(Body("outside", 1.0, (100, 80), radius_m=0.1))
    inside = world.add_body(Body("inside", 1.0, (0, 80), radius_m=0.1))
    world.add_bubble(SpeedBubble(center=(0, 0), radius_m=90, time_factor=5.0))
    world.add_power(AirDrag(world))
    world.run(6.0)
    outside_data = world.history.body("outside")
    inside_data = world.history.body("inside")
    outside_time = outside_data["t"][np.argmax(outside_data["on_ground"])]
    inside_time = inside_data["t"][np.argmax(inside_data["on_ground"])]
    outside_landing = -outside_data["vy"][np.argmax(outside_data["on_ground"]) - 1]
    inside_landing = -inside_data["vy"][np.argmax(inside_data["on_ground"]) - 1]
    print(f"bubbled faller: lands at {inside_time:.2f} s vs {outside_time:.2f} s "
          f"(ratio {outside_time / inside_time:.1f}, expect ~5), landing speeds "
          f"{inside_landing:.2f} vs {outside_landing:.2f} m/s (expect equal)")
    assert abs(outside_time / inside_time - 5.0) < 0.4
    assert abs(inside_landing - outside_landing) / outside_landing < 0.02


if __name__ == "__main__":
    check_free_fall()
    check_momentum_conserving_mass_change()
    check_anchored_launch()
    check_midair_coin_is_no_anchor()
    check_coin_drop_launch()
    check_feruchemy_is_zero_sum()
    check_storing_midfall_speeds_you_up()
    check_bubble_compresses_time()
    check_exit_speed_is_emergent()
    check_wayne_heals_fast_in_a_bubble()
    check_cadmium_stretches_time()
    check_compounding_breaks_zero_sum()
    check_miles_dies_when_the_metal_runs_out()
    check_steelrunner_footrace()
    check_steelmind_is_zero_sum()
    check_steel_speed_is_not_a_bubble()
    check_steel_velocity_is_kept_but_bubble_velocity_is_not()
    check_static_grip_breaks_then_falls_off()
    check_shallow_push_skitters_steep_push_anchors()
    check_fixed_anchor_gives_horizontal_launch()
    check_multi_target_push_shares_one_budget()
    check_steel_reserve_runs_dry()
    check_flaring_trades_push_for_metal()
    check_iron_is_an_energy_pump()
    check_pulled_coins_never_anchor()
    check_grapple_to_fixed_metal()
    check_rigid_constraint_stability()
    check_bubble_slows_rigid_bullets()
    check_tilted_bullet_turns_and_spins()
    check_rigid_frame_holds_shape_and_momentum()
    check_dead_center_crossing_is_symmetric()
    check_off_center_crossing_turns_and_spins()
    check_wide_bullet_slows_at_each_crossing()
    check_terminal_velocity_matches_paper()
    check_lighter_bodies_fall_slower()
    check_bubbled_faller_lands_sooner_not_harder()
    print("all probes passed")
