"""Builds every vehicle from vehicles.json as real Blender meshes.

Run:  python3 build_vehicles.py            (uses the `bpy` pip module, Blender 4.x/5.x)
 or:  blender -b -P build_vehicles.py

Output (blender/out/):
  <Vehicle>.blend / .fbx / .glb   one file per vehicle, 1 Blender unit = 1 stud
  previews/<Vehicle>.png          Cycles render used for the in-game menu thumbnails
  all_vehicles.blend              every vehicle laid out in one scene

Each vehicle is exported as separate named objects so Roblox can treat them as
separate MeshParts:
  <Vehicle>_Body      every painted panel, bevelled and joined
  <Vehicle>_Glass     windows
  <Vehicle>_Lights    head / brake lights and neon
  <Vehicle>_Trim      dark + metal trim
  <Vehicle>_Wheel1..N one object per wheel, origin on the axle
  <Vehicle>_Spin1..N  propellers / rotors, origin on the spin axis
  <Vehicle>_Turret    (tank) origin on the turret ring
Axis mapping: Roblox (x, y, z) -> Blender (x, -z, y). Vehicle front is Blender +Y,
which the FBX/glTF exporters turn back into -Z (Roblox forward).
"""
import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
os.makedirs(os.path.join(OUT, "previews"), exist_ok=True)
SPEC = json.load(open(os.path.join(HERE, "vehicles.json")))
ONLY = [a for a in sys.argv[1:] if a in SPEC["vehicles"]]
RENDER = "--no-render" not in sys.argv


def R2B(p):
    return Vector((p[0], -p[2], p[1]))


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple((int(h[i:i + 2], 16) / 255) ** 2.2 for i in (0, 2, 4)) + (1,)


_mats = {}
TAPER = False


def material(color, mat):
    key = (color, mat)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("%s_%s" % (mat, color.lstrip("#")))
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = hex_rgb(color)
    rough, metal = dict(body=(0.35, 0.0), glass=(0.08, 0.0), light=(0.3, 0.0), dark=(0.6, 0.0),
                        metal=(0.35, 0.9), rubber=(0.9, 0.0), neon=(0.4, 0.0))[mat]
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if mat in ("light", "neon"):
        b.inputs["Emission Color"].default_value = hex_rgb(color)
        b.inputs["Emission Strength"].default_value = 2.5 if mat == "neon" else 1.2
    if mat == "glass":
        b.inputs["Alpha"].default_value = 0.55
        m.diffuse_color = hex_rgb(color)[:3] + (0.55,)
    m.diffuse_color = hex_rgb(color)[:3] + (m.diffuse_color[3],)
    _mats[key] = m
    return m


def new_obj(name, bm, mat):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(mat)
    return ob


