"""Single source of truth for every vehicle in RAGDOLL CRASH PHYSICS.

Coordinates are Roblox studs, Roblox axes: +X right, +Y up, -Z is the FRONT of
the vehicle. y = 0 is the ground under the wheels.

Running this file writes:
  blender/vehicles.json                       (read by build_vehicles.py in Blender)
  roblox/src/shared/VehicleSpecs.luau         (read by the game's VehicleBuilder)
so the Blender meshes and the in-game part-built vehicles always agree on size.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def P(name, size, pos, color, mat="body", shape="box", axis="x", face="front", collide=None):
    """One primitive. shape: box | cyl | wedge. axis: cylinder axis (x|y|z).
    face: wedge low edge points 'front' (-Z) or 'back' (+Z).
    mat: body | glass | light | dark | metal | rubber | neon."""
    if collide is None:
        collide = mat in ("body", "metal", "dark") and min(size) >= 0.6
    return dict(name=name, size=[round(v, 3) for v in size], pos=[round(v, 3) for v in pos],
                color=color, mat=mat, shape=shape, axis=axis, face=face, collide=collide)


def wheels4(track, zf, zr, r, w):
    return [dict(pos=[sx * track / 2, r, z], radius=r, width=w)
            for z in (zf, zr) for sx in (-1, 1)]


def car(L, W, color, *, clear=0.8, bh=1.9, cab_h=1.7, cab_len=None, cab_z=0.6, wheel_r=1.25,
        wheel_w=1.0, accent="#1b1d22", extras=None, hood_wedge=False, spoiler=False):
    """Generic blocky road car. Front is -Z."""
    cab_len = cab_len or L * 0.45
    y0 = clear
    parts = [
        P("Body", (W, bh, L), (0, y0 + bh / 2, 0), color),
        P("Cabin", (W - 0.8, cab_h, cab_len), (0, y0 + bh + cab_h / 2, cab_z), "#9fd3ee", "glass"),
        P("Roof", (W - 0.6, 0.3, cab_len - 0.8), (0, y0 + bh + cab_h + 0.15, cab_z), color),
        P("Hood", (W - 0.4, 0.2, L / 2 + cab_z - cab_len / 2 - 0.3),
          (0, y0 + bh + 0.1, (-L / 2 + cab_z - cab_len / 2) / 2), color, collide=False),
        P("BumperF", (W + 0.3, 0.7, 0.6), (0, y0 + 0.45, -L / 2 - 0.2), accent, "dark"),
        P("BumperR", (W + 0.3, 0.7, 0.6), (0, y0 + 0.45, L / 2 + 0.2), accent, "dark"),
        P("Grille", (W * 0.5, 0.6, 0.15), (0, y0 + 1.2, -L / 2 - 0.05), "#101114", "dark", collide=False),
        P("HeadlightL", (1.1, 0.5, 0.2), (-W / 2 + 0.9, y0 + 1.3, -L / 2 - 0.05), "#fff6c8", "light"),
        P("HeadlightR", (1.1, 0.5, 0.2), (W / 2 - 0.9, y0 + 1.3, -L / 2 - 0.05), "#fff6c8", "light"),
        P("BrakeL", (1.1, 0.45, 0.2), (-W / 2 + 0.9, y0 + 1.3, L / 2 + 0.05), "#d21f1f", "light"),
        P("BrakeR", (1.1, 0.45, 0.2), (W / 2 - 0.9, y0 + 1.3, L / 2 + 0.05), "#d21f1f", "light"),
    ]
    for sx, n in ((-1, "L"), (1, "R")):
        for z, m in ((cab_z - cab_len / 2 + 0.2, "A"), (cab_z + cab_len / 2 - 0.2, "C")):
            parts.append(P("Pillar%s%s" % (m, n), (0.35, cab_h, 0.35),
                           (sx * (W / 2 - 0.45), y0 + bh + cab_h / 2, z), color, collide=False))
    if hood_wedge:
        parts.append(P("Nose", (W, bh * 0.75, 1.1), (0, y0 + bh * 0.375, -L / 2 - 1.05), color, shape="wedge", face="front"))
    if spoiler:
        parts.append(P("Spoiler", (W, 0.2, 1.0), (0, y0 + bh + 0.9, L / 2 - 0.6), accent, "dark", collide=False))
        for sx in (-1, 1):
            parts.append(P("SpoilerLeg", (0.25, 0.8, 0.3), (sx * (W / 2 - 0.8), y0 + bh + 0.4, L / 2 - 0.6), accent, "dark", collide=False))
    parts += extras or []
    wb = L * 0.31
    return dict(carStyle=True, parts=parts, wheels=wheels4(W - wheel_w, -wb, wb, wheel_r, wheel_w),
                seat=[-W / 4 if W > 5 else 0, y0 + bh - 0.2, cab_z - 0.4])


V = {}
ORDER = []


def add(key, display, category, klass, phys, model, stats, spawn="Road", mass=400, impact=1.0):
    model.update(key=key, display=display, category=category, klass=klass, phys=phys,
                 stats=stats, spawn=spawn, mass=mass, impact=impact)
    V[key] = model
    ORDER.append(key)


def carphys(maxSpeed, accel, turn, grip=1.0):
    return dict(kind="car", maxSpeed=maxSpeed, accel=accel, turn=turn, grip=grip)


# ---------------------------------------------------------------- CARS
add("Sedan", "Sedan", "Cars", "Light / Medium", carphys(95, 42, 1.9),
    car(15, 7, "#2f7fe0"), dict(speed=3, weight=2, handling=4), mass=420)

add("SportsCar", "Sports Car", "Cars", "Light / Fast", carphys(150, 70, 2.2, 1.2),
    car(15.5, 7.2, "#ffd21a", clear=0.55, bh=1.5, cab_h=1.3, cab_len=6, cab_z=1.2, wheel_r=1.15,
        wheel_w=1.2, hood_wedge=True, spoiler=True),
    dict(speed=5, weight=1, handling=5), mass=360)

add("PoliceCar", "Police Car", "Cars", "Light / Fast", carphys(125, 55, 2.0),
    car(15.5, 7, "#f4f5f7", accent="#15171c", extras=[
        P("DoorStripeL", (0.12, 1.5, 5.2), (-3.52, 1.75, 0.6), "#15171c", "dark", collide=False),
        P("DoorStripeR", (0.12, 1.5, 5.2), (3.52, 1.75, 0.6), "#15171c", "dark", collide=False),
        P("LightBarBase", (4.2, 0.25, 0.9), (0, 4.82, 0.6), "#22252b", "dark", collide=False),
        P("SirenRed", (1.9, 0.5, 0.8), (-1.05, 5.2, 0.6), "#ff2b2b", "neon"),
        P("SirenBlue", (1.9, 0.5, 0.8), (1.05, 5.2, 0.6), "#2b6bff", "neon"),
        P("PushBar", (5.2, 1.5, 0.35), (0, 1.75, -8.45), "#22252b", "metal"),
    ]), dict(speed=4, weight=2, handling=4), mass=450)

add("MuscleCar", "Muscle Car", "Cars", "Medium / Fast", carphys(135, 60, 1.7, 0.85),
    car(17, 7.4, "#c2261f", clear=0.7, bh=1.8, cab_h=1.4, cab_len=6.2, cab_z=1.6, wheel_r=1.4,
        wheel_w=1.4, spoiler=True, extras=[
            P("HoodScoop", (2.2, 0.55, 2.6), (0, 2.85, -4.4), "#15171c", "dark", collide=False),
            P("StripeL", (0.9, 0.06, 5.6), (-0.8, 2.74, -4.6), "#f4f5f7", "dark", collide=False),
            P("StripeR", (0.9, 0.06, 5.6), (0.8, 2.74, -4.6), "#f4f5f7", "dark", collide=False),
        ]), dict(speed=4, weight=3, handling=3), mass=520)

# ---------------------------------------------------------------- HEAVY
add("PickupTruck", "Pickup Truck", "Heavy", "Medium / Tough", carphys(100, 40, 1.6),
    car(18, 7.6, "#3d8f4a", clear=1.3, bh=2.2, cab_h=2.0, cab_len=5.2, cab_z=-1.6, wheel_r=1.7,
        wheel_w=1.3, extras=[
            P("BedWallL", (0.4, 1.3, 7.0), (-3.6, 4.15, 5.2), "#3d8f4a"),
            P("BedWallR", (0.4, 1.3, 7.0), (3.6, 4.15, 5.2), "#3d8f4a"),
            P("Tailgate", (7.6, 1.3, 0.4), (0, 4.15, 8.8), "#3d8f4a"),
            P("BedFront", (7.6, 1.3, 0.4), (0, 4.15, 1.6), "#3d8f4a"),
        ]), dict(speed=3, weight=3, handling=3), spawn="Road", mass=700, impact=1.2)

add("MonsterTruck", "Monster Truck", "Heavy", "Heavy / Bouncy", carphys(105, 46, 1.5, 0.9),
    car(16, 8, "#8a2be2", clear=4.2, bh=2.2, cab_h=1.9, cab_len=6, cab_z=0.4, wheel_r=3.6,
        wheel_w=3.0, extras=[
            P("AxleF", (11, 0.8, 0.8), (0, 3.6, -4.96), "#30333a", "metal", shape="cyl", axis="x"),
            P("AxleR", (11, 0.8, 0.8), (0, 3.6, 4.96), "#30333a", "metal", shape="cyl", axis="x"),
            P("FrameRail", (3.5, 0.8, 12), (0, 3.9, 0), "#30333a", "metal"),
            P("FlameL", (0.1, 1.0, 5), (-4.03, 5.3, -3), "#ffd21a", "neon", collide=False),
            P("FlameR", (0.1, 1.0, 5), (4.03, 5.3, -3), "#ffd21a", "neon", collide=False),
            P("RollBar", (7, 0.4, 0.4), (0, 8.6, 4.2), "#30333a", "metal", collide=False),
        ]), dict(speed=3, weight=4, handling=2), mass=1400, impact=1.5)
for w in V["MonsterTruck"]["wheels"]:
    w["pos"][0] = (1 if w["pos"][0] > 0 else -1) * 5.6

add("CityBus", "City Bus", "Heavy", "Heavy / Long", carphys(80, 26, 1.1),
    dict(parts=[
        P("Body", (9, 2.6, 36), (0, 2.5, 0), "#f2f4f6"),
        P("Windows", (8.6, 3.2, 34), (0, 5.4, 0), "#9fd3ee", "glass"),
        P("UpperBody", (9, 0.9, 36), (0, 7.45, 0), "#f2f4f6"),
        P("Roof", (8.6, 0.4, 35), (0, 8.1, 0), "#e3e6ea"),
        P("AirCon", (5, 0.9, 8), (0, 8.7, 6), "#d5d9de", collide=False),
        P("Stripe", (9.06, 0.9, 36.02), (0, 3.3, 0), "#0b8f8a", "dark", collide=False),
        P("DestSign", (6, 0.9, 0.2), (0, 7.4, -18.05), "#ff9a1a", "neon"),
        P("BumperF", (9.2, 0.9, 0.5), (0, 1.6, -18.2), "#15171c", "dark"),
        P("BumperR", (9.2, 0.9, 0.5), (0, 1.6, 18.2), "#15171c", "dark"),
        P("HeadlightL", (1.4, 0.6, 0.2), (-3.2, 2.5, -18.05), "#fff6c8", "light"),
        P("HeadlightR", (1.4, 0.6, 0.2), (3.2, 2.5, -18.05), "#fff6c8", "light"),
        P("BrakeL", (0.8, 1.6, 0.2), (-3.9, 3.4, 18.05), "#d21f1f", "light"),
        P("BrakeR", (0.8, 1.6, 0.2), (3.9, 3.4, 18.05), "#d21f1f", "light"),
        P("Floor", (8.2, 0.3, 34), (0, 3.9, 0), "#55585f", "dark"),
    ], wheels=wheels4(9 - 1.5, -11.5, 10.5, 1.9, 1.5), seat=[-2.2, 4.3, -15.5]),
    dict(speed=2, weight=4, handling=2), mass=1800, impact=1.6)

add("DumpTruck", "Dump Truck", "Heavy", "Very Heavy / Slow", carphys(70, 24, 1.0),
    dict(parts=[
        P("Frame", (8.6, 1.6, 26), (0, 3.2, 0), "#30333a", "metal"),
        P("Cab", (9, 4.2, 6), (0, 6.1, -9.6), "#ff8a1f"),
        P("CabGlass", (8.4, 1.9, 0.3), (0, 7.0, -12.7), "#9fd3ee", "glass"),
        P("CabSideGlassL", (0.2, 1.7, 3.2), (-4.55, 7.0, -9.8), "#9fd3ee", "glass"),
        P("CabSideGlassR", (0.2, 1.7, 3.2), (4.55, 7.0, -9.8), "#9fd3ee", "glass"),
        P("BedFloor", (9.6, 0.6, 17), (0, 4.6, 3.8), "#ff8a1f"),
        P("BedWallL", (0.6, 4.2, 17), (-4.5, 7.0, 3.8), "#ff8a1f"),
        P("BedWallR", (0.6, 4.2, 17), (4.5, 7.0, 3.8), "#ff8a1f"),
        P("BedFront", (9.6, 5.0, 0.6), (0, 7.4, -4.6), "#ff8a1f"),
        P("BedVisor", (9.6, 0.5, 4.5), (0, 10.1, -6.6), "#ff8a1f"),
        P("Tailgate", (9.6, 3.4, 0.5), (0, 6.6, 12.3), "#e07010"),
        P("BumperF", (9.6, 1.4, 0.9), (0, 2.9, -13.2), "#15171c", "dark"),
        P("HeadlightL", (1.3, 0.8, 0.2), (-3.3, 4.6, -12.7), "#fff6c8", "light"),
        P("HeadlightR", (1.3, 0.8, 0.2), (3.3, 4.6, -12.7), "#fff6c8", "light"),
        P("BrakeL", (1.3, 0.7, 0.2), (-3.3, 3.4, 13.05), "#d21f1f", "light"),
        P("BrakeR", (1.3, 0.7, 0.2), (3.3, 3.4, 13.05), "#d21f1f", "light"),
        P("Exhaust", (0.6, 5, 0.6), (4.0, 8.4, -6.0), "#9aa0a8", "metal", shape="cyl", axis="y", collide=False),
    ], wheels=wheels4(9.6, -9.5, 7.5, 2.5, 2.0) + wheels4(9.6, 3.0, 3.0, 2.5, 2.0)[:2], seat=[-2.2, 5.2, -9.4]),
    dict(speed=2, weight=5, handling=1), mass=2600, impact=1.9)

# ---------------------------------------------------------------- MILITARY-STYLE TEST VEHICLES
TANK_GREEN = "#4b5d3a"
tank_parts = [
    P("Hull", (10, 2.6, 20), (0, 2.6, 0), TANK_GREEN),
    P("HullFront", (10, 2.6, 3), (0, 2.6, -11.5), TANK_GREEN, shape="wedge", face="front"),
    P("HullRear", (10, 2.6, 1.5), (0, 2.6, 10.75), TANK_GREEN, shape="wedge", face="back"),
    P("TrackL", (2.6, 2.8, 22), (-6.3, 1.4, 0), "#1c1e22", "rubber", collide=True),
    P("TrackR", (2.6, 2.8, 22), (6.3, 1.4, 0), "#1c1e22", "rubber", collide=True),
    P("TrackGuardL", (3.0, 0.3, 23), (-6.3, 3.0, 0), TANK_GREEN, collide=False),
    P("TrackGuardR", (3.0, 0.3, 23), (6.3, 3.0, 0), TANK_GREEN, collide=False),
    P("TurretRing", (7, 0.5, 7), (0, 4.15, 0.5), "#3b4a2d", "metal", shape="cyl", axis="y"),
    P("Turret", (7.4, 2.2, 8.4), (0, 5.5, 0.8), TANK_GREEN),
    P("TurretCheek", (7.4, 2.2, 1.6), (0, 5.5, -4.2), TANK_GREEN, shape="wedge", face="front"),
    P("Barrel", (0.9, 0.9, 11), (0, 5.6, -9.2), "#3b4a2d", "metal", shape="cyl", axis="z"),
    P("Muzzle", (1.3, 1.3, 1.4), (0, 5.6, -14.6), "#2a3520", "metal", shape="cyl", axis="z"),
    P("Hatch", (2.4, 0.4, 2.4), (1.4, 6.8, 1.8), "#3b4a2d", "metal", shape="cyl", axis="y", collide=False),
    P("HeadlightL", (0.8, 0.6, 0.3), (-3.8, 3.5, -10.0), "#fff6c8", "light"),
    P("HeadlightR", (0.8, 0.6, 0.3), (3.8, 3.5, -10.0), "#fff6c8", "light"),
    P("TestMarking", (0.08, 1.2, 3.2), (-5.02, 2.9, 2), "#f4f5f7", "dark", collide=False),
]
for sx, n in ((-1, "L"), (1, "R")):
    for i, z in enumerate((-9, -4.5, 0, 4.5, 9)):
        tank_parts.append(P("RoadWheel%s%d" % (n, i), (0.5, 2.3, 2.3), (sx * 7.7, 1.3, z), "#3b4a2d", "metal",
                            shape="cyl", axis="x", collide=False))
add("Tank", "Tank", "Military", "Heavy / Slow",
    dict(kind="tank", maxSpeed=48, accel=14, turn=0.9, grip=2.0),
    dict(parts=tank_parts, wheels=[], seat=[0, 4.2, -3.0],
         turret=["TurretRing", "Turret", "TurretCheek", "Barrel", "Muzzle", "Hatch"], turretPivot=[0, 4.15, 0.5]),
    dict(speed=1, weight=5, handling=1), spawn="TankField", mass=9000, impact=2.6)

add("ArmoredTruck", "Armored Truck", "Military", "Heavy / Medium", carphys(85, 30, 1.3),
    dict(parts=[
        P("Body", (9, 3.2, 20), (0, 3.4, 0), "#6a7566"),
        P("Cabin", (9, 2.6, 9), (0, 6.3, 2.5), "#6a7566"),
        P("Nose", (9, 2.6, 4.0), (0, 6.3, -4.0), "#6a7566", shape="wedge", face="front"),
        P("WindshieldSlit", (6.5, 0.8, 0.2), (0, 6.6, -2.2), "#9fd3ee", "glass", collide=False),
        P("SlitL", (0.2, 0.7, 4), (-4.55, 6.6, 2), "#9fd3ee", "glass", collide=False),
        P("SlitR", (0.2, 0.7, 4), (4.55, 6.6, 2), "#9fd3ee", "glass", collide=False),
        P("RamBar", (9.6, 2.2, 0.8), (0, 3.2, -10.6), "#2b2f33", "metal"),
        P("RearBox", (8.6, 2.0, 5), (0, 6.0, 9.4), "#5b6557"),
        P("HeadlightL", (1.0, 0.7, 0.2), (-3.3, 4.6, -10.05), "#fff6c8", "light"),
        P("HeadlightR", (1.0, 0.7, 0.2), (3.3, 4.6, -10.05), "#fff6c8", "light"),
        P("BrakeL", (1.0, 0.6, 0.2), (-3.3, 4.2, 10.05), "#d21f1f", "light"),
        P("BrakeR", (1.0, 0.6, 0.2), (3.3, 4.2, 10.05), "#d21f1f", "light"),
    ], wheels=wheels4(9.4, -6.5, 6.5, 2.1, 1.7), seat=[-2.0, 5.3, 0.5]),
    dict(speed=2, weight=4, handling=2), spawn="TankField", mass=2400, impact=1.8)

# ---------------------------------------------------------------- AIRCRAFT
def plane(scale, color, trim, cargo=False):
    s = scale
    fl = 22 * s          # fuselage length
    fw = 3.2 * s if not cargo else 6.0 * s
    fh = 3.2 * s if not cargo else 5.6 * s
    gy = 2.2 * s if not cargo else 2.0 * s   # belly height above ground
    cy = gy + fh / 2
    span = 34 * s if not cargo else 46 * s
    parts = [
        P("Fuselage", (fw, fh, fl), (0, cy, 0), color),
        P("NoseCone", (fw * 0.8, fh * 0.8, 2.2 * s), (0, cy, -fl / 2 - 1.1 * s), trim, shape="cyl", axis="z"),
        P("TailTaper", (fw, fh, 5 * s), (0, cy, fl / 2 + 2.5 * s), color, shape="wedge", face="back"),
        P("Cockpit", (fw * 0.8, 1.3 * s, 4.6 * s), (0, cy + fh / 2 + 0.6 * s, -fl * 0.16), "#9fd3ee", "glass"),
        P("Wing", (span, 0.5 * s, 5.2 * s), (0, cy + (fh / 2 if cargo else -fh * 0.25), -fl * 0.08), color),
        P("WingStripeL", (4 * s, 0.52 * s, 5.25 * s), (-span / 2 + 3 * s, cy + (fh / 2 if cargo else -fh * 0.25), -fl * 0.08), trim, collide=False),
        P("WingStripeR", (4 * s, 0.52 * s, 5.25 * s), (span / 2 - 3 * s, cy + (fh / 2 if cargo else -fh * 0.25), -fl * 0.08), trim, collide=False),
        P("TailPlane", (12 * s, 0.4 * s, 3 * s), (0, cy + fh * 0.3, fl / 2 + 3.2 * s), color),
        P("Fin", (0.5 * s, 4.6 * s, 3.4 * s), (0, cy + fh / 2 + 2.0 * s, fl / 2 + 3.0 * s), trim),
        P("GearStrutN", (0.4 * s, gy, 0.4 * s), (0, gy / 2 + 0.5, -fl * 0.36), "#9aa0a8", "metal", collide=False),
        P("GearStrutL", (0.4 * s, gy, 0.4 * s), (-3.2 * s, gy / 2 + 0.5, 0.5 * s), "#9aa0a8", "metal", collide=False),
        P("GearStrutR", (0.4 * s, gy, 0.4 * s), (3.2 * s, gy / 2 + 0.5, 0.5 * s), "#9aa0a8", "metal", collide=False),
    ]
    props = []
    engines = [0] if not cargo else [-span * 0.2, span * 0.2]
    for i, ex in enumerate(engines):
        ez = -fl / 2 - 2.5 * s if not cargo else -fl * 0.08 - 4.2 * s
        ey = cy if not cargo else cy + fh / 2 - 0.9 * s
        if cargo:
            parts.append(P("Engine%d" % i, (2.0 * s, 2.0 * s, 4.4 * s), (ex, ey, ez + 2.0 * s), trim, shape="cyl", axis="z"))
        parts.append(P("PropHub%d" % i, (1.0 * s, 1.0 * s, 0.9 * s), (ex, ey, ez), "#22252b", "metal", shape="cyl", axis="z", collide=False))
        parts.append(P("PropBladeA%d" % i, (7.5 * s, 0.7 * s, 0.2 * s), (ex, ey, ez - 0.2 * s), "#22252b", "dark", collide=False))
        parts.append(P("PropBladeB%d" % i, (0.7 * s, 7.5 * s, 0.2 * s), (ex, ey, ez - 0.2 * s), "#22252b", "dark", collide=False))
        props.append(dict(parts=["PropHub%d" % i, "PropBladeA%d" % i, "PropBladeB%d" % i], pivot=[ex, ey, ez], axis="z"))
    r = 1.0 * s
    wheels = [dict(pos=[0, r, -fl * 0.36], radius=r, width=0.7 * s),
              dict(pos=[-3.2 * s, r, 0.5 * s], radius=r, width=0.7 * s),
              dict(pos=[3.2 * s, r, 0.5 * s], radius=r, width=0.7 * s)]
    return dict(parts=parts, wheels=wheels, seat=[0, cy - 0.4 * s, -fl * 0.16], spinners=props)


add("SmallPlane", "Small Plane", "Aircraft", "Aircraft / Medium",
    dict(kind="plane", maxSpeed=170, accel=38, takeoff=62, turn=1.1, pitch=1.0, roll=2.2),
    plane(1.0, "#f4f5f7", "#e2342b"), dict(speed=4, weight=2, handling=3), spawn="Runway", mass=500, impact=1.3)

add("CargoPlane", "Cargo Plane", "Aircraft", "Aircraft / Heavy",
    dict(kind="plane", maxSpeed=150, accel=24, takeoff=78, turn=0.6, pitch=0.6, roll=1.1),
    plane(1.5, "#aeb6bf", "#2f7fe0", cargo=True), dict(speed=3, weight=5, handling=1), spawn="Runway", mass=3200, impact=2.2)

add("Helicopter", "Helicopter", "Aircraft", "Aircraft / Hover",
    dict(kind="heli", maxSpeed=95, accel=30, climb=38, turn=1.6),
    dict(parts=[
        P("Cabin", (6, 5, 9), (0, 4.2, 0), "#e2342b"),
        P("NoseGlass", (5.4, 3.4, 2.4), (0, 4.4, -5.6), "#9fd3ee", "glass"),
        P("SideGlassL", (0.2, 2.2, 4), (-3.05, 4.9, -1.2), "#9fd3ee", "glass", collide=False),
        P("SideGlassR", (0.2, 2.2, 4), (3.05, 4.9, -1.2), "#9fd3ee", "glass", collide=False),
        P("TailBoom", (1.4, 1.4, 13), (0, 5.4, 10.6), "#e2342b", shape="cyl", axis="z"),
        P("TailFin", (0.4, 3.6, 2.2), (0, 6.6, 16.4), "#f4f5f7"),
        P("Mast", (0.8, 1.6, 0.8), (0, 7.5, 0), "#30333a", "metal", shape="cyl", axis="y", collide=False),
        P("RotorHub", (1.6, 0.5, 1.6), (0, 8.4, 0), "#22252b", "metal", shape="cyl", axis="y", collide=False),
        P("RotorBladeA", (26, 0.2, 1.3), (0, 8.5, 0), "#22252b", "dark", collide=False),
        P("RotorBladeB", (1.3, 0.2, 26), (0, 8.5, 0), "#22252b", "dark", collide=False),
        P("TailRotorHub", (0.5, 0.7, 0.7), (0.9, 6.6, 16.6), "#22252b", "metal", shape="cyl", axis="x", collide=False),
        P("TailRotorBlade", (0.15, 5, 0.6), (1.1, 6.6, 16.6), "#22252b", "dark", collide=False),
        P("SkidL", (0.5, 0.5, 11), (-3.2, 0.35, -0.5), "#30333a", "metal", shape="cyl", axis="z", collide=True),
        P("SkidR", (0.5, 0.5, 11), (3.2, 0.35, -0.5), "#30333a", "metal", shape="cyl", axis="z", collide=True),
        P("SkidLegFL", (0.3, 1.6, 0.3), (-3.0, 1.1, -3), "#30333a", "metal", collide=False),
        P("SkidLegFR", (0.3, 1.6, 0.3), (3.0, 1.1, -3), "#30333a", "metal", collide=False),
        P("SkidLegRL", (0.3, 1.6, 0.3), (-3.0, 1.1, 2.5), "#30333a", "metal", collide=False),
        P("SkidLegRR", (0.3, 1.6, 0.3), (3.0, 1.1, 2.5), "#30333a", "metal", collide=False),
    ], wheels=[], seat=[-1.3, 3.2, -2.0],
        spinners=[dict(parts=["RotorHub", "RotorBladeA", "RotorBladeB"], pivot=[0, 8.4, 0], axis="y"),
                  dict(parts=["TailRotorHub", "TailRotorBlade"], pivot=[0.9, 6.6, 16.6], axis="x")]),
    dict(speed=3, weight=3, handling=4), spawn="Helipad", mass=900, impact=1.4)

# ---------------------------------------------------------------- SPECIAL
train_parts = [
    P("Chassis", (9, 1.6, 38), (0, 2.6, 0), "#22252b", "metal"),
    P("Boiler", (7, 7, 22), (0, 7.0, -6), "#1f4fa8", shape="cyl", axis="z"),
    P("SmokeBox", (7.4, 7.4, 2.4), (0, 7.0, -18), "#15171c", "dark", shape="cyl", axis="z"),
    P("Cab", (9, 8.5, 10), (0, 7.6, 12), "#1f4fa8"),
    P("CabRoof", (10, 0.6, 11.4), (0, 12.1, 12), "#15171c", "dark"),
    P("CabGlassL", (0.2, 2.6, 4.5), (-4.55, 9.2, 12), "#9fd3ee", "glass", collide=False),
    P("CabGlassR", (0.2, 2.6, 4.5), (4.55, 9.2, 12), "#9fd3ee", "glass", collide=False),
    P("Chimney", (2.2, 3.6, 2.2), (0, 11.8, -14), "#15171c", "dark", shape="cyl", axis="y"),
    P("Dome", (2.6, 1.8, 2.6), (0, 11.2, -5), "#ffd21a", "metal", shape="cyl", axis="y", collide=False),
    P("CowCatcher", (9, 3.0, 4.5), (0, 1.9, -21.2), "#e2342b", "metal", shape="wedge", face="front"),
    P("Headlamp", (1.6, 1.6, 0.8), (0, 11.0, -19.4), "#fff6c8", "light", shape="cyl", axis="z"),
    P("BufferBeam", (9.4, 1.4, 0.8), (0, 2.8, 19.4), "#e2342b", "metal"),
]
for sx, n in ((-1, "L"), (1, "R")):
    for i, z in enumerate((-13, -6.5, 0, 6.5, 13)):
        train_parts.append(P("Wheel%s%d" % (n, i), (0.8, 4.2, 4.2) if i in (1, 2, 3) else (0.8, 3.0, 3.0),
                             (sx * 4.2, 2.1 if i in (1, 2, 3) else 1.5, z), "#e2342b", "metal", shape="cyl", axis="x", collide=False))
    train_parts.append(P("SideRod%s" % n, (0.3, 0.5, 14.5), (sx * 4.8, 2.1, 0), "#9aa0a8", "metal", collide=False))
add("Train", "Train", "Special", "Massive / Rail",
    dict(kind="train", maxSpeed=110, accel=16),
    dict(parts=train_parts, wheels=[], seat=[0, 5.2, 12]),
    dict(speed=3, weight=5, handling=0), spawn="Rail", mass=20000, impact=3.2)

add("Bulldozer", "Bulldozer", "Special", "Heavy / Pusher",
    dict(kind="tank", maxSpeed=34, accel=12, turn=0.8, grip=2.0),
    dict(parts=[
        P("Body", (8, 3.0, 12), (0, 3.2, 1), "#f2b90f"),
        P("EngineBox", (6.4, 2.4, 6), (0, 5.4, -2.2), "#f2b90f"),
        P("Cab", (6, 3.6, 4.6), (0, 6.5, 3.6), "#9fd3ee", "glass"),
        P("CabRoof", (6.6, 0.4, 5.2), (0, 8.5, 3.6), "#f2b90f"),
        P("TrackL", (2.4, 3.0, 15), (-5.2, 1.5, 1), "#1c1e22", "rubber", collide=True),
        P("TrackR", (2.4, 3.0, 15), (5.2, 1.5, 1), "#1c1e22", "rubber", collide=True),
        P("Blade", (15, 4.6, 0.9), (0, 2.5, -9.2), "#c9cdd3", "metal"),
        P("BladeLip", (15, 1.4, 1.6), (0, 0.9, -10.0), "#c9cdd3", "metal", shape="wedge", face="front"),
        P("ArmL", (0.8, 0.9, 9), (-6.9, 2.4, -4.5), "#30333a", "metal"),
        P("ArmR", (0.8, 0.9, 9), (6.9, 2.4, -4.5), "#30333a", "metal"),
        P("Exhaust", (0.6, 2.6, 0.6), (1.8, 7.8, -3.5), "#30333a", "metal", shape="cyl", axis="y", collide=False),
        P("BrakeL", (1.0, 0.6, 0.2), (-3, 3.8, 7.05), "#d21f1f", "light"),
        P("BrakeR", (1.0, 0.6, 0.2), (3, 3.8, 7.05), "#d21f1f", "light"),
    ], wheels=[], seat=[0, 5.3, 3.4]),
    dict(speed=1, weight=5, handling=1), spawn="TankField", mass=6000, impact=2.2)

add("GoKart", "Go-Kart", "Special", "Tiny / Zippy", carphys(105, 75, 2.8, 1.3),
    dict(parts=[
        P("Frame", (4.4, 0.5, 7.5), (0, 0.75, 0), "#e2342b"),
        P("NoseFairing", (3.2, 0.9, 2.2), (0, 1.1, -3.6), "#e2342b", shape="wedge", face="front"),
        P("SeatBack", (2.2, 2.0, 0.5), (0, 2.0, 1.6), "#15171c", "dark"),
        P("SteeringColumn", (0.25, 1.6, 0.25), (0, 1.8, -1.4), "#30333a", "metal", collide=False),
        P("SteeringWheel", (1.5, 1.5, 0.25), (0, 2.6, -1.3), "#15171c", "dark", shape="cyl", axis="z", collide=False),
        P("Engine", (1.8, 1.3, 1.5), (0.9, 1.6, 3.0), "#9aa0a8", "metal"),
        P("BumperF", (4.8, 0.4, 0.4), (0, 0.8, -4.3), "#30333a", "metal"),
        P("BumperR", (4.8, 0.4, 0.4), (0, 0.8, 4.0), "#30333a", "metal"),
    ], wheels=wheels4(4.8, -2.6, 2.7, 0.8, 0.8), seat=[0, 1.1, 0.6]),
    dict(speed=3, weight=1, handling=5), mass=140, impact=0.7)

add("RocketSled", "Rocket Sled", "Special", "Extreme / Straight Line",
    dict(kind="sled", maxSpeed=380, accel=160, turn=0.25, grip=3.0),
    dict(parts=[
        P("Sled", (5, 1.0, 16), (0, 1.0, 0), "#f4f5f7"),
        P("Nose", (5, 2.4, 5), (0, 1.7, -10.5), "#e2342b", shape="wedge", face="front"),
        P("SeatShell", (3.2, 2.6, 4), (0, 2.8, -3), "#15171c", "dark"),
        P("RocketL", (2.0, 2.0, 10), (-1.6, 3.0, 3.5), "#c9cdd3", "metal", shape="cyl", axis="z"),
        P("RocketR", (2.0, 2.0, 10), (1.6, 3.0, 3.5), "#c9cdd3", "metal", shape="cyl", axis="z"),
        P("NozzleL", (2.4, 2.4, 1.4), (-1.6, 3.0, 9.0), "#30333a", "metal", shape="cyl", axis="z"),
        P("NozzleR", (2.4, 2.4, 1.4), (1.6, 3.0, 9.0), "#30333a", "metal", shape="cyl", axis="z"),
        P("FlameL", (1.6, 1.6, 3.0), (-1.6, 3.0, 11.2), "#ff8a1f", "neon", shape="cyl", axis="z"),
        P("FlameR", (1.6, 1.6, 3.0), (1.6, 3.0, 11.2), "#ff8a1f", "neon", shape="cyl", axis="z"),
        P("SkidL", (0.8, 0.5, 17), (-2.6, 0.25, 0), "#30333a", "metal", collide=True),
        P("SkidR", (0.8, 0.5, 17), (2.6, 0.25, 0), "#30333a", "metal", collide=True),
        P("FinL", (0.3, 2.4, 3), (-2.6, 2.6, 6), "#e2342b", collide=False),
        P("FinR", (0.3, 2.4, 3), (2.6, 2.6, 6), "#e2342b", collide=False),
    ], wheels=[], seat=[0, 2.0, -2.6]),
    dict(speed=5, weight=2, handling=0), spawn="SledTrack", mass=600, impact=1.6)


# ---------------------------------------------------------------- cockpits
# First-person view and driver placement, researched per vehicle (see README "Interiors").
# eye     : where the driver's head (eye point) belongs, Roblox axes. The game seats the avatar so
#           its head lands here, puts the first-person camera here, and the Blender interior is
#           built around it (seat under it, controls in reach, dash below the sight line).
# control : what the hands hold. type wheel | yoke | bars | sticks | levers | grips.
#           wheel / yoke / bars: pos = centre, tilt = degrees the rim leans back from vertical,
#           radius (wheel) or width (yoke, bars). sticks / levers / grips: right, left = grip points.
# Roblox avatars sit about 2.75 studs from seat to eye, a lot taller than a real person in a seat
# of the same size, so seats sit low and the eye sits ~0.45 under the headliner.
SEATED_EYE = 2.75


def fwd(eye, f=0.0, up=0.0, right=0.0):
    return [round(eye[0] + right, 3), round(eye[1] + up, 3), round(eye[2] - f, 3)]


def wheel_at(eye, f, down, r, tilt, kind="wheel"):
    return dict(type=kind, pos=fwd(eye, f, -down), tilt=tilt, radius=r)


COCKPITS = {
    # midsize sedan: eye ~0.6 ahead of the B-pillar, 15 in wheel ~19 in from the chest
    "Sedan": dict(eye=[-1.75, 4.43, -0.3], control=("wheel", 1.55, 1.25, 0.6, 25)),
    "PoliceCar": dict(eye=[-1.75, 4.43, -0.35], control=("wheel", 1.55, 1.25, 0.6, 25)),
    # mid-engined supercar: low, reclined, small flat-bottom wheel close to the chest
    "SportsCar": dict(eye=[-1.8, 3.25, 0.9], control=("wheel", 1.45, 1.05, 0.52, 20)),
    # 60s muscle car: thin-rimmed big wheel, upright
    "MuscleCar": dict(eye=[-1.85, 4.0, 1.0], control=("wheel", 1.6, 1.2, 0.68, 22)),
    # regular-cab full-size pickup: high seat, big wheel
    "PickupTruck": dict(eye=[-1.9, 5.65, 0.0], control=("wheel", 1.6, 1.3, 0.7, 30)),
    # monster truck: driver centred in the body for balance and protection
    "MonsterTruck": dict(eye=[0.0, 9.6, -0.5], control=("wheel", 1.45, 1.2, 0.55, 25)),
    # transit bus: raised driver's platform, near-horizontal big wheel
    "CityBus": dict(eye=[-2.3, 6.9, -15.2], control=("wheel", 1.45, 1.45, 0.95, 62)),
    # heavy dump truck: high cab, big wheel on a steep column
    "DumpTruck": dict(eye=[-2.2, 8.3, -7.6], control=("wheel", 1.5, 1.35, 0.85, 40)),
    # tank: driven head-out of the open driver's hatch, T-bar handlebars below
    "Tank": dict(eye=[-2.2, 5.15, -5.0], control=("bars", 0.55, 1.75, 1.3, 15)),
    # armoured truck: upright seat, small thick windscreen panes
    "ArmoredTruck": dict(eye=[-1.4, 6.7, -0.3], control=("wheel", 1.5, 1.25, 0.7, 30)),
    # light aircraft (tandem bubble canopy): yoke, six-pack panel ahead
    "SmallPlane": dict(eye=[-0.75, 6.0, -3.95], control=("yoke", 1.5, 1.05, 0.95, 8)),
    # cargo plane: captain's (left) seat on the flight deck
    "CargoPlane": dict(eye=[-1.3, 9.6, -13.4], control=("yoke", 1.4, 1.2, 1.0, 8)),
    # helicopter: pilot in the right seat; cyclic between the knees, collective on the left
    "Helicopter": dict(eye=[1.3, 5.55, -2.35], control=dict(type="sticks", right=[1.3, 3.85, -3.45], left=[0.5, 3.3, -2.8])),
    # steam locomotive: engineer on the right of the cab (US practice), front window beside the boiler
    "Train": dict(eye=[2.75, 10.4, 8.5], control=dict(type="levers", right=[2.0, 9.45, 7.5], left=[1.5, 8.9, 7.55])),
    # bulldozer: ROPS cab, left joystick steers, right joystick works the blade
    "Bulldozer": dict(eye=[0.0, 8.6, 4.0], control=dict(type="sticks", right=[0.85, 6.6, 3.2], left=[-0.85, 6.6, 3.2])),
    # racing kart: low seat, small wheel, legs straight out
    "GoKart": dict(eye=[0.0, 3.5, 1.2], control=("wheel", 1.85, 1.2, 0.55, 36)),
    # rocket sled (after Sonic Wind No. 1): open seat on top, hand grips either side
    "RocketSled": dict(eye=[0.0, 4.75, -3.6], control=dict(type="grips", right=[0.95, 3.2, -4.4], left=[-0.95, 3.2, -4.4])),
}


def apply_cockpits():
    for key, c in COCKPITS.items():
        eye = c["eye"]
        ctl = c["control"]
        if isinstance(ctl, tuple):
            kind, f, down, size, tilt = ctl
            ctl = dict(type=kind, pos=fwd(eye, f, -down), tilt=tilt)
            ctl["radius" if kind == "wheel" else "width"] = size
        V[key]["cockpit"] = dict(eye=eye, control=ctl, pitch=c.get("pitch", -8))
        # the avatar's root sits at the seat centre with the head straight above it
        V[key]["seat"] = [eye[0], round(eye[1] - SEATED_EYE - 0.3, 3), eye[2]]


apply_cockpits()


# ---------------------------------------------------------------- emit
def lua(v, ind=0):
    pad = "\t" * ind
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(round(v, 3))
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, (list, tuple)):
        if all(isinstance(x, (int, float)) for x in v):
            return "{ " + ", ".join(lua(x) for x in v) + " }"
        return "{\n" + "".join(pad + "\t" + lua(x, ind + 1) + ",\n" for x in v) + pad + "}"
    if isinstance(v, dict):
        flat = all(not isinstance(x, (dict,)) and not (isinstance(x, list) and x and isinstance(x[0], (dict, list)))
                   for x in v.values())
        if flat:
            return "{ " + ", ".join("%s = %s" % (k, lua(x)) for k, x in v.items()) + " }"
        return "{\n" + "".join("%s\t%s = %s,\n" % (pad, k, lua(x, ind + 1)) for k, x in v.items()) + pad + "}"
    raise TypeError(type(v))


def main():
    with open(os.path.join(HERE, "vehicles.json"), "w") as f:
        json.dump(dict(order=ORDER, vehicles=V), f, indent=1)
    out = os.path.join(HERE, "..", "roblox", "src", "shared", "VehicleSpecs.luau")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        f.write("--!strict\n-- GENERATED by blender/vehicles_spec.py — do not edit by hand.\n"
                "-- Studs, Roblox axes, -Z is the vehicle front, y = 0 is the ground.\n"
                "return {\n\tOrder = %s,\n\tVehicles = %s,\n}\n" % (lua(ORDER, 1), lua(V, 1)))
    print("wrote", len(ORDER), "vehicles:", ", ".join(ORDER))


if __name__ == "__main__":
    main()
