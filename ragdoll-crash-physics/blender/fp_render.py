"""First-person check renders: what the driver sees from the cockpit eye point.

    python3 fp_render.py [Vehicle ...] [--out DIR] [--samples N]

Reads blender/vehicles.json (cockpit.eye, Roblox axes) and out/<Vehicle>.blend, puts a camera at
the eye with Roblox's default 70 degree vertical field of view, looking straight ahead and slightly
down, fades the glass the way the game does in first person, hides back faces as Roblox does, and
renders out/previews/fp/<Vehicle>.png.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
SPEC = json.load(open(os.path.join(HERE, "vehicles.json")))
V = SPEC["vehicles"]
FP_GLASS_ALPHA = 0.12      # in first person the game makes glass ~88% clear
AMBIENT = 0.3              # stands in for Roblox's Lighting.Ambient on every surface


def rbx(v):
    """Roblox (x, y up, -z front) -> Blender (x, y front, z up)."""
    return Vector((v[0], -v[2], v[1]))


def setup_world(sc):
    w = bpy.data.worlds.new("FPWorld")
    w.use_nodes = True
    nt = w.node_tree
    sky = nt.nodes.new("ShaderNodeTexSky")
    try:
        sky.sun_elevation, sky.sun_rotation = math.radians(40), math.radians(-30)
    except Exception:
        pass
    bg = nt.nodes["Background"]
    nt.links.new(sky.outputs[0], bg.inputs[0])
    bg.inputs[1].default_value = 0.05
    # Roblox lights interiors with an ambient term (Ambient / OutdoorAmbient); a path tracer only gets
    # light bounced in through the windows. Bounce rays see a soft grey ambient, camera rays the sky.
    amb = nt.nodes.new("ShaderNodeBackground")
    amb.inputs[0].default_value = (0.62, 0.64, 0.68, 1)
    amb.inputs[1].default_value = 0.55
    lp = nt.nodes.new("ShaderNodeLightPath")
    mix = nt.nodes.new("ShaderNodeMixShader")
    out = nt.nodes["World Output"]
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
    nt.links.new(amb.outputs[0], mix.inputs[1])
    nt.links.new(bg.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    sc.world = w
    sun = bpy.data.objects.new("FPSun", bpy.data.lights.new("FPSun", "SUN"))
    sun.data.energy, sun.data.angle = 2.2, math.radians(3)
    sun.rotation_euler = (math.radians(50), 0, math.radians(150))
    sc.collection.objects.link(sun)
    bpy.ops.mesh.primitive_plane_add(size=2000, location=(0, 0, 0))
    g = bpy.context.active_object
    m = bpy.data.materials.new("FPGround")
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0.32, 0.33, 0.34, 1)
    b.inputs["Roughness"].default_value = 0.9
    g.data.materials.append(m)
    # road markings ahead so the view has something to read distance against
    for k in range(12):
        bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 14 + k * 12, 0.02))
        s = bpy.context.active_object
        s.scale = (0.35, 4.0, 1)
        mm = bpy.data.materials.new("FPLine")
        mm.use_nodes = True
        mm.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.9, 0.85, 0.6, 1)
        s.data.materials.append(mm)


def fade_glass():
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        name = m.name.lower()
        if "glass" in name or "canopy" in name:
            b = m.node_tree.nodes.get("Principled BSDF")
            if b and "Alpha" in b.inputs:
                b.inputs["Alpha"].default_value = FP_GLASS_ALPHA
                try:
                    m.surface_render_method = "BLENDED"
                except Exception:
                    pass


def cull_backfaces():
    """Roblox draws a mesh from the front only; make back faces invisible so the preview matches."""
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        nt = m.node_tree
        out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
        if not out or not out.inputs["Surface"].links:
            continue
        src = out.inputs["Surface"].links[0].from_socket
        # Roblox's Ambient term lights every surface directly, even deep inside a cab; a path tracer
        # only gets light bounced in through the windows, which leaves dark cabins black
        bsdf = nt.nodes.get("Principled BSDF")
        if bsdf is not None:
            amb = nt.nodes.new("ShaderNodeEmission")
            amb.inputs["Strength"].default_value = AMBIENT
            col = bsdf.inputs["Base Color"]
            if col.links:
                nt.links.new(col.links[0].from_socket, amb.inputs["Color"])
            else:
                amb.inputs["Color"].default_value = col.default_value
            both = nt.nodes.new("ShaderNodeAddShader")
            nt.links.new(src, both.inputs[0])
            nt.links.new(amb.outputs[0], both.inputs[1])
            src = both.outputs[0]
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        clear = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(geo.outputs["Backfacing"], mix.inputs[0])
        nt.links.new(src, mix.inputs[1])
        nt.links.new(clear.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])


def render(key, out_dir, samples):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT, key + ".blend"))
    sc = bpy.context.scene
    cp = V[key].get("cockpit")
    if not cp:
        print("no cockpit for", key)
        return
    fade_glass()
    cull_backfaces()
    setup_world(sc)
    cam = bpy.data.objects.new("FPCam", bpy.data.cameras.new("FPCam"))
    sc.collection.objects.link(cam)
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle_y = math.radians(70)
    cam.data.clip_start = 0.05
    cam.location = rbx(cp["eye"])
    pitch = cp.get("pitch", -8)
    yaw = cp.get("yaw", 0)
    cam.rotation_euler = Euler((math.radians(90 + pitch), 0, math.radians(yaw)), "XYZ")
    sc.camera = cam
    sc.render.engine = "CYCLES"
    sc.cycles.samples = samples
    try:
        sc.cycles.use_denoising = True
    except Exception:
        pass
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x, sc.render.resolution_y = 960, 540
    os.makedirs(out_dir, exist_ok=True)
    sc.render.filepath = os.path.join(out_dir, key + ".png")
    try:
        bpy.ops.render.render(write_still=True)
    except RuntimeError:
        sc.cycles.use_denoising = False
        bpy.ops.render.render(write_still=True)
    print("FP", key, flush=True)


def main():
    args = sys.argv[1:]
    out_dir = os.path.join(OUT, "previews", "fp")
    samples = 24
    if "--out" in args:
        out_dir = args[args.index("--out") + 1]
    if "--samples" in args:
        samples = int(args[args.index("--samples") + 1])
    keys = [a for a in args if a in V] or SPEC["order"]
    for k in keys:
        render(k, out_dir, samples)


if __name__ == "__main__":
    main()