def prim(p):
    """Create one primitive from the spec, in Blender space."""
    sx, sy, sz = p["size"]          # Roblox size (x, y, z)
    bm = bmesh.new()
    shape = p["shape"]
    if shape == "box":
        bmesh.ops.create_cube(bm, size=1)
        bmesh.ops.scale(bm, vec=(sx, sz, sy), verts=bm.verts)
        if TAPER and p["name"] == "Cabin":      # raked windscreens (Blender-only polish)
            for v in bm.verts:
                if v.co.z > 0:
                    v.co.x *= 0.9
                    v.co.y *= 0.74
        elif TAPER and p["name"] == "Roof":
            for v in bm.verts:
                v.co.x *= 0.9
                v.co.y *= 0.74
        bev = min(0.18, min(sx, sy, sz) * 0.22)
        if bev > 0.02:
            bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bev, segments=2, profile=0.6, affect="EDGES")
    elif shape == "wedge":
        # Roblox WedgePart: full height on the +Z face, zero on -Z. face=back flips it.
        zs = 1 if p["face"] == "front" else -1
        hx, hy, hz = sx / 2, sy / 2, sz / 2
        # roblox coords -> blender (x, -z, y)
        pts = [(-hx, -hy, -hz * zs), (hx, -hy, -hz * zs), (-hx, -hy, hz * zs), (hx, -hy, hz * zs),
               (-hx, hy, hz * zs), (hx, hy, hz * zs)]
        vs = [bm.verts.new((x, -z, y)) for x, y, z in pts]
        for f in ((0, 1, 3, 2), (2, 3, 5, 4), (0, 4, 5, 1), (0, 2, 4), (1, 5, 3)):
            bm.faces.new([vs[i] for i in f])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bev = min(0.1, min(sx, sy, sz) * 0.15)
        if bev > 0.02:
            bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bev, segments=2, affect="EDGES")
    elif shape == "cyl":
        ax = p["axis"]
        # Roblox size is the bounding box; pick length along the axis and diameters across it
        length = dict(x=sx, y=sy, z=sz)[ax]
        d = [v for k, v in (("x", sx), ("y", sy), ("z", sz)) if k != ax]
        bmesh.ops.create_cone(bm, cap_ends=True, segments=28, radius1=0.5, radius2=0.5, depth=1)
        # cone is along Blender Z. scale then rotate to the right axis.
        bmesh.ops.scale(bm, vec=(d[0], d[1], length), verts=bm.verts)
        bev = min(0.12, length * 0.2, min(d) * 0.12)
        cap_edges = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6]
        if bev > 0.02:
            bmesh.ops.bevel(bm, geom=cap_edges, offset=bev, segments=2, affect="EDGES")
        if ax == "x":      # blender X
            bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=__import__("mathutils").Matrix.Rotation(math.pi / 2, 3, "Y"))
        elif ax == "z":    # roblox Z -> blender Y
            bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=__import__("mathutils").Matrix.Rotation(math.pi / 2, 3, "X"))
    bmesh.ops.translate(bm, vec=R2B(p["pos"]), verts=bm.verts)
    return new_obj(p["name"], bm, material(p["color"], p["mat"]))


def wheel(i, w):
    """Detailed wheel: tyre with rounded shoulders, rim, hub and 5 spokes."""
    r, wd = w["radius"], w["width"]
    objs = []
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=32, radius1=r, radius2=r, depth=wd)
    cap = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6]
    bmesh.ops.bevel(bm, geom=cap, offset=min(wd * 0.3, r * 0.25), segments=3, affect="EDGES")
    objs.append(new_obj("tyre", bm, material("#17181b", "rubber")))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=r * 0.58, radius2=r * 0.58, depth=wd * 1.04)
    objs.append(new_obj("rim", bm, material("#c9cdd3", "metal")))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=r * 0.2, radius2=r * 0.16, depth=wd * 1.12)
    objs.append(new_obj("hub", bm, material("#30333a", "metal")))
    for k in range(5):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1)
        bmesh.ops.scale(bm, vec=(r * 0.5, r * 0.13, wd * 1.08), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(r * 0.33, 0, 0), verts=bm.verts)
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                         matrix=__import__("mathutils").Matrix.Rotation(k * math.tau / 5, 3, "Z"))
        objs.append(new_obj("spoke", bm, material("#30333a", "metal")))
    ob = join(objs, "Wheel%d" % i)
    ob.rotation_euler = (0, math.pi / 2, 0)      # axle along X
    ob.location = R2B(w["pos"])
    select([ob])
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return ob


