"""Road vehicles: lofted + subdivided monocoque bodies with real glasshouses, cut wheel arches,
interiors, and surface-projected lamps / grilles / shut-lines. Used for the sedan, sports car,
police car, muscle car, pickup, monster truck and (with other numbers) the heavy trucks."""
import math

import bpy
from mathutils import Vector

import rcp_model as M
from rcp_model import box, cyl, lathe, loft, tube, mat, section


def stations(p):
    """Turn a handful of named dimensions into the list of body cross-sections (rear -> front).
    Returns (rings, flags) where flags[i] describes the segment between ring i and i+1."""
    L, hw = p["L"], p["W"] / 2
    c, belt, roof = p["clear"], p["belt"], p["roof"]
    hf, hc = p["hood_front"], p["hood_cowl"]
    yc, ywt, yrr, ydk = p["cowl"], p["ws_top"], p["roof_rear"], p["deck"]
    tz = p["trunk"]
    yb = p.get("b_pillar", (ywt + yrr) / 2)
    nose, tail = L / 2, -L / 2
    rw_ = p.get("roof_w", 0.74)     # roof half-width as a fraction of body half-width (tumblehome)
    nw, tw = p.get("nose_w", 0.86), p.get("tail_w", 0.9)
    crown = p.get("crown", 0.07)
    fl = p.get("flare", 0.025)
    yaf, yar = p["axle_f"], p["axle_r"]
    S = []

    fender = p["wheel_r"] * (p.get("arch_z", 0.95) + p.get("arch", 1.2)) + 0.14   # arches must stay below the wing tops

    def add(y, w, zf, zb, zd, wd, flag="", cr=None, flare=0.0):
        if flare:   # axle stations: raise the wing over the wheel if the bonnet / boot is lower than the arch
            zb = max(zb, fender)
            zd = max(zd, zb + 0.04)
        S.append((section(y, hw * w, zf, zb, zd, hw * wd, crown if cr is None else cr, flare), flag))

    tb = min(belt, tz)  # beltline under the boot
    # --- tail
    add(tail + 0.02, tw * 0.74, c + 0.55, tz - 0.55, tz - 0.5, tw * 0.6, cr=0.02)
    add(tail + 0.12, tw * 0.93, c + 0.22, tb - 0.2, tz - 0.14, tw * 0.8, cr=0.04)
    add(tail + 0.7, tw + (1 - tw) * 0.5, c + 0.06, tb - 0.04, tz - 0.03, tw * 0.84)
    add(yar - p["wheel_r"] * 0.4, 1.0, c, tb, tz, 0.84, flare=fl)
    add(yar + p["wheel_r"] * 0.5, 1.0, c, tb, tz, 0.84, flare=fl)
    if ydk - (yar + p["wheel_r"] * 0.5) > 0.6:
        add(ydk - 0.25, 1.0, c, belt, tz, 0.85)
    add(ydk, 1.0, c, belt, tz + 0.04, 0.84, "rw")                 # base of the rear screen
    add(yrr, 1.0, c, belt, roof - 0.06, rw_, "glass")              # rear of the roof
    add(yb - 0.22, 1.0, c, belt, roof, rw_, "pillar")              # B pillar
    add(yb + 0.22, 1.0, c, belt, roof, rw_, "glass")
    add(ywt, 1.0, c, belt, roof - 0.05, rw_, "ws")                 # header rail
    add(yc, 1.0, c, belt, hc + 0.05, 0.86)                          # cowl / base of the windscreen
    add(yc + 0.3, 1.0, c, hc - 0.04, hc, 0.86)
    add(yaf + p["wheel_r"] * 0.5, 1.0, c, (hc + hf) / 2 - 0.03, (hc + hf) / 2 + 0.03, 0.85, flare=fl)
    add(yaf - p["wheel_r"] * 0.4, 0.99, c, hf + 0.06, hf + 0.12, 0.84, flare=fl)
    add(nose - 0.8, nw + (1 - nw) * 0.55, c + 0.05, hf - 0.02, hf + 0.03, nw * 0.82)
    add(nose - 0.14, nw * 0.95, c + 0.2, hf - 0.2, hf - 0.14, nw * 0.76, cr=0.04)
    add(nose - 0.02, nw * 0.76, c + 0.5, hf - 0.6, hf - 0.55, nw * 0.6, cr=0.02)
    return [s[0] for s in S], [s[1] for s in S]


