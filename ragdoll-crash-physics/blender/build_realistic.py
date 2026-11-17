"""Builds the detailed vehicle models.   python3 build_realistic.py [Vehicle ...] [--no-render]

Output in blender/out/: <Vehicle>.blend / .glb / .fbx, previews/<Vehicle>.png, build_stats.json.
Objects per vehicle (origins match the game's hinge points, 1 unit = 1 stud):
  <V>_Body  <V>_Glass  <V>_Lights  <V>_Trim  <V>_Wheel1..N  <V>_Spin1..N  <V>_Turret
Every object carries a "Col" colour attribute baked from its materials, so each imports into Roblox
as ONE MeshPart with the right colours (Roblox renders vertex colours); Glass / Lights stay separate
so they can use the Glass / Neon materials in Studio.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy
from mathutils import Vector

import rcp_model as M
import rcp_cars as C
C.box, C.cyl, C.lathe, C.loft, C.tube = M.box, M.cyl, M.lathe, M.loft, M.tube

OUT = os.path.join(HERE, "out")
os.makedirs(os.path.join(OUT, "previews"), exist_ok=True)
SPEC = json.load(open(os.path.join(HERE, "vehicles.json")))
RENDER = "--no-render" not in sys.argv
BUILDERS = {}


def builder(key):
    def deco(fn):
        BUILDERS[key] = fn
        return fn
    return deco


def spec(key):
    return SPEC["vehicles"][key]


# ------------------------------------------------------------------ CARS
def car_dims(key, **over):
    s = spec(key)
    w = s["wheels"]
    r = w[0]["radius"]
    zs = sorted({-x["pos"][2] for x in w})
    p = dict(key=key, wheel_r=r, axle_f=zs[-1], axle_r=zs[0])
    p.update(over)
    return p


@builder("Sedan")
def sedan():
    p = car_dims("Sedan", L=15.6, W=7.0, color="#2f6fd0", clear=0.75, belt=3.0, roof=4.8, hood_front=2.72, hood_cowl=3.08,
                 cowl=2.9, ws_top=0.9, roof_rear=-2.9, deck=-4.9, trunk=3.18, b_pillar=-0.9, arch=1.14)
    return C.build_car(p, spec("Sedan")["wheels"])


@builder("SportsCar")
def sports():
    p = car_dims("SportsCar", L=16.2, W=7.2, color="#f6c40f", clear=0.5, belt=2.5, roof=3.72, hood_front=1.85, hood_cowl=2.5,
                 cowl=2.6, ws_top=0.2, roof_rear=-2.3, deck=-5.9, trunk=2.72, b_pillar=-1.0, arch=1.16, roof_w=0.68, nose_w=0.8,
                 tail_w=0.92, wheel_style="sport10", rim_color="#2a2c30", caliper="#d11a1a", crown=0.05, flare=0.04,
                 headlight=(0.52, 0.93, 1.35, 1.72), grille=(0.5, 0.78, 1.25), grille_bars=2, chrome=False,
                 doors=[2.2, -1.0], seat_rows=[0.5], exhausts=(-1.2, -0.6, 0.6, 1.2), taillight=(0.3, 0.95, 2.2, 2.48),
                 flush_handles=True, handle_drop=0.28)

    def extras(p, surf, paint, G):
        hw = p["W"] / 2
        w = C.wing("spoiler", p["W"] * 0.96, 1.25, 0.1, M.DARK())
        M.place(w, (0, -7.2, 3.75), rot=(math.radians(-8), 0, 0))
        G["Trim"].append(w)
        for s in (-1, 1):
            G["Trim"].append(C.loft("pylon", [[(s * 2.3 - 0.05, -7.6, 2.6), (s * 2.3 + 0.05, -7.6, 2.6), (s * 2.3 + 0.05, -6.6, 2.6), (s * 2.3 - 0.05, -6.6, 2.6)],
                                                [(s * 2.3 - 0.04, -7.5, 3.72), (s * 2.3 + 0.04, -7.5, 3.72), (s * 2.3 + 0.04, -6.95, 3.72), (s * 2.3 - 0.04, -6.95, 3.72)]], M.DARK()))
            G["Trim"].append(C.box("endplate", (0.06, 1.4, 0.5), (s * hw * 0.955, -7.2, 3.78), M.DARK(), bev=0.02))
            side = "R" if s > 0 else "L"
            G["Trim"].append(surf.project("intake", side, (-3.6, 1.15, -2.2, 1.95), M.DARK(), 0.012, res=0.07, round_r=0.3))
            G["Trim"].append(surf.project("skirt", side, (-3.4, 0.5, 3.4, 0.72), M.DARK(), 0.02, res=0.15))
        G["Trim"].append(surf.project("splitter", "F", (-hw * 0.86, 0.5, hw * 0.86, 0.66), M.DARK(), 0.03, res=0.1, thickness=0.2))
        G["Trim"].append(surf.project("diffuser", "B", (-hw * 0.7, 0.5, hw * 0.7, 1.1), M.DARK(), 0.02, res=0.1))
        G["Trim"].append(surf.project("enginecover", "T", (-1.6, -5.4, 1.6, -3.0), M.GLASS(), 0.012, res=0.15))
    return C.build_car(p, spec("SportsCar")["wheels"], extras)


@builder("PoliceCar")
def police():
    p = car_dims("PoliceCar", L=16.0, W=7.0, color="#f2f3f5", clear=0.78, belt=3.02, roof=4.82, hood_front=2.75, hood_cowl=3.1,
                 cowl=3.0, ws_top=1.0, roof_rear=-2.9, deck=-5.0, trunk=3.2, b_pillar=-0.9, arch=1.14, wheel_style="steel",
                 rim_color="#1c1d20", chrome=False, antenna=False, black_handles=True)

    def extras(p, surf, paint, G):
        hw = p["W"] / 2
        black = M.paint("#101114")
        for side in ("L", "R"):  # black doors + lettering
            G["Body"].append(surf.project("livery", side, (-2.85, 1.1, 2.6, 3.0), black, 0.008, res=0.12))
            loc, nrm = surf.point(side, -0.1, 2.1)
            s = 1 if side == "R" else -1
            G["Trim"].append(M.text("police", "POLICE", 0.62, (loc.x + s * 0.03, -0.1, 2.1), (math.pi / 2, 0, s * math.pi / 2), M.matte("#f4f4f4", 0.5)))
            loc, _ = surf.point(side, -6.9, 2.5)
            if loc is not None:
                G["Trim"].append(M.text("unit", "911", 0.42, (loc.x + s * 0.03, -6.9, 2.5), (math.pi / 2, 0, s * math.pi / 2), M.matte("#101114", 0.5)))
        top, _ = surf.point("T", 0, -0.9)
        z = top.z
        G["Trim"].append(C.box("barbase", (4.4, 0.9, 0.16), (0, -0.9, z + 0.12), M.DARK(), bev=0.05))
        for s, col in ((-1, "#e01616"), (1, "#1b4fe0")):
            G["Lights"].append(C.box("beacon", (1.9, 0.78, 0.36), (s * 1.12, -0.9, z + 0.36), M.mat("Beacon", col, rough=0.15, emit=1.2), bev=0.12, segs=3))
            G["Trim"].append(C.box("foot", (0.16, 0.5, 0.2), (s * 1.9, -0.9, z + 0.06), M.DARK(), bev=0.03))
        G["Lights"].append(C.box("beaconmid", (0.3, 0.7, 0.3), (0, -0.9, z + 0.33), M.mat("BeaconW", "#f5f5f5", rough=0.2, emit=0.4), bev=0.08))
        # push bar
        y = p["L"] / 2 + 0.28
        for s in (-1, 1):
            G["Trim"].append(C.tube("pushup", [(s * 1.0, y - 0.35, 0.95), (s * 1.0, y, 1.1), (s * 1.0, y, 2.9), (s * 1.0, y - 0.3, 3.0)], 0.09, M.DARK(), segs=10, smooth=5))
        for zz in (1.5, 2.2, 2.85):
            G["Trim"].append(C.tube("pushx", [(-1.9, y - 0.12, zz), (-1.0, y, zz), (1.0, y, zz), (1.9, y - 0.12, zz)], 0.075, M.DARK(), segs=10))
        loc, _ = surf.point("L", 2.85, 3.35)
        G["Trim"].append(C.cyl("spot", 0.2, 0.3, (loc.x - 0.3, 2.9, 3.4), M.CHROME(), "Y", segs=16))
        G["Trim"].append(M.text("roofnum", "27", 1.3, (0, -2.1, z + 0.02), (0, 0, 0), M.matte("#101114", 0.5)))
    return C.build_car(p, spec("PoliceCar")["wheels"], extras)


@builder("MuscleCar")
def muscle():
    p = car_dims("MuscleCar", L=17.6, W=7.4, color="#b3161a", clear=0.7, belt=3.05, roof=4.5, hood_front=2.8, hood_cowl=3.12,
                 cowl=2.0, ws_top=0.2, roof_rear=-2.6, deck=-6.2, trunk=3.22, b_pillar=-1.1, arch=1.14, roof_w=0.72, nose_w=0.92,
                 tail_w=0.94, wheel_style="alloy5", rim_color="#d8dbe0", doors=[1.6, -1.6], seat_rows=[-0.3, -2.4],
                 headlight=(0.62, 0.9, 2.05, 2.5), grille=(0.58, 1.75, 2.55), grille_bars=5, exhausts=(-2.4, 2.4), flare=0.035,
                 taillight=(0.2, 0.95, 2.55, 2.95))

    def extras(p, surf, paint, G):
        white = M.paint("#f1f1f1")
        for x in (-0.95, 0.35):
            for y0, y1 in ((2.2, 8.4), (-2.5, 0.1), (-8.6, -6.3)):
                G["Body"].append(surf.project("stripe", "T", (x, y0, x + 0.6, y1), white, 0.008, res=0.15))
        scoop = C.loft("scoop", [[(-1.0, 6.2, 3.0), (1.0, 6.2, 3.0), (0.9, 6.2, 3.38), (-0.9, 6.2, 3.38)],
                                 [(-1.1, 4.2, 3.1), (1.1, 4.2, 3.1), (0.95, 4.2, 3.5), (-0.95, 4.2, 3.5)],
                                 [(-0.9, 2.6, 3.12), (0.9, 2.6, 3.12), (0.7, 2.6, 3.2), (-0.7, 2.6, 3.2)]], paint, smooth=False)
        M.bevel(scoop, 0.05, 2)
        G["Body"].append(scoop)
        G["Trim"].append(C.box("scoopmouth", (1.7, 0.05, 0.26), (0, 6.22, 3.2), M.DARK(), bev=0.01))
        lip = C.wing("ducktail", p["W"] * 0.82, 0.9, 0.12, paint)
        M.place(lip, (0, -8.25, 3.42), rot=(math.radians(-22), 0, 0))
        G["Body"].append(lip)
        for s in (-1, 1):
            G["Trim"].append(C.tube("sidepipe", [(s * 3.5, 2.4, 0.62), (s * 3.62, 0, 0.6), (s * 3.62, -3.0, 0.6)], 0.12, M.CHROME(), segs=10))
    return C.build_car(p, spec("MuscleCar")["wheels"], extras)


def pickup_body(key, color, wheels, lift=0.0, style="offroad"):
    s = spec(key)
    p = car_dims("PickupTruck", L=18.6, W=7.6, color=color, clear=1.25, belt=4.15, roof=6.25, hood_front=3.8, hood_cowl=4.2,
                 cowl=4.9, ws_top=3.3, roof_rear=0.7, deck=0.35, trunk=4.3, b_pillar=2.0, arch=1.13, roof_w=0.8, nose_w=0.94, tail_w=0.97,
                 wheel_style=style, rim_color="#c9ccd1", doors=[4.4, 0.75], seat_rows=[2.3], quarter_glass=False, crown=0.05, flare=0.03,
                 headlight=(0.58, 0.92, 2.95, 3.5), grille=(0.52, 2.2, 3.55), grille_bars=4, exhausts=(2.6,), taillight=(0.86, 0.97, 2.9, 3.9),
                 plate_front=True, antenna=False)

    def extras(p, surf, paint, G):
        body = G["Body"][0]
        C.recess(body, -3.25, 3.25, -8.75, -0.25, 3.9, 2.55)   # the load bed
        for o in body.data.polygons:
            o.use_smooth = True
        G["Trim"].append(C.box("bedliner", (6.4, 8.4, 0.06), (0, -4.5, 2.6), M.matte("#1b1c1e", 0.9), bev=0.01))
        for y in (-8.0, -6.2, -4.4, -2.6, -0.8):
            G["Trim"].append(C.box("bedrib", (6.2, 0.18, 0.06), (0, y, 2.66), M.matte("#232427", 0.9), bev=0.02))
        for yb, zc in ((p["L"] / 2 + 0.12, 1.75), (-p["L"] / 2 - 0.12, 1.85)):   # chrome bumpers
            b = C.box("bumper", (7.5, 0.5, 0.75), (0, yb, zc), M.CHROME(), bev=0.16, segs=3)
            G["Trim"].append(b)
        G["Trim"].append(surf.project("tailgate", "B", (-3.3, 2.65, 3.3, 2.7), M.DARK(), 0.006, res=0.15))
        G["Trim"].append(C.box("tghandle", (0.9, 0.06, 0.2), (0, -p["L"] / 2 - 0.03, 3.85), M.DARK(), bev=0.03))
        G["Trim"].append(C.cyl("hitch", 0.16, 0.5, (0, -p["L"] / 2 - 0.45, 1.5), M.STEEL(), "Y", segs=12))
        for sgn in (-1, 1):
            G["Trim"].append(C.tube("step", [(sgn * 3.75, 4.3, 1.35), (sgn * 3.95, 3.9, 1.2), (sgn * 3.95, 1.2, 1.2), (sgn * 3.75, 0.8, 1.35)], 0.11, M.CHROME(), segs=10, smooth=4))
            G["Trim"].append(C.box("flap", (1.2, 0.06, 1.0), (sgn * 3.1, p["axle_r"] - p["wheel_r"] * 1.25, 1.5), M.RUBBER(), bev=0.01))
    G = C.build_car(p, wheels, extras)
    return p, G


@builder("PickupTruck")
def pickup():
    return pickup_body("PickupTruck", "#2f7d3c", spec("PickupTruck")["wheels"])[1]


@builder("MonsterTruck")
def monster():
    s = spec("MonsterTruck")
    fake = [dict(pos=[sx * 3.15, 1.7, z], radius=1.7, width=1.3) for z in (-5.58, 5.58) for sx in (-1, 1)]
    p, G = pickup_body("MonsterTruck", "#7a22d6", [], style="offroad")
    for ob in G["Wheels"]:
        bpy.data.objects.remove(ob)
    G["Wheels"] = []
    # flames
    LIFT = 3.9
    C.lift(G, LIFT)
    steel, blue = M.mat("Frame", "#2a2c31", rough=0.4, metal=0.8), M.mat("Shock", "#1e62d0", rough=0.3, metal=0.6)
    ws = s["wheels"]
    for i, w in enumerate(ws):
        x, y, z = w["pos"][0], -w["pos"][2], w["pos"][1]
        ob = M.wheel("Wheel%d" % (i + 1), w["radius"], w["width"], "monster", 1 if x > 0 else -1, "#d0d3d8", rim_frac=0.5)
        M.place(ob, (x, y, z))
        M.set_origin(ob, (x, y, z))
        G["Wheels"].append(ob)
    ys = sorted({-w["pos"][2] for w in ws})
    zr = ws[0]["radius"]
    for y in ys:
        G["Trim"].append(C.cyl("axle", 0.42, 9.2, (0, y, zr), steel, "X", segs=20))
        G["Trim"].append(C.lathe("diff", [(0, -0.9), (0.5, -0.9), (0.95, -0.4), (0.95, 0.4), (0.5, 0.9), (0, 0.9)], steel, segs=24, axis="X", loc=(0, y, zr)))
        for sx in (-1, 1):
            top = (sx * 2.2, y * 0.62, LIFT + 1.6)
            bot = (sx * 3.2, y, zr + 0.3)
            G["Trim"].append(C.tube("shock", [bot, top], 0.16, blue, segs=12))
            a, b_ = Vector(bot), Vector(top)
            ax = (b_ - a).normalized()
            u = ax.cross(Vector((0, 1, 0))).normalized()
            v = ax.cross(u)
            n = 9 * 14
            helix = [a.lerp(b_, 0.12 + 0.76 * k / n) + (u * math.cos(M.TAU * k / 14) + v * math.sin(M.TAU * k / 14)) * 0.36 for k in range(n + 1)]
            G["Trim"].append(C.tube("spring", helix, 0.07, M.mat("Spring", "#e2342b", rough=0.35, metal=0.5), segs=6))
            for zz in (0.45, -0.25):   # four-link bars
                G["Trim"].append(C.tube("link", [(sx * 2.6, y, zr + zz), (sx * 1.6, y * 0.12, LIFT + 0.9 + zz * 0.5)], 0.13, steel, segs=10))
    for sx in (-1, 1):  # ladder frame + roll cage
        G["Trim"].append(C.tube("rail", [(sx * 1.7, ys[0] * 0.95, LIFT + 0.9), (sx * 1.7, ys[1] * 0.95, LIFT + 0.9)], 0.22, steel, segs=10))
        G["Trim"].append(C.tube("cage", [(sx * 3.0, -1.0, LIFT + 4.3), (sx * 3.0, -1.2, LIFT + 6.7), (sx * 3.0, -8.2, LIFT + 6.7), (sx * 3.0, -8.6, LIFT + 4.3)], 0.14, steel, segs=10, smooth=5))
    for y in (-1.2, -8.2):
        G["Trim"].append(C.tube("cagex", [(-3.0, y, LIFT + 6.7), (3.0, y, LIFT + 6.7)], 0.14, steel, segs=10))
    for y in (ys[0] * 0.6, 0, ys[1] * 0.6):
        G["Trim"].append(C.tube("cross", [(-1.7, y, LIFT + 0.9), (1.7, y, LIFT + 0.9)], 0.18, steel, segs=10))
    for sx in (-1, 1):
        G["Lights"].append(C.box("rooflight", (0.7, 0.3, 0.5), (sx * 1.2, 2.9, LIFT + 6.55), M.HEADLIGHT(), bev=0.1))
    G["Lights"].append(C.box("rooflight", (0.7, 0.3, 0.5), (0, 2.9, LIFT + 6.55), M.HEADLIGHT(), bev=0.1))
    return G


# ------------------------------------------------------------------ assembly / export
def bake_colors(ob):
    me = ob.data
    if "Col" in me.color_attributes:
        me.color_attributes.remove(me.color_attributes["Col"])
    layer = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    cols = []
    for slot in me.materials:
        c = slot.diffuse_color if slot else (0.5, 0.5, 0.5, 1)
        cols.append((c[0] ** (1 / 2.2), c[1] ** (1 / 2.2), c[2] ** (1 / 2.2), 1.0))
    if not cols:
        cols = [(0.5, 0.5, 0.5, 1)]
    for poly in me.polygons:
        col = cols[min(poly.material_index, len(cols) - 1)]
        for li in poly.loop_indices:
            layer.data[li].color_srgb = col
    try:
        me.color_attributes.active_color = layer
        me.color_attributes.render_color_index = me.color_attributes.find("Col")
    except Exception:
        pass


def assemble(key, G):
    s = spec(key)
    made = []
    for g in ("Body", "Glass", "Lights", "Trim"):
        objs = [o for o in G.get(g, []) if o is not None]
        # Roblox MeshParts are capped at 20k triangles: pack the pieces into bins below that
        bins, cur, n = [], [], 0
        for o in sorted(objs, key=M.tris, reverse=True):
            t = M.tris(o)
            if cur and n + t > 18500:
                bins.append(cur)
                cur, n = [], 0
            cur.append(o)
            n += t
        if cur:
            bins.append(cur)
        for bi, group in enumerate(bins):
            ob = M.join(group, "%s_%s%s" % (key, g, "" if bi == 0 else str(bi + 1)))
            M.set_origin(ob, (0, 0, 0))
            made.append(ob)
    if G.get("Turret"):
        ob = M.join(G["Turret"], key + "_Turret")
        tp = s["turretPivot"]
        M.set_origin(ob, (tp[0], -tp[2], tp[1]))
        made.append(ob)
    for i, ob in enumerate(G.get("Spin", [])):
        ob.name = "%s_Spin%d" % (key, i + 1)
        pv = s["spinners"][i]["pivot"]
        M.set_origin(ob, (pv[0], -pv[2], pv[1]))
        made.append(ob)
    for i, ob in enumerate(G.get("Wheels", [])):
        ob.name = "%s_Wheel%d" % (key, i + 1)
        made.append(ob)
    for ob in made:
        ob.data.name = ob.name
        bake_colors(ob)
        ob["rcp_vehicle"] = key
    return made


def bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    return Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)])


def render(key, objs, suffix="", view=(-0.78, 1.0, 0.36)):
    sc = bpy.context.scene
    lo, hi = bounds(objs)
    c = (lo + hi) / 2
    size = max((hi - lo).length, 6)
    bpy.ops.mesh.primitive_plane_add(size=900, location=(0, 0, 0))
    g = bpy.context.active_object
    g.data.materials.append(M.mat("Ground", "#6a6d72", rough=0.85))
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    cam.data.lens = 70
    d = Vector(view).normalized()
    cam.location = c + d * size * 2.05
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    nt = w.node_tree
    sky = nt.nodes.new("ShaderNodeTexSky")
    try:
        sky.sun_elevation, sky.sun_rotation = math.radians(38), math.radians(-40)
    except Exception:
        pass
    nt.links.new(sky.outputs[0], nt.nodes["Background"].inputs[0])
    nt.nodes["Background"].inputs[1].default_value = 0.09
    sc.world = w
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy, sun.data.angle = 2.2, math.radians(3)
    sun.rotation_euler = (math.radians(52), 0, math.radians(130))
    sc.collection.objects.link(sun)
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 48
    try:
        sc.cycles.use_denoising = True
    except Exception:
        pass
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x, sc.render.resolution_y = 960, 600
    sc.render.filepath = os.path.join(OUT, "previews", key + suffix + ".png")
    try:
        bpy.ops.render.render(write_still=True)
    except RuntimeError:
        sc.cycles.use_denoising = False
        bpy.ops.render.render(write_still=True)
    for o in (g, cam, sun):
        bpy.data.objects.remove(o)


def export(key, objs):
    M.select(objs)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, key + ".blend"))
    M.select(objs)
    try:
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, key + ".glb"), use_selection=True, export_yup=True, export_vertex_color="ACTIVE", export_all_vertex_colors=False)
    except TypeError:
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, key + ".glb"), use_selection=True, export_yup=True)
    M.select(objs)
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, key + ".fbx"), use_selection=True, apply_unit_scale=True,
                             apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE",
                             bake_anim=False, colors_type="SRGB")


def main():
    import importlib
    for mod in ("rcp_trucks", "rcp_military", "rcp_aircraft", "rcp_special"):
        if os.path.exists(os.path.join(HERE, mod + ".py")):
            importlib.import_module(mod).register(builder, spec, car_dims)
    keys = [a for a in sys.argv[1:] if a in BUILDERS] or [k for k in SPEC["order"] if k in BUILDERS]
    stats_path = os.path.join(OUT, "build_stats.json")
    stats = json.load(open(stats_path)) if os.path.exists(stats_path) else {}
    for key in keys:
        M.reset()
        objs = assemble(key, BUILDERS[key]())
        lo, hi = bounds(objs)
        stats[key] = dict(objects={o.name: M.tris(o) for o in objs}, tris=sum(M.tris(o) for o in objs), size=[round(v, 2) for v in (hi - lo)])
        over = [o.name for o in objs if M.tris(o) > 20000]
        export(key, objs)
        if RENDER:
            render(key, objs)
            if "--rear" in sys.argv:
                render(key, objs, "_rear", (0.8, -1.0, 0.4))
            if "--side" in sys.argv:
                render(key, objs, "_side", (-1.0, 0.12, 0.12))
        print("BUILT", key, stats[key]["tris"], "tris", stats[key]["size"], "OVER 20k: %s" % over if over else "", flush=True)
    json.dump(stats, open(stats_path, "w"), indent=1)


if __name__ == "__main__":
    main()