def select(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def join(objs, name):
    select(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def set_origin(ob, world):
    bpy.context.scene.cursor.location = world
    select([ob])
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")


def smooth(ob):
    for poly in ob.data.polygons:
        poly.use_smooth = True
    try:
        mod = ob.modifiers.new("wn", "WEIGHTED_NORMAL")
        mod.keep_sharp = True
    except Exception:
        pass


def build(key, offset=Vector((0, 0, 0))):
    global TAPER
    spec = SPEC["vehicles"][key]
    TAPER = bool(spec.get("carStyle"))
    spin_names, turret_names = {}, set(spec.get("turret", []))
    for si, sp in enumerate(spec.get("spinners", [])):
        for n in sp["parts"]:
            spin_names[n] = si
    groups = {"Body": [], "Glass": [], "Lights": [], "Trim": [], "Turret": []}
    spins = {}
    for p in spec["parts"]:
        if TAPER and p["name"].startswith("Pillar"):
            continue
        ob = prim(p)
        if p["name"] in spin_names:
            spins.setdefault(spin_names[p["name"]], []).append(ob)
        elif p["name"] in turret_names:
            groups["Turret"].append(ob)
        else:
            groups[dict(body="Body", glass="Glass", light="Lights", neon="Lights").get(p["mat"], "Trim")].append(ob)
    made = []
    for g, objs in groups.items():
        if objs:
            ob = join(objs, "%s_%s" % (key, g))
            if g == "Turret":
                set_origin(ob, R2B(spec["turretPivot"]))
            else:
                set_origin(ob, Vector((0, 0, 0)))
            made.append(ob)
    for si, objs in spins.items():
        ob = join(objs, "%s_Spin%d" % (key, si + 1))
        set_origin(ob, R2B(spec["spinners"][si]["pivot"]))
        made.append(ob)
    for i, w in enumerate(spec["wheels"]):
        ob = wheel(i + 1, w)
        ob.name = "%s_Wheel%d" % (key, i + 1)
        set_origin(ob, R2B(w["pos"]))
        made.append(ob)
    for ob in made:
        smooth(ob)
        ob["rcp_vehicle"] = key
        ob.location += offset
    return made


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()


def bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    return lo, hi


def render(key, objs):
    sc = bpy.context.scene
    lo, hi = bounds(objs)
    c = (lo + hi) / 2
    size = max((hi - lo).length, 6)
    bpy.ops.mesh.primitive_plane_add(size=600, location=(0, 0, 0))
    g = bpy.context.active_object
    g.data.materials.append(material("#7fc66a", "dark"))
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    cam.data.lens = 55
    d = Vector((-0.72, 1.0, 0.42)).normalized()      # look from front-left, front is +Y
    cam.location = c + d * size * 1.75
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4
    sun.data.angle = 0.15
    sun.rotation_euler = (math.radians(50), 0, math.radians(140))
    sc.collection.objects.link(sun)
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.38, 0.62, 1.0, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.1
    sc.world = w
    sc.view_settings.view_transform = "Standard"
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 24
    sc.cycles.use_denoising = False
    sc.render.resolution_x, sc.render.resolution_y = 640, 400
    sc.render.filepath = os.path.join(OUT, "previews", key + ".png")
    bpy.ops.render.render(write_still=True)
    for o in (g, cam, sun):
        bpy.data.objects.remove(o)


def export(key, objs):
    select(objs)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, key + ".blend"))
    select(objs)
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, key + ".fbx"), use_selection=True,
                             apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS",
                             axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE", bake_anim=False)
    select(objs)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, key + ".glb"), use_selection=True, export_yup=True)


def main():
    keys = ONLY or SPEC["order"]
    stats = {}
    for key in keys:
        reset()
        objs = build(key)
        lo, hi = bounds(objs)
        stats[key] = dict(objects=len(objs), tris=sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons),
                          size=[round(v, 2) for v in (hi - lo)])
        export(key, objs)
        if RENDER:
            render(key, objs)
        print("BUILT", key, stats[key], flush=True)
    if not ONLY:
        reset()
        x = 0
        for key in keys:
            sz = stats[key]["size"]
            build(key, Vector((x + sz[0] / 2, 0, 0)))
            x += sz[0] + 8
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "all_vehicles.blend"))
    json.dump(stats, open(os.path.join(OUT, "build_stats.json"), "w"), indent=1)


main()