def body_shell(p, paint, extra_cut=None):
    rings, flags = stations(p)

    def mat_fn(i, j):
        f = flags[i]
        if f in ("glass",) and j in M.SIDE_GLASS:
            return 1
        if f in ("ws", "rw") and j in M.TOP_STRIPS:
            return 1
        if f in ("ws", "rw") and j in M.SIDE_GLASS and p.get("quarter_glass", True):
            return 1 if j in (7, 12) else 0   # small quarter lights, leaving real A / C pillars
        return 0

    shell = loft("shell", rings, materials=[paint, M.GLASS()], mat_fn=mat_fn)
    M.subsurf(shell, p.get("subdiv", 2))
    # wheel arches
    for y in (p["axle_f"], p["axle_r"]):
        M.cut_arch(shell, y, p["wheel_r"] * p.get("arch_z", 0.95), p["wheel_r"] * p.get("arch", 1.2), p["W"] * 0.3)
    if extra_cut:
        extra_cut(shell)
    for poly in shell.data.polygons:
        poly.use_smooth = True
    return shell


def split_glass(shell):
    M.select([shell])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    body, glass = None, None
    for ob in bpy.context.selected_objects:
        names = [s.material.name for s in ob.material_slots if s.material]
        used = {ob.data.materials[pl.material_index].name for pl in ob.data.polygons} if ob.data.polygons else set()
        if any(n.startswith("Glass") for n in used):
            glass = ob
        else:
            body = ob
    return body, glass


def interior(p, lhd=True):
    """Dark cabin tub, dashboard, steering wheel and seats so the glass shows a real inside."""
    hw, c, belt = p["W"] / 2, p["clear"], p["belt"]
    yc, ydk = p["cowl"], p["deck"]
    parts = []
    floor_z = c + 0.25
    parts.append(box("tub", (hw * 1.7, yc - ydk - 0.2, 0.15), (0, (yc + ydk) / 2, floor_z), M.INTERIOR(), bev=0.02))
    parts.append(box("dash", (hw * 1.7, 0.9, 0.7), (0, yc - 0.55, belt - 0.3), M.INTERIOR(), bev=0.15))
    parts.append(box("rearshelf", (hw * 1.7, 0.8, 0.12), (0, ydk + 0.35, belt - 0.05), M.INTERIOR(), bev=0.03))
    parts.append(box("console", (0.6, (yc - ydk) * 0.5, 0.55), (0, (yc + ydk) / 2 + 0.3, floor_z + 0.3), M.PLASTIC(), bev=0.08))
    sx = -hw * 0.48 if lhd else hw * 0.48
    col = tube("column", [(sx, yc - 0.75, belt - 0.4), (sx, yc - 1.25, belt - 0.12)], 0.07, M.PLASTIC(), segs=8)
    ring_pts = [(sx + 0.42 * math.cos(a), yc - 1.3 - 0.12 * math.sin(a), belt - 0.1 + 0.42 * math.sin(a)) for a in [M.TAU * k / 20 for k in range(20)]]
    parts += [col, tube("wheelrim", ring_pts, 0.05, M.PLASTIC(), segs=8, closed=True)]
    rows = p.get("seat_rows", [yc - 2.1, ydk + 1.3])
    for ri, y in enumerate(rows):
        for x in ((-hw * 0.48, hw * 0.48) if ri == 0 or not p.get("bench", True) else (0,)):
            wseat = hw * 0.7 if (ri == 0 or not p.get("bench", True)) else hw * 1.6
            parts.append(box("cushion", (wseat, 1.15, 0.3), (x, y, floor_z + 0.5), M.SEAT(), bev=0.1))
            parts.append(box("back", (wseat, 0.3, 1.35), (x, y - 0.6, floor_z + 1.15), M.SEAT(), bev=0.12, rot=(math.radians(-12), 0, 0)))
            for hx in ((x,) if wseat < hw else (-hw * 0.5, hw * 0.5)):
                parts.append(box("headrest", (0.55, 0.22, 0.4), (hx, y - 0.78, floor_z + 2.0), M.SEAT(), bev=0.08))
    return parts


