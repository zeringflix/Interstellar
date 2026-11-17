"""Bakes real PBR texture sets onto every finished vehicle (out/<Vehicle>.blend).

    python3 texture_vehicles.py [Vehicle ...] [--res 1024] [--no-render]

All textures are original and generated here: procedural paint with orange peel and clear-coat
variation, edge wear down to primer / bare metal, crevice grime (baked ambient occlusion), road dirt
that builds up low on the body, dust on upward faces, brushed and scratched metal, tyre rubber with
sidewall grain, grained plastic, upholstery weave, aircraft panel lines, military camouflage, soot.
Each vehicle has its own wear profile (a showroom sports car stays clean, the bulldozer is caked).

Per object (Body, Trim, Turret, Wheels, Spinners; Glass and Lights keep their plain materials):
  1. UV unwrap (smart project + pack)
  2. bake a mask pass  R = crevice (AO), G = convex edges (bevel normal), B = cavity (AO, tight)
  3. bake Color (sRGB), Roughness, Metalness (linear) and a tangent-space Normal map from the
     procedural shaders, which read the mask instead of ray tracing again
  4. replace the object's materials with ONE material using those images
Output: out/textures/<Vehicle>/<Object>_{Color,Roughness,Metalness,Normal}.png, the textured
out/<Vehicle>.blend / .glb (JPEG-compressed images embedded) and out/AllVehicles.glb.
Roblox's Import 3D turns each textured object into a MeshPart with a SurfaceAppearance.
"""
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy

OUT = os.path.join(HERE, "out")
SPEC = json.load(open(os.path.join(HERE, "vehicles.json")))
ARGS = sys.argv[1:]
RES = int(ARGS[ARGS.index("--res") + 1]) if "--res" in ARGS else 1024
RENDER = "--no-render" not in ARGS
ONLY = [a for a in ARGS if a in SPEC["vehicles"]]

# wear profile per vehicle: dirt amount, edge wear, dust, dirt colour, extras
WEAR = {
    "Sedan": dict(dirt=0.30, edge=0.15, dust=0.20),
    "SportsCar": dict(dirt=0.12, edge=0.05, dust=0.08),
    "PoliceCar": dict(dirt=0.25, edge=0.15, dust=0.15),
    "MuscleCar": dict(dirt=0.22, edge=0.18, dust=0.12),
    "PickupTruck": dict(dirt=0.55, edge=0.35, dust=0.40, mud="#5b4632"),
    "MonsterTruck": dict(dirt=0.75, edge=0.45, dust=0.35, mud="#4e3b28"),
    "CityBus": dict(dirt=0.35, edge=0.20, dust=0.25),
    "DumpTruck": dict(dirt=0.85, edge=0.60, dust=0.55, mud="#5a4530", rust=0.35),
    "Tank": dict(dirt=0.80, edge=0.50, dust=0.50, mud="#5d4b33", camo=("#4a5a38", "#2f3a24", "#6b5b3e")),
    "ArmoredTruck": dict(dirt=0.70, edge=0.45, dust=0.50, mud="#5d4b33", camo=("#6f7a63", "#4a5240", "#8a8164")),
    "SmallPlane": dict(dirt=0.15, edge=0.10, dust=0.10, panels=2.4),
    "CargoPlane": dict(dirt=0.30, edge=0.20, dust=0.15, panels=3.2),
    "Helicopter": dict(dirt=0.25, edge=0.15, dust=0.15, panels=1.8),
    "Train": dict(dirt=0.60, edge=0.35, dust=0.20, mud="#1c1a18", soot=0.6),
    "Bulldozer": dict(dirt=0.90, edge=0.65, dust=0.60, mud="#5a4530", rust=0.25),
    "GoKart": dict(dirt=0.30, edge=0.25, dust=0.20),
    "RocketSled": dict(dirt=0.35, edge=0.20, dust=0.10, mud="#1c1a18", soot=0.5),
}
SKIP = ("_Glass", "_Lights")


def srgb_to_lin(h):
    h = h.lstrip("#")
    return tuple((int(h[i:i + 2], 16) / 255) ** 2.2 for i in (0, 2, 4)) + (1.0,)


