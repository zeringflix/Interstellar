"""Perspective render of the built map (tests/out/map.json from tests/map_spec.luau) in Blender, to
check the look without Studio. python3 tools/render_map3d.py [out.png] [camX camY camZ lookX lookY lookZ]"""
import json, math, os, sys
import bpy
from mathutils import Vector
here = os.path.dirname(os.path.abspath(__file__))
d = json.load(open(os.path.join(here, "..", "tests", "out", "map.json")))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "..", "docs", "map_view.png")
cam_args = [float(v) for v in sys.argv[2:8]] if len(sys.argv) >= 8 else [60, 140, 150, -40, 0, -120]
bpy.ops.wm.read_factory_settings(use_empty=True)
mats = {}
def mat(hexc, neon=False, glass=False):
    k = (hexc, neon, glass)
    if k in mats: return mats[k]
    m = bpy.data.materials.new(hexc); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    rgb = tuple((int(hexc[i:i+2], 16) / 255) ** 2.2 for i in (0, 2, 4))
    b.inputs["Base Color"].default_value = rgb + (1,)
    b.inputs["Roughness"].default_value = 0.7
    if neon:
        b.inputs["Emission Color"].default_value = rgb + (1,); b.inputs["Emission Strength"].default_value = 3
    mats[k] = m; return m
import bmesh
bm_all = {}
for p in d["parts"]:
    if p["transparency"] >= 1 or p["name"] in ("Baseplate",): continue
    sx, sy, sz = p["size"]; x, y, z = p["pos"]
    bm = bmesh.new()
    if p["ball"]:
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=0.5)
        bmesh.ops.scale(bm, vec=(sx, sz, sy), verts=bm.verts)
    elif p["class"] == "WedgePart":
        hx, hy, hz = sx/2, sy/2, sz/2
        pts = [(-hx,-hy,hz),(hx,-hy,hz),(-hx,-hy,-hz),(hx,-hy,-hz),(-hx,hy,hz),(hx,hy,hz)]  # tall face at +Z (Roblox local back)
        vs = [bm.verts.new((a, -c, b)) for a, b, c in pts]
        for f in ((0,1,3,2),(0,4,5,1),(4,2,3,5),(0,2,4),(1,5,3)):
            bm.faces.new([vs[i] for i in f])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    else:
        bmesh.ops.create_cube(bm, size=1); bmesh.ops.scale(bm, vec=(sx, sz, sy), verts=bm.verts)
    from mathutils import Matrix
    rot = Matrix.Rotation(p["yaw"], 4, "Z") if p["class"] != "WedgePart" else Matrix.Rotation(p.get("yawFull", p["yaw"]), 4, "Z")
    bmesh.ops.transform(bm, matrix=Matrix.Translation((x, -z, y)) @ rot, verts=bm.verts)
    key = (p["color"], p["name"] in ("LampHead", "CrossLight", "SignalLamp", "BufferLamp") )
    tgt = bm_all.setdefault(key, bmesh.new())
    me = bpy.data.meshes.new("t"); bm.to_mesh(me); bm.free()
    tgt.from_mesh(me); bpy.data.meshes.remove(me)
for (col, neon), bm in bm_all.items():
    me = bpy.data.meshes.new(col); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(col, me); bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat(col, neon))
bpy.ops.mesh.primitive_plane_add(size=4000, location=(0, 0, -0.05))
bpy.context.active_object.data.materials.append(mat("9a9486"))
sc = bpy.context.scene
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")); sc.collection.objects.link(cam)
cam.data.lens = 24; cam.data.clip_end = 5000
cx, cy, cz, lx, ly, lz = cam_args
cam.location = (cx, -cz, cy)
cam.rotation_euler = (Vector((lx, -lz, ly)) - cam.location).to_track_quat("-Z", "Y").to_euler()
sc.camera = cam
w = bpy.data.worlds.new("W"); w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.45, 0.65, 1.0, 1); w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
sc.world = w
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN")); sun.data.energy = 3.2; sun.data.angle = math.radians(2)
sun.rotation_euler = (math.radians(45), 0, math.radians(35)); sc.collection.objects.link(sun)
sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in sc.render.bl_rna.properties["engine"].enum_items] else "CYCLES"
if sc.render.engine == "CYCLES": sc.cycles.samples = 24
sc.view_settings.view_transform = "Standard"
sc.render.resolution_x, sc.render.resolution_y = 1280, 720
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("wrote", out)