def mirror_pod(surf, p, paint, side):
    y, z = p["cowl"] - 0.15, p["belt"] + 0.18
    loc, _ = surf.point("R" if side > 0 else "L", y, z - 0.1)
    if loc is None:
        return []
    x0 = loc.x
    pod = M.from_bm("pod", _ellipsoid(0.32, 0.13, 0.19), paint)
    M.place(pod, (x0 + side * 0.3, y - 0.02, z + 0.02))
    glass = box("mglass", (0.46, 0.02, 0.26), (x0 + side * 0.3, y - 0.125, z + 0.02), M.CHROME(), bev=0.01)
    stalk = box("stalk", (0.3, 0.14, 0.08), (x0 + side * 0.14, y, z - 0.08), M.DARK(), bev=0.02)
    return [pod, glass, stalk]


def _ellipsoid(rx, ry, rz):
    import bmesh
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=1)
    bmesh.ops.scale(bm, vec=(rx, ry, rz), verts=bm.verts)
    return bm


def details(surf, p, paint, G):
    """Everything that sits ON the body surface. G is the dict of part groups being filled."""
    hw, L, c = p["W"] / 2, p["L"], p["clear"]
    belt, hf, tz = p["belt"], p["hood_front"], p["trunk"]
    yc, ydk, yb = p["cowl"], p["deck"], p.get("b_pillar", (p["ws_top"] + p["roof_rear"]) / 2)
    P = surf.project
    add = lambda group, ob: G[group].append(ob) if ob is not None else None

    # ---- front
    hl = p.get("headlight", (0.5, 0.92, hf - 0.85, hf - 0.28))    # x0 frac, x1 frac, z0, z1
    for s in (-1, 1):
        x0, x1 = sorted((s * hw * hl[0], s * hw * hl[1]))
        add("Trim", P("hl_bezel", "F", (x0 - 0.06, hl[2] - 0.06, x1 + 0.06, hl[3] + 0.06), M.CHROME(), 0.012, res=0.06, round_r=0.2))
        add("Lights", P("headlight", "F", (x0, hl[2], x1, hl[3]), M.HEADLIGHT(), 0.03, res=0.06, thickness=0.03, round_r=0.16))
        ix0, ix1 = sorted((s * hw * 0.74, s * hw * 0.94))
        add("Lights", P("indicator", "F", (ix0, hl[2] - 0.3, ix1, hl[2] - 0.12), M.AMBER(), 0.03, res=0.05, round_r=0.07))
    gr = p.get("grille", (0.42, c + 0.95, hf - 0.32))            # half-width frac, z0, z1
    if gr:
        add("Trim", P("grille", "F", (-hw * gr[0], gr[1], hw * gr[0], gr[2]), M.DARK(), 0.015, round_r=0.08))
        n = p.get("grille_bars", 4)
        for k in range(n):
            z = gr[1] + (gr[2] - gr[1]) * (k + 0.5) / n
            add("Trim", P("bar", "F", (-hw * gr[0] + 0.06, z - 0.03, hw * gr[0] - 0.06, z + 0.03), M.CHROME(), 0.035, thickness=0.02))
    add("Trim", P("intake", "F", (-hw * 0.6, c + 0.22, hw * 0.6, c + 0.7), M.DARK(), 0.015, round_r=0.1))
    for s in (-1, 1):
        add("Lights", P("fog", "F", (s * hw * 0.72 - 0.16, c + 0.34, s * hw * 0.72 + 0.16, c + 0.6), M.HEADLIGHT(), 0.03, round_r=0.11))
    add("Trim", P("plateF", "F", (-0.75, c + 0.72, 0.75, c + 1.08), M.PLATE(), 0.03, thickness=0.02) if p.get("plate_front", True) else None)

    # ---- rear
    tl = p.get("taillight", (0.42, 0.95, tz - 0.75, tz - 0.3))
    for s in (-1, 1):
        x0, x1 = sorted((s * hw * tl[0], s * hw * tl[1]))
        add("Lights", P("taillight", "B", (x0, tl[2], x1, tl[3]), M.TAILLIGHT(), 0.03, res=0.06, thickness=0.03, round_r=0.14))
        add("Lights", P("reverse", "B", (min(s * hw * 0.2, s * hw * 0.4), tl[2] + 0.08, max(s * hw * 0.2, s * hw * 0.4), tl[3] - 0.08), mat("Reverse", "#f1f1f1", rough=0.2, emit=0.4), 0.03, round_r=0.06))
    add("Trim", P("plateB", "B", (-0.75, tl[2] - 0.55, 0.75, tl[2] - 0.17), M.PLATE(), 0.03, thickness=0.02))
    add("Trim", P("valance", "B", (-hw * 0.7, c + 0.2, hw * 0.7, c + 0.6), M.DARK(), 0.015, round_r=0.1))
    for x in p.get("exhausts", (-hw * 0.55,)):
        tip = cyl("exhaust", 0.14, 0.5, (x, -L / 2 + 0.1, c + 0.32), M.CHROME(), "Y", segs=16)
        hole = cyl("exhole", 0.105, 0.52, (x, -L / 2 + 0.08, c + 0.32), M.DARK(), "Y", segs=16, bev=0)
        G["Trim"] += [tip, hole]

    # ---- sides: shut-lines, handles, trim
    seam = M.DARK()
    doors = p.get("doors", [yc - 0.35, yb, p["roof_rear"] - 0.2])
    for side in ("L", "R"):
        for y in doors:
            add("Trim", P("seam", side, (y - 0.022, c + 0.3, y + 0.022, belt - 0.02), seam, 0.006, res=0.1))
        add("Trim", P("sill", side, (doors[-1], c + 0.28, doors[0], c + 0.325), seam, 0.006, res=0.15))
        add("Trim", P("beltline", side, (ydk + 0.1, belt - 0.035, yc - 0.1, belt + 0.035), M.CHROME() if p.get("chrome", True) else M.DARK(), 0.012, res=0.15))
        for a, b in zip(doors[:-1], doors[1:]):
            yh = b - 0.55
            loc, nrm = surf.point(side, yh, belt - 0.38)
            if loc is not None:
                G["Trim"].append(box("handle", (0.07, 0.48, 0.11), loc + nrm * 0.035, M.CHROME() if p.get("chrome", True) else paint, bev=0.03))
        add("Lights", P("repeater", side, (p["axle_f"] + p["wheel_r"] * 1.35, belt - 0.5, p["axle_f"] + p["wheel_r"] * 1.35 + 0.3, belt - 0.38), M.AMBER(), 0.012))
        # arch lip
    # ---- top: bonnet + boot shut-lines, wipers, antenna
    add("Trim", P("hoodseamL", "T", (-hw * 0.84, yc + 0.25, -hw * 0.84 + 0.04, L / 2 - 0.9), seam, 0.006, res=0.15))
    add("Trim", P("hoodseamR", "T", (hw * 0.84 - 0.04, yc + 0.25, hw * 0.84, L / 2 - 0.9), seam, 0.006, res=0.15))
    add("Trim", P("hoodseamF", "T", (-hw * 0.84, L / 2 - 0.94, hw * 0.84, L / 2 - 0.9), seam, 0.006, res=0.15))
    if ydk - (-L / 2) > 1.6:
        add("Trim", P("bootseam", "T", (-hw * 0.8, -L / 2 + 0.5, hw * 0.8, -L / 2 + 0.54), seam, 0.006, res=0.15))
        add("Trim", P("bootseamL", "T", (-hw * 0.8, -L / 2 + 0.5, -hw * 0.8 + 0.04, ydk - 0.1), seam, 0.006, res=0.15))
        add("Trim", P("bootseamR", "T", (hw * 0.8 - 0.04, -L / 2 + 0.5, hw * 0.8, ydk - 0.1), seam, 0.006, res=0.15))
    add("Trim", P("cowl", "T", (-hw * 0.8, yc + 0.02, hw * 0.8, yc + 0.3), M.PLASTIC(), 0.012, res=0.12))
    for x0 in (-hw * 0.55, hw * 0.1):
        a, _ = surf.point("T", x0, yc + 0.12)
        b, _ = surf.point("T", x0 + hw * 0.5, yc - 0.5)
        if a is not None and b is not None:
            G["Trim"].append(tube("wiper", [a + Vector((0, 0, 0.06)), (a + b) / 2 + Vector((0, 0, 0.09)), b + Vector((0, 0, 0.05))], 0.03, M.DARK(), segs=6))
    top, _ = surf.point("T", 0, p["roof_rear"] + 0.5)
    if top is not None and p.get("antenna", True):
        G["Trim"].append(loft("fin", [[(-0.07, top.y - 0.3, top.z), (0.07, top.y - 0.3, top.z), (0.02, top.y - 0.34, top.z + 0.28), (-0.02, top.y - 0.34, top.z + 0.28)],
                                      [(-0.05, top.y + 0.35, top.z), (0.05, top.y + 0.35, top.z), (0.01, top.y - 0.1, top.z + 0.22), (-0.01, top.y - 0.1, top.z + 0.22)]], M.DARK()))
    for s in (-1, 1):
        G["Body"] += mirror_pod(surf, p, paint, s)[:1]
        G["Trim"] += mirror_pod(surf, p, paint, s)[1:]