# ------------------------------------------------------------------------------- node helpers
class G:
    """Tiny node-graph builder for one material."""

    def __init__(self, mat):
        self.nt = mat.node_tree
        self.n = self.nt.nodes
        self.l = self.nt.links
        self.x = 0

    def node(self, kind, **inputs):
        nd = self.n.new(kind)
        nd.location = (self.x, 0)
        self.x += 40
        for k, v in inputs.items():
            if k.startswith("_"):
                setattr(nd, k[1:], v)
            elif hasattr(v, "bl_idname") or (isinstance(v, tuple) and len(v) == 2 and hasattr(v[0], "bl_idname")):
                self.link(v, nd.inputs[k])
            else:
                nd.inputs[k].default_value = v
        return nd

    def link(self, src, dst):
        if isinstance(src, tuple):
            src = src[0].outputs[src[1]]
        elif hasattr(src, "outputs"):
            src = src.outputs[0]
        self.l.new(src, dst)

    def math(self, op, a, b=0.0, clamp=False):
        nd = self.n.new("ShaderNodeMath")
        nd.operation = op
        nd.use_clamp = clamp
        for i, v in enumerate((a, b)):
            if isinstance(v, (int, float)):
                nd.inputs[i].default_value = v
            else:
                self.link(v, nd.inputs[i])
        return nd

    def mix(self, a, b, fac, blend="MIX"):
        nd = self.n.new("ShaderNodeMix")
        nd.data_type = "RGBA"
        nd.blend_type = blend
        nd.clamp_factor = True
        for sock, v in ((nd.inputs[0], fac), (nd.inputs[6], a), (nd.inputs[7], b)):
            if isinstance(v, (int, float)):
                sock.default_value = v
            elif isinstance(v, tuple) and len(v) == 4:
                sock.default_value = v
            else:
                self.link(v, sock)
        return (nd, 2)

    def mixf(self, a, b, fac):
        nd = self.n.new("ShaderNodeMix")
        nd.data_type = "FLOAT"
        nd.clamp_factor = True
        for sock, v in ((nd.inputs[0], fac), (nd.inputs[2], a), (nd.inputs[3], b)):
            if isinstance(v, (int, float)):
                sock.default_value = v
            else:
                self.link(v, sock)
        return (nd, 0)

    def ramp(self, src, stops, interp="LINEAR"):
        nd = self.n.new("ShaderNodeValToRGB")
        nd.color_ramp.interpolation = interp
        el = nd.color_ramp.elements
        while len(el) > 1:
            el.remove(el[-1])
        el[0].position, el[0].color = stops[0][0], stops[0][1]
        for p, c in stops[1:]:
            e = el.new(p)
            e.color = c
        self.link(src, nd.inputs[0])
        return nd

    def noise(self, vec, scale, detail=4.0, rough=0.55, distortion=0.0, dims="3D"):
        nd = self.n.new("ShaderNodeTexNoise")
        nd.noise_dimensions = dims
        nd.inputs["Scale"].default_value = scale
        nd.inputs["Detail"].default_value = detail
        nd.inputs["Roughness"].default_value = rough
        nd.inputs["Distortion"].default_value = distortion
        self.link(vec, nd.inputs["Vector"])
        return nd

    def smooth(self, src, lo, hi):
        """smoothstep(lo, hi, src) via a map range node."""
        nd = self.n.new("ShaderNodeMapRange")
        nd.interpolation_type = "SMOOTHSTEP"
        nd.inputs["From Min"].default_value = lo
        nd.inputs["From Max"].default_value = hi
        self.link(src, nd.inputs["Value"])
        return nd


def default_material():
    m = bpy.data.materials.get("RCP_Default")
    if not m:
        m = bpy.data.materials.new("RCP_Default")
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, 0.05, 0.055, 1)
        m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.6
    return m


def classify(mat):
    """paint | metal | rubber | plastic | fabric | glass | emissive, from the original material."""
    mat = mat or default_material()
    name = mat.name.split(".")[0]
    b = mat.node_tree.nodes.get("Principled BSDF") if mat.use_nodes else None
    metal = b.inputs["Metallic"].default_value if b else 0
    rough = b.inputs["Roughness"].default_value if b else 0.5
    alpha = b.inputs["Alpha"].default_value if b else 1
    emit = b.inputs["Emission Strength"].default_value if b else 0
    coat = b.inputs["Coat Weight"].default_value if b and "Coat Weight" in b.inputs else 0
    col = tuple(b.inputs["Base Color"].default_value) if b else (0.5, 0.5, 0.5, 1)
    if alpha < 0.95:
        kind = "glass"
    elif emit > 0.5:
        kind = "emissive"
    elif name in ("Seat", "Interior", "BusSeat", "Canvas") or name.startswith("Seat"):
        kind = "fabric"
    elif name in ("Rubber", "TrackPad", "Tyre") or (rough > 0.84 and max(col[:3]) < 0.02):
        kind = "rubber"
    elif metal > 0.5:
        kind = "metal"
    elif coat > 0.5 or name in ("Paint", "Olive", "OliveDark", "Armour", "ArmourDark", "LocoBlack", "LocoRed", "DozerBlack", "KartFrame"):
        kind = "paint"
    else:
        kind = "plastic"
    return kind, col, metal, rough