def new_groups():
    return dict(Body=[], Glass=[], Lights=[], Trim=[], Wheels=[], Spin=[], Turret=[])


def build_car(p, wheels, extras=None, extra_cut=None):
    """p: dimension dict. wheels: list of dicts from vehicles.json (pos in ROBLOX axes, radius, width)."""
    paint = M.paint(p["color"])
    G = new_groups()
    shell = body_shell(p, paint, extra_cut)
    surf = M.Surface(shell)
    body, glass = split_glass(shell)
    G["Body"].append(body)
    if glass:
        G["Glass"].append(glass)
    if p.get("interior", True):
        G["Trim"] += interior(p)
    details(surf, p, paint, G)
    # wheel-well liners + axle stubs
    ar = p["wheel_r"] * p.get("arch", 1.2)
    for y in (p["axle_f"], p["axle_r"]):
        for sx in (-1, 1):   # one dark wheel-well cup per corner: closed inboard, open towards the wheel
            cup = lathe("liner", [(0, 0), (ar - 0.015, 0), (ar - 0.015, p["W"] * 0.32)], M.matte("#0c0c0d", 0.95), segs=32, axis="X", cap=False)
            if sx < 0:
                cup.scale.x = -1
            M.place(cup, (sx * p["W"] * 0.17, y, p["wheel_r"] * p.get("arch_z", 0.95)))
            G["Trim"].append(cup)
        G["Trim"].append(cyl("axle", 0.14, p["W"] * 0.8, (0, y, p["wheel_r"]), M.STEEL(), "X", segs=10, bev=0))
    for i, w in enumerate(wheels):
        x, yr_, zr_ = w["pos"][0], w["pos"][1], w["pos"][2]
        ob = M.wheel("Wheel%d" % (i + 1), w["radius"], w["width"], p.get("wheel_style", "alloy5"), 1 if x > 0 else -1, p.get("rim_color"), p.get("caliper", "#b3261e"))
        M.place(ob, (x, -zr_, yr_))
        M.set_origin(ob, (x, -zr_, yr_))
        G["Wheels"].append(ob)
    if extras:
        extras(p, surf, paint, G)
    return G


def recess(ob, x0, x1, y0, y1, z_min, floor_z):
    """Sink the part of a deck inside a rectangle down to floor_z (pickup beds, open cockpits)."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for v in bm.verts:
        if x0 < v.co.x < x1 and y0 < v.co.y < y1 and v.co.z > z_min:
            v.co.z = floor_z
    bm.to_mesh(ob.data)
    bm.free()


def lift(G, dz, groups=("Body", "Glass", "Lights", "Trim")):
    for g in groups:
        for ob in G[g]:
            ob.location.z += dz
            M.apply_xf(ob)


def wing(name, span, chord, thick, material, tip_chord=None, n=14):
    """Symmetric aerofoil section lofted across a span along X (spoilers, plane wings use aircraft.py)."""
    def ring(x, c):
        pts = []
        for k in range(n):
            t = k / (n - 1)
            xx = 0.5 * (1 - math.cos(math.pi * t))
            yt = 5 * thick * (0.2969 * math.sqrt(xx) - 0.126 * xx - 0.3516 * xx ** 2 + 0.2843 * xx ** 3 - 0.1036 * xx ** 4)
            pts.append((xx, yt))
        loop = [(x, (0.5 - xx) * c, yt * c) for xx, yt in pts] + [(x, (0.5 - xx) * c, -yt * c) for xx, yt in reversed(pts[1:-1])]
        return loop
    tc = tip_chord or chord
    return loft(name, [ring(-span / 2, tc), ring(0, chord), ring(span / 2, tc)], material)