def build_material(src, img_mask, wear, obj_height, vehicle, look=None):
    look = look or {}
    """Returns a new material: procedural graph whose outputs are routed for each bake pass."""
    kind, col, metal0, rough0 = classify(src)
    src = src or default_material()
    m = bpy.data.materials.new(src.name + "_bake")
    m.use_nodes = True
    g = G(m)
    for nd in list(g.n):
        g.n.remove(nd)
    out = g.node("ShaderNodeOutputMaterial")
    geo = g.node("ShaderNodeNewGeometry")
    tex = g.node("ShaderNodeTexCoord")
    pos = (geo, "Position")
    # ---- mask pass graph (ray traced: AO + bevel)
    ao = g.node("ShaderNodeAmbientOcclusion", Distance=0.9, _samples=12, _only_local=True)
    ao_t = g.node("ShaderNodeAmbientOcclusion", Distance=0.12, _samples=12, _only_local=True)
    bev = g.node("ShaderNodeBevel", Radius=0.06, _samples=8)
    dotn = g.node("ShaderNodeVectorMath", _operation="DOT_PRODUCT")
    g.link((bev, "Normal"), dotn.inputs[0])
    g.link((geo, "Normal"), dotn.inputs[1])
    edge = g.math("SUBTRACT", 1.0, (dotn, "Value"))
    edge = g.math("MULTIPLY", edge, 9.0, clamp=True)
    crev = g.math("SUBTRACT", 1.0, (ao, "AO"))
    cav = g.math("SUBTRACT", 1.0, (ao_t, "AO"))
    comb = g.node("ShaderNodeCombineColor")
    g.link(crev, comb.inputs[0])
    g.link(edge, comb.inputs[1])
    g.link(cav, comb.inputs[2])
    mask_emit = g.node("ShaderNodeEmission", Color=comb)
    # ---- texture pass graph (reads the baked mask)
    mimg = g.node("ShaderNodeTexImage", _image=img_mask, _interpolation="Linear")
    g.link((tex, "UV"), mimg.inputs["Vector"])
    sep = g.node("ShaderNodeSeparateColor", Color=(mimg, "Color"))
    m_crev, m_edge, m_cav = (sep, 0), (sep, 1), (sep, 2)
    sepz = g.node("ShaderNodeSeparateXYZ", Vector=pos)
    zpos = (sepz, "Z")
    nz = g.node("ShaderNodeSeparateXYZ", Vector=(geo, "Normal"))
    up = g.smooth((nz, "Z"), 0.45, 0.95)

    # breakup noises
    big = g.noise(pos, 0.35, 6, 0.6, 0.4)
    mid = g.noise(pos, 2.2, 8, 0.65)
    fine = g.noise(pos, 28, 4, 0.5)
    # low-on-the-body road dirt: strongest near the ground, rising with noise
    hfrac = g.math("DIVIDE", zpos, max(obj_height, 0.5))
    low = g.smooth(zpos, 2.6, 0.3)  # road spray: absolute height in studs, same for every part
    low_n = g.math("MULTIPLY", low, g.smooth((big, "Fac"), 0.3, 0.65), clamp=True)
    dirt = g.math("MAXIMUM", g.math("MULTIPLY", m_crev, 1.4), low_n)
    dirt = g.math("MULTIPLY", dirt, g.smooth((mid, "Fac"), 0.25, 0.6))
    dirt = g.math("MULTIPLY", dirt, wear["dirt"] * 1.6, clamp=True)
    dust = g.math("MULTIPLY", up, g.math("MULTIPLY", g.smooth((big, "Fac"), 0.5, 0.72), wear["dust"] * 0.6), clamp=True)
    wear_e = g.math("MULTIPLY", m_edge, g.smooth((mid, "Fac"), 0.42, 0.56))
    wear_e = g.math("MULTIPLY", wear_e, wear["edge"] * 2.2, clamp=True)
    # long thin scratches: anisotropic noise
    sc_map = g.node("ShaderNodeMapping", Vector=pos, Scale=(1.0, 26.0, 1.0))
    sc = g.noise(sc_map, 6.0, 2, 0.4)
    scratch = g.smooth((sc, "Fac"), 0.72, 0.75)
    scratch = g.math("MULTIPLY", scratch, g.smooth((big, "Fac"), 0.5, 0.75))
    scratch = g.math("MULTIPLY", scratch, min(1.0, wear["edge"] * 2), clamp=True)

    mud = srgb_to_lin(wear.get("mud", "#6b5a45"))
    dustc = srgb_to_lin("#9a8f7b")
    base = tuple(col)
    # the vehicle's main body colour can be swapped by a look (variant)
    is_main = kind == "paint" and look.get("main") is not None and max(abs(base[i] - look["main"][i]) for i in range(3)) < 0.03
    if is_main and look.get("paint"):
        base = srgb_to_lin(look["paint"])
    color = None
    rough = None
    metal = None
    bump_h = None
    bump_s = 0.0
    if kind == "paint":
        c = (g.node("ShaderNodeRGB"), 0)
        c[0].outputs[0].default_value = base
        camo = look.get("camo", wear.get("camo"))
        if camo and (src.name.split(".")[0] in ("Olive", "Armour", "OliveDark", "ArmourDark") or (is_main and look.get("camo_on_main"))):
            cam = g.noise(pos, look.get("camo_scale", 0.11), 2, 0.5, 1.2)
            camr = g.ramp((cam, "Fac"), [(0.0, srgb_to_lin(camo[0])), (0.47, srgb_to_lin(camo[1])),
                                         (0.6, srgb_to_lin(camo[2]))], "CONSTANT")
            c = (camr, 0)
        if is_main and look.get("stripes"):
            hw, H = look["hw"], look["H"]
            sx = g.node("ShaderNodeSeparateXYZ", Vector=pos)
            ax = g.math("ABSOLUTE", (sx, "X"))
            band = g.math("MULTIPLY", g.smooth(ax, hw * 0.10, hw * 0.12), g.smooth(ax, hw * 0.38, hw * 0.36))
            top = g.smooth((nz, "Z"), 0.35, 0.6)
            nxa = g.math("ABSOLUTE", (nz, "X"))
            side = g.smooth(nxa, 0.55, 0.8)
            zb = g.math("MULTIPLY", g.smooth(zpos, H * 0.40, H * 0.41), g.smooth(zpos, H * 0.50, H * 0.49))
            smask = g.math("MAXIMUM", g.math("MULTIPLY", top, band), g.math("MULTIPLY", side, zb))
            c = g.mix(c, srgb_to_lin(look["stripes"]), smask)
        # subtle tone variation (sun fade / respray patches)
        c = g.mix(c, (0.0, 0.0, 0.0, 1.0), g.math("MULTIPLY", g.smooth((big, "Fac"), 0.35, 0.75), 0.06))
        if look.get("fade"):  # sun-bleached, chalky paint
            c = g.mix(c, (0.5, 0.49, 0.47, 1.0), g.math("MULTIPLY", g.smooth((big, "Fac"), 0.2, 0.8), look["fade"]))
        if wear.get("panels"):
            sy = g.node("ShaderNodeSeparateXYZ", Vector=pos)
            fr = g.math("FRACT", g.math("DIVIDE", (sy, "Y"), wear["panels"]))
            line = g.math("MULTIPLY", g.smooth(fr, 0.985, 0.995), 1.0)
            line = g.math("MAXIMUM", line, g.smooth(fr, 0.01, 0.002))
            c = g.mix(c, srgb_to_lin("#55595f"), g.math("MULTIPLY", line, 0.5))
            bump_h = g.math("SUBTRACT", 0.0, line)
            bump_s = 0.25
        if wear.get("rust"):
            rust = g.math("MULTIPLY", g.smooth((g.noise(pos, 1.4, 8, 0.7), "Fac"), 0.58, 0.7), wear["rust"] * 2.0, clamp=True)
            rust = g.math("MAXIMUM", rust, g.math("MULTIPLY", m_crev, wear["rust"]))
            c = g.mix(c, srgb_to_lin("#7a3e1d"), rust)
        primer = srgb_to_lin("#7c7d80")
        bare = srgb_to_lin("#a9adb3")
        c = g.mix(c, primer, wear_e)
        c = g.mix(c, bare, g.math("MULTIPLY", wear_e, g.smooth((fine, "Fac"), 0.5, 0.6)))
        c = g.mix(c, srgb_to_lin("#b9b9b6"), g.math("MULTIPLY", scratch, 0.35))
        color = c
        rough = g.math("ADD", look.get("gloss", 0.22), g.math("MULTIPLY", (fine, "Fac"), 0.12))
        metal = g.math("MULTIPLY", wear_e, g.smooth((fine, "Fac"), 0.5, 0.6))
        peel = g.noise(pos, 140, 2, 0.5)
        bump_h = g.math("ADD", g.math("MULTIPLY", (peel, "Fac"), 0.25), bump_h if bump_h else 0.0)
        bump_h = g.math("SUBTRACT", bump_h, g.math("MULTIPLY", scratch, 0.6))
        bump_s = max(bump_s, 0.06)
    elif kind == "metal":
        c = (g.node("ShaderNodeRGB"), 0)
        c[0].outputs[0].default_value = base
        brush_map = g.node("ShaderNodeMapping", Vector=pos, Scale=(1.0, 1.0, 60.0))
        brush = g.noise(brush_map, 18, 3, 0.5)
        c = g.mix(c, (0.0, 0.0, 0.0, 1.0), g.math("MULTIPLY", (brush, "Fac"), 0.12))
        c = g.mix(c, srgb_to_lin("#3a3633"), g.math("MULTIPLY", m_cav, 0.6))
        color = c
        rough = g.math("ADD", max(0.06, rough0 - 0.05), g.math("MULTIPLY", (brush, "Fac"), 0.18))
        rough = g.math("ADD", rough, g.math("MULTIPLY", scratch, 0.2))
        metal = g.math("SUBTRACT", 1.0, g.math("MULTIPLY", dirt, 0.7))
        bump_h = g.math("ADD", g.math("MULTIPLY", (brush, "Fac"), 0.4), g.math("MULTIPLY", scratch, -0.5))
        bump_s = 0.04
    elif kind == "rubber":
        c = (g.node("ShaderNodeRGB"), 0)
        c[0].outputs[0].default_value = srgb_to_lin("#1b1b1d")
        grain = g.noise(pos, 90, 3, 0.6)
        c = g.mix(c, srgb_to_lin("#2c2b2a"), g.math("MULTIPLY", (mid, "Fac"), 0.5))
        c = g.mix(c, srgb_to_lin("#4a4744"), g.math("MULTIPLY", m_edge, 0.35))  # scuffed shoulders
        color = c
        rough = g.math("ADD", 0.82, g.math("MULTIPLY", (grain, "Fac"), 0.12))
        metal = 0.0
        bump_h = (grain, "Fac")
        bump_s = 0.18
    elif kind == "fabric":
        c = (g.node("ShaderNodeRGB"), 0)
        c[0].outputs[0].default_value = base
        weave = g.node("ShaderNodeTexWave", Scale=180.0, Distortion=0.0, Detail=0.0, Vector=pos)
        weave2 = g.node("ShaderNodeTexWave", Scale=180.0, Distortion=0.0, Detail=0.0, Vector=pos, _bands_direction="Y")
        w = g.math("MULTIPLY", (weave, "Fac"), (weave2, "Fac"))
        c = g.mix(c, (0.0, 0.0, 0.0, 1.0), g.math("MULTIPLY", w, 0.2))
        color = c
        rough = 0.9
        metal = 0.0
        bump_h = w
        bump_s = 0.12
    else:  # plastic / matte / emissive-in-trim / glass-in-trim
        c = (g.node("ShaderNodeRGB"), 0)
        c[0].outputs[0].default_value = base
        vor = g.node("ShaderNodeTexVoronoi", Scale=260.0, Vector=pos)
        c = g.mix(c, (0.0, 0.0, 0.0, 1.0), g.math("MULTIPLY", (mid, "Fac"), 0.08))
        c = g.mix(c, srgb_to_lin("#d8d8d4"), g.math("MULTIPLY", wear_e, 0.35))  # stress-whitened edges
        color = c
        rough = g.math("ADD", max(0.35, rough0 - 0.1), g.math("MULTIPLY", (vor, "Distance"), 0.2))
        metal = metal0 if kind != "emissive" else 0.0
        bump_h = (vor, "Distance")
        bump_s = 0.05

    # shared grime layers (not on glass / emissive faces)
    if kind not in ("glass", "emissive"):
        color = g.mix(color, mud, dirt)
        color = g.mix(color, dustc, dust)
        if wear.get("soot"):
            soot = g.math("MULTIPLY", g.math("MAXIMUM", m_crev, g.smooth(hfrac, 0.55, 1.0)), wear["soot"], clamp=True)
            color = g.mix(color, srgb_to_lin("#151413"), g.math("MULTIPLY", soot, g.smooth((mid, "Fac"), 0.3, 0.6)))
        rough = g.mixf(rough, 0.95, g.math("MAXIMUM", dirt, dust)) if not isinstance(rough, float) else g.mixf(rough, 0.95, dirt)
        if isinstance(metal, (int, float)):
            mv = g.node("ShaderNodeValue")
            mv.outputs[0].default_value = metal
            metal = (mv, 0)
        metal = g.math("MULTIPLY", metal, g.math("SUBTRACT", 1.0, dirt), clamp=True)
        bump_h = g.math("ADD", bump_h if bump_h is not None else 0.0, g.math("MULTIPLY", dirt, 0.6))
        bump_s = max(bump_s, 0.08)
    if isinstance(rough, (int, float)):
        rv = g.node("ShaderNodeValue")
        rv.outputs[0].default_value = rough
        rough = (rv, 0)
    if isinstance(metal, (int, float)):
        mv = g.node("ShaderNodeValue")
        mv.outputs[0].default_value = metal
        metal = (mv, 0)
    bump = g.node("ShaderNodeBump", Strength=min(1.0, bump_s * 4), Distance=0.02)
    g.link(bump_h, bump.inputs["Height"])
    bsdf = g.node("ShaderNodeBsdfPrincipled")
    g.link(color, bsdf.inputs["Base Color"])
    g.link(rough, bsdf.inputs["Roughness"])
    g.link(metal, bsdf.inputs["Metallic"])
    g.link((bump, "Normal"), bsdf.inputs["Normal"])
    e_col = g.node("ShaderNodeEmission", Color=color)
    e_rough = g.node("ShaderNodeEmission", Color=rough)
    e_metal = g.node("ShaderNodeEmission", Color=metal)
    target = g.node("ShaderNodeTexImage")  # active node = bake target
    m["rcp_nodes"] = True
    m.node_tree.nodes.active = target
    route = {"MASK": mask_emit, "COLOR": e_col, "ROUGH": e_rough, "METAL": e_metal, "NORMAL": bsdf}
    return m, out, route, target


# ------------------------------------------------------------------------------- per object
def select_only(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def unwrap(ob):
    select_only(ob)
    me = ob.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    me.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    try:
        bpy.ops.uv.pack_islands(rotate=True, margin=0.004)
    except Exception:
        pass
    bpy.ops.object.mode_set(mode="OBJECT")


def new_image(name, res, non_color, fill=(0.5, 0.5, 0.5, 1.0)):
    img = bpy.data.images.new(name, res, res, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    img.generated_color = fill
    return img


def final_material(ob, imgs, has_metal):
    m = bpy.data.materials.new(ob.name + "_PBR")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    def img_node(img, y):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        n.location = (-500, y)
        return n
    c = img_node(imgs["COLOR"], 300)
    nt.links.new(c.outputs["Color"], b.inputs["Base Color"])
    r = img_node(imgs["ROUGH"], 0)
    nt.links.new(r.outputs["Color"], b.inputs["Roughness"])
    if has_metal:
        mt = img_node(imgs["METAL"], -300)
        nt.links.new(mt.outputs["Color"], b.inputs["Metallic"])
    else:
        b.inputs["Metallic"].default_value = 0.0
    n = img_node(imgs["NORMAL"], -600)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.location = (-200, -600)
    nt.links.new(n.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    ob.data.materials.clear()
    ob.data.materials.append(m)
    for p in ob.data.polygons:
        p.material_index = 0
    # the colour map now carries the colours: drop the baked vertex colours so they cannot tint it twice
    me = ob.data
    for attr in list(me.color_attributes):
        me.color_attributes.remove(attr)


def resolution_for(ob):
    name = ob.name
    dims = ob.dimensions
    size = max(dims)
    if "_Wheel" in name or "_Spin" in name:
        return 512 if size > 2 else 256
    if size < 4:
        return RES // 2
    return RES



# ------------------------------------------------------------------------------- the five looks
# Per vehicle: the colour that "Two-Tone Livery" repaints the body with, and its stripe colour.
LIVERY = {
    "Sedan": ("#b3161a", "#f2f2f2"), "SportsCar": ("#16181c", "#f6c40f"), "PoliceCar": ("#1f3a7a", "#f2f2f2"),
    "MuscleCar": ("#1f4fd8", "#f2f2f2"), "PickupTruck": ("#c3c0b8", "#2f7d3c"), "MonsterTruck": ("#ff7a00", "#16181c"),
    "CityBus": ("#c8102e", "#f2f2f2"), "DumpTruck": ("#f2c21a", "#16181c"), "Tank": ("#dfe2e3", "#9aa0a6"),
    "ArmoredTruck": ("#585e66", "#9aa0a6"), "SmallPlane": ("#1d4fa8", "#f2f2f2"), "CargoPlane": ("#4b5446", "#d9d9d0"),
    "Helicopter": ("#16181c", "#f6c40f"), "Train": ("#1f6b3a", "#c9a13b"), "Bulldozer": ("#ff8a1f", "#16181c"),
    "GoKart": ("#1d6fe0", "#f2f2f2"), "RocketSled": ("#f2c21a", "#16181c"),
}
CAMO = {"Tank", "ArmoredTruck"}


def looks(vehicle, wear):
    """The five options offered for every vehicle: (number, name, wear profile, look)."""
    base = dict(wear)
    alt, stripe = LIVERY.get(vehicle, ("#b3161a", "#f2f2f2"))
    clean = dict(base, dirt=0.03, edge=0.0, dust=0.0)
    clean.pop("rust", None)
    clean["soot"] = min(base.get("soot", 0), 0.15) if base.get("soot") else 0
    battered = dict(base, dirt=min(1.0, base["dirt"] * 1.4 + 0.35), edge=min(1.0, base["edge"] + 0.5), dust=min(1.0, base["dust"] + 0.3),
                    rust=max(base.get("rust", 0), 0.45), mud=base.get("mud", "#4e3d2b"))
    livery = dict(base, dirt=0.12, edge=0.08, dust=0.06)
    livery.pop("rust", None)
    rally = dict(base, dirt=0.55, edge=0.25, dust=0.5, mud="#86714f")
    rally.pop("rust", None)
    out = [
        (1, "Factory Clean", clean, dict(gloss=0.10)),
        (2, "Daily Use", base, dict()),
        (3, "Battered", battered, dict(fade=0.35, gloss=0.5)),
    ]
    if vehicle in CAMO:
        out.append((4, "Arctic Camo", livery, dict(camo=("#e6e8e8", "#a9b0b5", "#5e666d"), camo_on_main=True, camo_scale=0.09)))
        out.append((5, "Desert Camo", rally, dict(camo=("#cdb78c", "#a88c60", "#6f5c40"), camo_on_main=True, camo_scale=0.12, gloss=0.6)))
    else:
        out.append((4, "Two-Tone Livery", livery, dict(paint=alt, stripes=stripe, gloss=0.14)))
        out.append((5, "Matte Rally", rally, dict(paint="#2b2e33", stripes="#ff6a00", gloss=0.6)))
    return out


# ------------------------------------------------------------------------------- stages
def texturable(sc, vehicle):
    return [o for o in sc.objects if o.type == "MESH" and o.name.startswith(vehicle + "_") and not any(k in o.name for k in SKIP)]


def main_color(objs):
    """The body colour covering the most area: the colour a look may repaint."""
    area = {}
    for ob in objs:
        names = list(ob["rcp_orig"]) if "rcp_orig" in ob else [sl.material.name if sl.material else "" for sl in ob.material_slots]
        for poly in ob.data.polygons:
            mat = bpy.data.materials.get(names[poly.material_index]) if poly.material_index < len(names) else None
            if not mat:
                continue
            kind, col, _, _ = classify(mat)
            if kind == "paint":
                key = tuple(round(c, 3) for c in col[:3])
                area[key] = area.get(key, 0) + poly.area
    return (max(area, key=area.get) + (1.0,)) if area else None


def vehicle_frame(objs):
    import mathutils
    pts = [ob.matrix_world @ mathutils.Vector(c) for ob in objs for c in ob.bound_box]
    return max(abs(p.x) for p in pts), max(p.z for p in pts)


def prepare(vehicle):
    """UV-unwrap every texturable mesh and bake its mask (AO + edges): shared by all five looks."""
    import shutil
    clean = os.path.join(OUT, "untextured", vehicle + ".blend")
    if not os.path.exists(clean):
        os.makedirs(os.path.dirname(clean), exist_ok=True)
        shutil.copy2(os.path.join(OUT, vehicle + ".blend"), clean)
    prepared = os.path.join(OUT, "prepared", vehicle + ".blend")
    if os.path.exists(prepared) and "--reprepare" not in ARGS:
        bpy.ops.wm.open_mainfile(filepath=prepared)
        return
    bpy.ops.wm.open_mainfile(filepath=clean)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    for o in [o for o in sc.objects if o.type == "MESH" and not o.name.startswith(vehicle + "_")]:
        bpy.data.objects.remove(o)   # strays left behind by the modelling scripts
    folder = os.path.join(OUT, "textures", vehicle)
    os.makedirs(folder, exist_ok=True)
    wear = WEAR.get(vehicle, dict(dirt=0.3, edge=0.2, dust=0.2))
    for ob in texturable(sc, vehicle):
        unwrap(ob)
        res = resolution_for(ob)
        mask = new_image(ob.name + "_Mask", res, True, (0, 0, 0, 1))
        originals = [slot.material for slot in ob.material_slots]
        graphs = []
        for slot in ob.material_slots:
            if slot.material is None:
                slot.material = default_material()
            originals[len(graphs)] = slot.material
            src = slot.material
            m, out, route, target = build_material(src, mask, wear, 1.0, vehicle)
            slot.material = m
            graphs.append((m, out, route, target))
        run_pass(ob, graphs, "MASK", mask, 12, "EMIT")
        mask.filepath_raw = os.path.join(folder, ob.name + "_Mask.png")
        mask.file_format = "PNG"
        mask.save()
        for slot, orig in zip(ob.material_slots, originals):
            junk = slot.material
            slot.material = orig
            bpy.data.materials.remove(junk)
        ob["rcp_res"] = res
        print("  prepared", ob.name, res, flush=True)
    os.makedirs(os.path.dirname(prepared), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=prepared)


def run_pass(ob, graphs, pass_name, image, samples, bake_type):
    sc = bpy.context.scene
    select_only(ob)
    for m, out, route, target in graphs:
        target.image = image
        m.node_tree.nodes.active = target
        m.node_tree.links.new(route[pass_name].outputs[0], out.inputs["Surface"])
    sc.cycles.samples = samples
    kw = dict(type=bake_type, margin=6, use_clear=True)
    if bake_type == "NORMAL":
        kw.update(normal_space="TANGENT")
    bpy.ops.object.bake(**kw)


def mask_image(ob, vehicle):
    p = os.path.join(OUT, "textures", vehicle, ob.name + "_Mask.png")
    img = bpy.data.images.load(p, check_existing=True)
    img.colorspace_settings.name = "Non-Color"
    return img


def apply_look(vehicle, objs, wear, look, route_name="NORMAL"):
    """Swap every texturable mesh to the procedural graph of one look. Returns per-object graphs."""
    hw, H = vehicle_frame(objs)
    for ob in objs:
        if "rcp_orig" not in ob:
            ob["rcp_orig"] = [slot.material.name if slot.material else "" for slot in ob.material_slots]
    look = dict(look, main=main_color(objs), hw=hw, H=H)
    all_graphs = {}
    for ob in objs:
        mask = mask_image(ob, vehicle)
        graphs = []
        for slot, orig_name in zip(ob.material_slots, ob["rcp_orig"]):
            src = bpy.data.materials.get(orig_name) or default_material()
            m, out, route, target = build_material(src, mask, wear, 1.0, vehicle, look)
            m.node_tree.links.new(route[route_name].outputs[0], out.inputs["Surface"])
            old = slot.material
            slot.material = m
            if old and old.get("rcp_nodes"):
                bpy.data.materials.remove(old)
            graphs.append((m, out, route, target))
        all_graphs[ob.name] = graphs
    return all_graphs


def preview(vehicle):
    """Render the five looks with the live procedural shaders (no baking needed to choose)."""
    prepare(vehicle)
    sc = bpy.context.scene
    objs = texturable(sc, vehicle)
    every = [o for o in sc.objects if o.type == "MESH" and o.name.startswith(vehicle + "_")]
    wear = WEAR.get(vehicle, dict(dirt=0.3, edge=0.2, dust=0.2))
    folder = os.path.join(OUT, "previews", "looks")
    os.makedirs(folder, exist_ok=True)
    for n, name, w, look in looks(vehicle, wear):
        apply_look(vehicle, objs, w, look)
        render_preview(every, os.path.join(folder, "%s_%d.png" % (vehicle, n)))
        print("  look", vehicle, n, name, flush=True)


def render_preview(objs, path):
    import importlib
    importlib.import_module("rcp_model")._mats.clear()
    br = importlib.import_module("build_realistic")
    name = os.path.splitext(os.path.basename(path))[0]
    br.render(name, objs)  # writes <out>/previews/<name>.png
    os.replace(os.path.join(br.OUT, "previews", name + ".png"), path)


def apply(vehicle, n):
    """Bake the chosen look into texture maps, export the textured model and render it."""
    prepare(vehicle)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    objs = texturable(sc, vehicle)
    every = [o for o in sc.objects if o.type == "MESH" and o.name.startswith(vehicle + "_")]
    wear = WEAR.get(vehicle, dict(dirt=0.3, edge=0.2, dust=0.2))
    pick = [l for l in looks(vehicle, wear) if l[0] == n][0]
    graphs = apply_look(vehicle, objs, pick[2], pick[3])
    folder = os.path.join(OUT, "textures", vehicle)
    import numpy as np
    for ob in objs:
        res = int(ob.get("rcp_res", resolution_for(ob)))
        imgs = {
            "COLOR": new_image(ob.name + "_Color", res, False),
            "ROUGH": new_image(ob.name + "_Roughness", res, True),
            "METAL": new_image(ob.name + "_Metalness", res, True, (0, 0, 0, 1)),
            "NORMAL": new_image(ob.name + "_Normal", res, True, (0.5, 0.5, 1.0, 1.0)),
        }
        g = graphs[ob.name]
        run_pass(ob, g, "COLOR", imgs["COLOR"], 1, "EMIT")
        run_pass(ob, g, "ROUGH", imgs["ROUGH"], 1, "EMIT")
        run_pass(ob, g, "METAL", imgs["METAL"], 1, "EMIT")
        run_pass(ob, g, "NORMAL", imgs["NORMAL"], 1, "NORMAL")
        for key, img in imgs.items():
            label = {"COLOR": "Color", "ROUGH": "Roughness", "METAL": "Metalness", "NORMAL": "Normal"}[key]
            img.filepath_raw = os.path.join(folder, "%s_%s.png" % (ob.name, label))
            img.file_format = "PNG"
            img.save()
        arr = np.empty(res * res * 4, dtype=np.float32)
        imgs["METAL"].pixels.foreach_get(arr)
        final_material(ob, imgs, float(arr[0::4].max()) > 0.08)
        print("  baked", ob.name, res, flush=True)
    for img in bpy.data.images:
        if img.filepath_raw:
            img.filepath = bpy.path.relpath(img.filepath_raw, start=OUT)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, vehicle + ".blend"), relative_remap=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in every:
        o.select_set(True)
    bpy.context.view_layer.objects.active = every[0]
    glb = os.path.join(OUT, vehicle + ".glb")
    try:
        bpy.ops.export_scene.gltf(filepath=glb, use_selection=True, export_yup=True, export_image_format="JPEG", export_image_quality=88)
    except TypeError:
        bpy.ops.export_scene.gltf(filepath=glb, use_selection=True, export_yup=True, export_image_format="JPEG", export_jpeg_quality=88)
    import importlib
    importlib.import_module("rcp_model")._mats.clear()
    importlib.import_module("build_realistic").render(vehicle, every)
    print("APPLIED", vehicle, n, pick[1], flush=True)


def main():
    """python3 texture_vehicles.py preview [Vehicle ...]
    python3 texture_vehicles.py apply Sedan=3 Tank=5 ...   (or  apply all=2)"""
    if "apply" in ARGS:
        picks = {}
        for a in ARGS:
            if "=" in a:
                k, v = a.split("=")
                for key in (SPEC["order"] if k == "all" else [k]):
                    picks[key] = int(v)
        for k in SPEC["order"]:
            if k in picks:
                apply(k, picks[k])
        return
    for k in ONLY or SPEC["order"]:
        t0 = time.time()
        preview(k)
        print("PREVIEWED", k, "%.0fs" % (time.time() - t0), flush=True)


if __name__ == "__main__":
    main()
