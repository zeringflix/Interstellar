"""Researched cockpits and interiors, built around the cockpit data in vehicles.json.

Every vehicle has a driver's eye point and a control (wheel, yoke, handlebars, sticks, levers or
grips) in blender/vehicles_spec.py. The game seats the avatar with its head at the eye point and
puts the first-person camera there, so everything here is laid out from it:
  * the driver's seat sits under the eye, the control sits where the avatar's hands can reach it;
  * dashboards and panels stay below the sight line through the windscreen;
  * the steering control is its own mesh (group "Steer") so the game can turn it with the input;
  * Roblox draws a mesh from one side only, so each cab gets an inward-facing lining (headliner,
    pillar and door trim) copied from its own body shell; without it the roof and doors would be
    invisible from inside.

Research notes per vehicle are in the README ("Interiors").
"""
import json
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

import rcp_model as M
from rcp_model import TAU, box, cyl, lathe, loft, mat, tube


SPEC = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "vehicles.json")))["vehicles"]


def rb(v):
    """Roblox (x, y up, -z front) -> Blender (x, y front, z up)."""
    return Vector((v[0], -v[2], v[1]))


# ---- materials (names drive the texture pass: Seat* = fabric, metal > 0.5 = metal, else plastic)
def CLOTH(c="#34322f"):
    return mat("SeatCloth", c, rough=0.92)


def LEATHER(c="#26211e"):
    return mat("SeatLeather", c, rough=0.55)


def HEADLINER(c="#9a958c"):
    return mat("SeatHeadliner", c, rough=0.95)


def DASH(c="#1c1d20"):
    return mat("Dash", c, rough=0.72)


def SOFT(c="#2b2c30"):
    return mat("DashSoft", c, rough=0.86)


def CARBON():
    return mat("Carbon", "#16171a", rough=0.28)


def PANEL(c="#2a2d31"):
    return mat("InstrumentPanel", c, rough=0.6)


def FACE():
    return mat("GaugeFace", "#0b0c0e", rough=0.35)


def TICK():
    return mat("GaugeTick", "#f1f1ec", rough=0.4)


def NEEDLE():
    return mat("GaugeNeedle", "#ff5418", rough=0.35)


def SCREEN():
    return mat("Screen", "#0b1622", rough=0.1)


def UI(c="#2b7fe0"):
    return mat("ScreenUI", c, rough=0.3)


def RUBBER_MAT():
    return mat("Rubber", "#0f0f10", rough=0.9)


def KNOB(c="#d8231c"):
    return mat("Knob", c, rough=0.35)


def BRASS():
    return mat("Brass", "#c9a24a", rough=0.3, metal=1.0)


# ---- oriented placement -------------------------------------------------------------------
def frame(origin, right, up):
    """Matrix taking local X -> right, Y -> up, Z -> right x up (the face normal) at origin."""
    r = Vector(right).normalized()
    n = r.cross(Vector(up)).normalized()
    u = n.cross(r).normalized()
    o = Vector(origin)
    return Matrix(((r.x, u.x, n.x, o.x), (r.y, u.y, n.y, o.y), (r.z, u.z, n.z, o.z), (0, 0, 0, 1)))


def put(ob, m):
    ob.data.transform(m)
    ob.data.update()
    return ob


def facing(origin, target, roll_up=(0, 0, 1)):
    """Frame at origin whose face (local +Z) looks at target, local Y as close to roll_up as possible."""
    n = (Vector(target) - Vector(origin)).normalized()
    r = Vector(roll_up).cross(n)
    if r.length < 1e-4:
        r = Vector((1, 0, 0))
    return frame(origin, r.normalized(), n.cross(r.normalized()))


def wheel_frame(center, tilt_deg):
    """Steering wheel plane: local Y up the rim, local Z along the column towards the driver.
    tilt = how far the top of the rim leans forward (away from the driver) from vertical."""
    t = math.radians(tilt_deg)
    return frame(center, (1, 0, 0), (0, math.sin(t), math.cos(t)))


# ---- instruments --------------------------------------------------------------------------
def dial(name, m, r, ticks=9, needle=0.3, sweep=270, ring=None, face=None):
    """Round gauge in frame m (face +Z): face, bezel, tick marks, needle, hub."""
    parts = [put(cyl(name + "face", r, 0.03, (0, 0, 0), face or FACE(), "Z", segs=24, bev=0), m)]
    rp = [(r * math.cos(TAU * k / 24), r * math.sin(TAU * k / 24), 0.03) for k in range(24)]
    parts.append(put(tube(name + "bezel", rp, max(0.016, r * 0.08), ring or M.CHROME(), segs=6, closed=True), m))
    a0 = math.radians(90 + sweep / 2)
    for k in range(ticks):
        a = a0 - math.radians(sweep) * k / max(1, ticks - 1)
        c = Vector((math.cos(a), math.sin(a), 0.022))
        parts.append(put(box(name + "tick", (r * 0.07, r * 0.24, 0.012), tuple(Vector((c.x * r * 0.76, c.y * r * 0.76, 0.022))), TICK(), bev=0, rot=(0, 0, a - math.pi / 2)), m))
    an = a0 - math.radians(sweep) * needle
    nd = Vector((math.cos(an), math.sin(an), 0))
    parts.append(put(box(name + "needle", (r * 0.05, r * 0.7, 0.012), tuple(nd * r * 0.3 + Vector((0, 0, 0.036))), NEEDLE(), bev=0, rot=(0, 0, an - math.pi / 2)), m))
    parts.append(put(cyl(name + "hub", r * 0.11, 0.03, (0, 0, 0.045), M.DARK(), "Z", segs=10, bev=0), m))
    return parts


def screen(name, m, w, h, ui="#2b7fe0", bars=4):
    """Glossy display in frame m with a simple UI drawn on it (tiles / map strip)."""
    parts = [put(box(name, (w + 0.06, h + 0.06, 0.06), (0, 0, 0), M.DARK(), bev=0.02), m),
             put(box(name + "glass", (w, h, 0.012), (0, 0, 0.034), SCREEN(), bev=0), m)]
    for k in range(bars):
        y = -h / 2 + h * (k + 0.6) / (bars + 0.4)
        parts.append(put(box(name + "ui", (w * (0.55 if k % 2 else 0.8), h * 0.09, 0.008), (-w * 0.08, y, 0.044), UI(ui if k else "#e8eef6"), bev=0), m))
    return parts


def toggles(name, m, n, pitch=0.16, color="#c7ccd2"):
    """A row of toggle switches with guard plate, frame m (face +Z)."""
    parts = [put(box(name + "plate", (pitch * n + 0.1, 0.24, 0.03), (0, 0, 0), PANEL("#22252a"), bev=0.01), m)]
    for k in range(n):
        x = -pitch * (n - 1) / 2 + pitch * k
        parts.append(put(cyl(name + "boss", 0.035, 0.03, (x, 0, 0.03), M.CHROME(), "Z", segs=8, bev=0), m))
        parts.append(put(box(name + "lever", (0.025, 0.025, 0.13), (x, 0.02, 0.09), mat("Toggle", color, rough=0.3, metal=0.8), bev=0, rot=(math.radians(-25), 0, 0)), m))
    return parts


# ---- steering controls (built in the wheel frame, then placed) -----------------------------
def steering_wheel(name, m, r, spokes=3, grip=0.075, flat_bottom=False, rim_mat=None, wood=False):
    parts = []
    pts = []
    for k in range(40):
        a = TAU * k / 40
        x, y = r * math.cos(a), r * math.sin(a)
        if flat_bottom and y < -r * 0.74:
            y = -r * 0.74
        pts.append((x, y, 0))
    rim_m = rim_mat or (mat("WoodRim", "#5a3418", rough=0.35) if wood else LEATHER("#18181a"))
    parts.append(tube(name + "rim", pts, grip, rim_m, segs=10, closed=True))
    angles = {2: (0, math.pi), 3: (0, math.pi, -math.pi / 2), 4: (math.radians(20), math.radians(160), math.radians(-35), math.radians(-145))}[spokes]
    for a in angles:
        parts.append(tube(name + "spoke", [(math.cos(a) * r * 0.24, math.sin(a) * r * 0.2, -0.05), (math.cos(a) * (r - grip * 0.6), math.sin(a) * (r - grip * 0.6), 0)],
                          0.045, M.ALLOY() if wood else DASH("#202124"), segs=6))
    parts.append(box(name + "hub", (r * 0.62, r * 0.48, 0.16), (0, -r * 0.04, -0.03), DASH("#151618"), bev=0.07, segs=3))
    parts.append(cyl(name + "badge", r * 0.09, 0.03, (0, -r * 0.02, 0.06), M.CHROME(), "Z", segs=14, bev=0.01))
    return [put(p, m) for p in parts]


def yoke(name, m, width):
    """Aircraft control wheel: two horns on a centre boss, shaft forward along -Z."""
    w = width / 2
    parts = [tube(name + "horn", [(-w, 0.18, 0), (-w * 0.92, -0.12, 0), (-w * 0.55, -0.2, 0), (w * 0.55, -0.2, 0), (w * 0.92, -0.12, 0), (w, 0.18, 0)], 0.065, DASH("#18191b"), segs=10, smooth=4),
             box(name + "boss", (w * 0.7, 0.26, 0.14), (0, -0.18, -0.02), PANEL("#33363b"), bev=0.05),
             cyl(name + "ptt", 0.03, 0.04, (-w * 0.95, 0.2, 0.05), KNOB("#c0141a"), "Z", segs=8, bev=0),
             cyl(name + "trim", 0.03, 0.04, (w * 0.95, 0.2, 0.05), M.CHROME(), "Z", segs=8, bev=0)]
    return [put(p, m) for p in parts]


def tbar(name, m, width):
    """Tank driver's T-bar / handlebars with twist-grip throttles."""
    w = width / 2
    parts = [tube(name + "bar", [(-w, 0, 0), (w, 0, 0)], 0.06, M.STEEL(), segs=10),
             cyl(name + "gripL", 0.085, 0.4, (-w + 0.2, 0, 0), RUBBER_MAT(), "X", segs=12, bev=0.02),
             cyl(name + "gripR", 0.085, 0.4, (w - 0.2, 0, 0), RUBBER_MAT(), "X", segs=12, bev=0.02),
             box(name + "boss", (0.4, 0.25, 0.25), (0, 0, -0.05), M.STEEL(), bev=0.05)]
    return [put(p, m) for p in parts]


def column(name, center, tilt, length=1.45, radius=0.09, shroud=True):
    """Steering column from the wheel hub forward and down into the dash, with a shroud and stalks."""
    m = wheel_frame(center, tilt)
    parts = [put(cyl(name, radius, length, (0, 0, -length / 2 - 0.12), DASH("#1a1b1e"), "Z", segs=12, bev=0.02), m)]
    if shroud:
        parts.append(put(box(name + "shroud", (0.42, 0.34, 0.6), (0, -0.04, -0.45), SOFT("#222327"), bev=0.1, segs=3), m))
        for s in (-1, 1):
            parts.append(put(tube(name + "stalk", [(s * 0.2, 0.02, -0.38), (s * 0.55, 0.06, -0.3)], 0.025, DASH("#141517"), segs=6), m))
    return parts


# ---- seats --------------------------------------------------------------------------------
def seat(name, x, y_hip, z_top, width=1.9, back=14, kind="bucket", material=None, back_h=2.3, headrest=True, depth=1.45):
    """A seat whose occupant's hips (the avatar's root) sit at (x, y_hip) on a cushion top at z_top.
    The back's front face clears the avatar's torso (1 stud deep, centred on the root)."""
    mtl = material or CLOTH()
    parts = []
    cz = z_top - 0.19
    parts.append(box(name + "cushion", (width, depth, 0.38), (x, y_hip + 0.3, cz), mtl, bev=0.12, segs=3, rot=(math.radians(5), 0, 0)))
    a = math.radians(back)
    up = Vector((0, -math.sin(a), math.cos(a)))
    base = Vector((x, y_hip - 0.72, z_top - 0.12))
    c = base + up * (back_h / 2)
    parts.append(box(name + "back", (width * 0.96, 0.32, back_h), tuple(c), mtl, bev=0.12, segs=3, rot=(a, 0, 0)))
    if kind in ("bucket", "racing"):
        bl = 0.32 if kind == "bucket" else 0.42
        for s in (-1, 1):
            parts.append(box(name + "bolster", (0.26, depth * 0.85, 0.22), (x + s * (width / 2 - 0.13), y_hip + 0.28, z_top + 0.06), mtl, bev=0.09, rot=(math.radians(5), 0, 0)))
            bc = base + up * (back_h * 0.45) + Vector((s * (width / 2 - 0.12), 0.12, 0))
            parts.append(box(name + "wing", (0.24, bl, back_h * 0.75), tuple(bc), mtl, bev=0.09, rot=(a, 0, 0)))
    if kind == "racing":   # harness slots + belts down the back
        for s in (-1, 1):
            sc = base + up * (back_h * 0.86) + Vector((s * 0.35, 0.18, 0))
            parts.append(box(name + "slot", (0.22, 0.05, 0.42), tuple(sc), M.DARK(), bev=0.02, rot=(a, 0, 0)))
    if headrest and kind != "racing":
        hc = base + up * (back_h + 0.42)
        parts.append(box(name + "headrest", (width * 0.5, 0.3, 0.55), tuple(hc), mtl, bev=0.12, segs=3, rot=(a, 0, 0)))
        for s in (-1, 1):
            p0 = base + up * back_h + Vector((s * 0.22, 0, 0))
            parts.append(tube(name + "post", [p0, p0 + up * 0.18], 0.03, M.CHROME(), segs=6))
    return parts


def bench(name, x0, x1, y_hip, z_top, back=16, material=None, back_h=2.1):
    w = x1 - x0
    return seat(name, (x0 + x1) / 2, y_hip, z_top, width=w, back=back, kind="bench", material=material, back_h=back_h)


def harness(name, x, y_hip, z_top, color="#c4161c"):
    """Five-point harness lying over an (invisible) occupant: shoulder straps and lap belt."""
    m = mat("Harness", color, rough=0.75)
    parts = []
    for s in (-1, 1):
        parts.append(tube(name + "shoulder", [(x + s * 0.35, y_hip - 0.75, z_top + 2.2), (x + s * 0.32, y_hip - 0.45, z_top + 2.05), (x + s * 0.22, y_hip + 0.15, z_top + 0.9)], 0.05, m, segs=6, smooth=3))
        parts.append(tube(name + "lap", [(x + s * 0.95, y_hip - 0.25, z_top + 0.1), (x + s * 0.3, y_hip + 0.3, z_top + 0.55)], 0.05, m, segs=6))
    parts.append(box(name + "buckle", (0.26, 0.08, 0.26), (x, y_hip + 0.38, z_top + 0.6), M.CHROME(), bev=0.04))
    return parts


def pedals(name, x, y, z, n=2, gap=0.42, color=None):
    parts = []
    for k in range(n):
        px = x - gap * (n - 1) / 2 + gap * k
        w = 0.42 if (n == 2 and k == 0) else 0.24
        parts.append(box(name, (w, 0.08, 0.38), (px, y, z), RUBBER_MAT(), bev=0.03, rot=(math.radians(-25), 0, 0)))
        parts.append(tube(name + "arm", [(px, y + 0.05, z + 0.15), (px, y + 0.3, z + 0.75)], 0.03, M.STEEL(), segs=6))
    return parts


# ---- inner lining: the cab seen from inside -------------------------------------------------
def lining(name, body, lo, hi, material, inset=0.05, skip_down=True):
    """Copy the body-shell faces inside the box lo..hi, push them inwards and flip them to face the
    cabin: headliner, pillar trim and door cards in one piece."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.transform(body.matrix_world)
    lo, hi = Vector(lo), Vector(hi)
    drop = []
    for f in bm.faces:
        c = f.calc_center_median()
        inside = all(lo[i] <= c[i] <= hi[i] for i in range(3))
        if not inside or (skip_down and f.normal.z < -0.6):
            drop.append(f)
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    if not bm.faces:
        bm.free()
        return None
    bm.normal_update()
    for v in bm.verts:
        v.co -= v.normal * inset
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(material)
    return ob


def inner_box(name, lo, hi, material, open_faces=()):
    """A box seen from inside (faces point inwards). open_faces: any of 'front','back','left','right','top','bottom'."""
    bm = bmesh.new()
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    v = [bm.verts.new(p) for p in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
    quads = dict(bottom=(0, 1, 2, 3), top=(7, 6, 5, 4), back=(4, 5, 1, 0), front=(3, 2, 6, 7), left=(0, 3, 7, 4), right=(1, 5, 6, 2))
    for k, q in quads.items():
        if k not in open_faces:
            bm.faces.new([v[i] for i in q])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(material)
    return ob


# ---- shared cockpit data ------------------------------------------------------------------
class Cockpit:
    def __init__(self, s):
        ck = s["cockpit"]
        self.eye = rb(ck["eye"])
        self.ctl = ck["control"]
        self.seat_top = s["seat"][1] + 0.3
        self.hip = Vector((self.eye.x, self.eye.y, self.seat_top))
        if "pos" in self.ctl:
            self.cpos = rb(self.ctl["pos"])
            self.tilt = self.ctl.get("tilt", 20)
            self.size = self.ctl.get("radius", self.ctl.get("width", 1.0))
        self.right = rb(self.ctl["right"]) if "right" in self.ctl else None
        self.left = rb(self.ctl["left"]) if "left" in self.ctl else None


def add(G, group, objs):
    G.setdefault(group, [])
    G[group] += [o for o in objs if o is not None]


def control(G, ck, style="sport", **kw):
    """The driver's steering control as the Steer group (turned by the game), column in Interior."""
    kind = ck.ctl["type"]
    shroud = kw.pop("shroud", True)
    if kind == "wheel":
        add(G, "Steer", steering_wheel("swheel", wheel_frame(ck.cpos, ck.tilt), ck.size, **kw))
        add(G, "Interior", column("column", ck.cpos, ck.tilt, shroud=shroud))
    elif kind == "yoke":
        add(G, "Steer", yoke("yoke", wheel_frame(ck.cpos, ck.tilt), ck.size))
        m = wheel_frame(ck.cpos, ck.tilt)
        add(G, "Interior", [put(cyl("yokeshaft", 0.07, 1.4, (0, -0.15, -0.8), M.CHROME(), "Z", segs=12, bev=0), m)])
    elif kind == "bars":
        add(G, "Steer", tbar("tbar", wheel_frame(ck.cpos, ck.tilt), ck.size))
        m = wheel_frame(ck.cpos, ck.tilt)
        add(G, "Interior", [put(cyl("tbarpost", 0.08, 1.2, (0, 0, -0.8), M.STEEL(), "Z", segs=12, bev=0), m)])


# =============================================================================================
# Road cars: sedan, police car, muscle car, supercar, pickup, monster truck
# =============================================================================================
def car(p, G, body, style="sedan", dz=0.0, key=None):
    """Full car interior. style: sedan | police | muscle | sports | pickup | monster.
    dz: how far the body was lifted after it was built (monster truck)."""
    s = SPEC[key or p["key"]]
    ck = Cockpit(s)
    hw, c, belt, roof = p["W"] / 2, p["clear"] + dz, p["belt"] + dz, p["roof"] + dz
    yc, hc, ywt = p["cowl"], p["hood_cowl"] + dz, p["ws_top"]
    floor = c + 0.25
    inner = hw - 0.42                     # inner half-width at the beltline
    centre = style == "monster"
    sports, muscle = style == "sports", style == "muscle"
    I = []
    dash_m = CARBON() if sports else (DASH("#1f1d1b") if muscle else DASH())
    trim_m = LEATHER("#1c1a19") if sports else (LEATHER("#3a1512") if muscle else CLOTH("#2f2e2c"))
    # --- dashboard: a padded beam under the windscreen across the cab
    # The dash's rear face (back) sits a hand's width in front of the steering wheel: the rim never
    # reaches further forward than its centre + r sin(tilt), so the wheel, its hub and the column
    # stay clear of the dash, the cluster and its hood (before, the sedan's wheel sat in its cluster).
    t_ = math.radians(ck.tilt) if hasattr(ck, "tilt") else 0.0
    rim_front = ck.cpos.y + ck.size * math.sin(t_) if hasattr(ck, "cpos") else yc - 1.5
    back = max(yc - 1.08, rim_front + 0.3)
    D = yc - back
    k = D / 1.08
    prof = [(yc + 0.3, hc - 0.03), (yc - 0.3 * k, hc + 0.0), (yc - 0.9 * k, hc - 0.04), (back, hc - 0.26), (yc - 1.0 * k, belt - 0.75),
            (yc - 0.72 * k, belt - 1.2), (yc - 0.3 * k, floor + 0.65), (yc + 0.3, floor + 0.65)]
    xs = [-inner, -inner + 0.25, inner - 0.25, inner]
    rings = []
    for x in xs:
        k = 0.12 if abs(x) >= inner else 0.0
        rings.append([(x, y - k, z - k * 0.5) for y, z in prof])
    dash = loft("dash", rings, dash_m)
    M.subsurf(dash, 1)
    I.append(dash)
    # top pad / defroster grille
    I.append(box("defrost", (inner * 1.4, 0.35, 0.03), (0, yc - 0.1, hc + 0.0), M.DARK(), bev=0.01))
    # --- instrument cluster under a hood, read through the top half of the wheel
    ex = ck.eye.x
    cy = back + 0.06                       # dial faces just proud of the dash's rear face
    if hasattr(ck, "cpos"):                # read through the gap between hub and rim top
        u = Vector((0, math.sin(t_), math.cos(t_)))
        gap = ck.cpos + u * (ck.size * 0.62)
        f_ = ((cy - 0.12) - ck.eye.y) / max(0.1, gap.y - ck.eye.y)
        zc = min(max(ck.eye.z + (gap.z - ck.eye.z) * f_, hc + 0.05), hc + 0.4)
    else:
        zc = hc + 0.12
    # cluster face behind the dials, with a shallow hood over them
    I.append(box("clusterface", (1.1, 0.12, max(0.5, zc + 0.26 - (hc - 0.2))), (ex, cy + 0.02, (zc + 0.26 + hc - 0.2) / 2), M.DARK(), bev=0.04))
    I.append(box("binnacle", (1.2, 0.5, 0.08), (ex, cy + 0.16, zc + 0.3), dash_m, bev=0.03, segs=2, rot=(math.radians(-8), 0, 0)))
    for s_ in (-1, 1):
        I.append(box("binnacleside", (0.08, 0.42, zc + 0.3 - (hc - 0.1)), (ex + s_ * 0.58, cy + 0.17, (zc + 0.3 + hc - 0.1) / 2), dash_m, bev=0.03))
    toward = Vector((ex, ck.eye.y, ck.eye.z))
    if sports:   # digital cluster
        I += screen("cluster", facing((ex, cy - 0.06, zc), toward), 0.85, 0.32, ui="#ff7a1a")
    elif muscle:  # big round speedo and tach, three small gauges on the console
        for dx, r, nd in ((-0.26, 0.2, 0.35), (0.26, 0.2, 0.55)):
            I += dial("gauge", facing((ex + dx, cy - 0.06, zc), toward), r, needle=nd, ring=M.CHROME())
    else:
        for dx, r, nd in ((-0.27, 0.19, 0.25), (0.27, 0.19, 0.4)):
            I += dial("gauge", facing((ex + dx, cy - 0.06, zc), toward), r, needle=nd, ring=DASH("#3a3c40"))
        I += screen("mid", facing((ex, cy - 0.07, zc - 0.02), toward), 0.2, 0.22, ui="#7fd0ff", bars=3)
    # --- centre stack
    if not centre:
        sx = 0.0
        if style in ("sedan", "police"):
            I += screen("infotainment", facing((sx, back + 0.10, hc + 0.22), toward), 0.85, 0.5)
            I += [box("vent", (0.36, 0.06, 0.16), (sx + dx, back + 0.01, hc - 0.18), M.DARK(), bev=0.03) for dx in (-0.25, 0.25)]
            I += [cyl("knob", 0.07, 0.07, (sx + dx, back + 0.04, belt - 0.42), M.CHROME(), "Y", segs=14, bev=0.01) for dx in (-0.35, 0.35)]
            I.append(box("climate", (0.8, 0.05, 0.22), (sx, back + 0.04, belt - 0.42), PANEL("#1b1d21"), bev=0.03))
        elif muscle:
            I.append(box("radio", (0.8, 0.06, 0.24), (sx, back + 0.03, belt - 0.3), M.CHROME(), bev=0.03))
            I += [cyl("radioknob", 0.06, 0.08, (sx + dx, back - 0.02, belt - 0.3), DASH(), "Y", segs=12, bev=0.01) for dx in (-0.3, 0.3)]
        elif sports:
            I += screen("infotainment", facing((sx, back + 0.10, hc + 0.05), toward), 0.6, 0.38, ui="#ff7a1a")
        else:   # pickup: big round vents, simple radio
            I.append(box("radio", (0.85, 0.06, 0.32), (sx, back + 0.03, belt - 0.35), PANEL(), bev=0.04))
            I += screen("radiodisp", facing((sx, back - 0.01, belt - 0.3), toward), 0.4, 0.12, ui="#7fd0ff", bars=1)
        # vents at the outer ends of the dash
        for s_ in (-1, 1):
            I.append(cyl("sidevent", 0.16, 0.08, (s_ * (inner - 0.4), back + 0.02, hc - 0.18), M.DARK(), "Y", segs=16, bev=0.02))
        # glovebox seam on the passenger side
        I.append(box("glovebox", (0.95, 0.03, 0.4), (-ex * 0.85, back + 0.06, belt - 0.55), dash_m, bev=0.02))
    # --- console / tunnel between the front seats with the gear selector
    if not centre:
        cl = max(1.4, (back + 0.08) - (ck.eye.y - 1.1))
        I.append(box("console", (0.8, cl, belt - 0.9 - floor), (0, (back + 0.08 + ck.eye.y - 1.1) / 2, floor + (belt - 0.9 - floor) / 2), dash_m if sports else SOFT(), bev=0.1, segs=3))
        gy = back - 0.47
        gz = belt - 0.82
        if muscle or sports:
            I.append(tube("shifter", [(0, gy, gz), (0, gy - 0.12, gz + 0.5)], 0.035, M.CHROME(), segs=8))
            I.append(lathe("shiftknob", [(0, 0), (0.09, 0.02), (0.1, 0.1), (0.07, 0.18), (0, 0.2)], mat("ShiftKnob", "#101011", rough=0.2), segs=14, axis="Z", loc=(0, gy - 0.12, gz + 0.48)))
            I.append(box("boot", (0.3, 0.3, 0.08), (0, gy, gz + 0.03), LEATHER("#141414"), bev=0.04))
        elif style == "pickup":
            # column shifter stalk on the right of the column
            pass
        else:
            I.append(box("selector", (0.16, 0.34, 0.24), (0, gy, gz + 0.12), DASH("#121314"), bev=0.06))
        I.append(box("armrest", (0.72, 0.9, 0.18), (0, ck.eye.y - 0.8, belt - 0.65), trim_m, bev=0.08))
    if style == "pickup":
        # column shifter: comes out of the column behind the wheel and reaches past the rim on the right
        I.append(tube("colshift", [(ex + 0.15, ck.cpos.y + 0.45, ck.cpos.z - 0.2), (ex + 0.6, ck.cpos.y + 0.42, ck.cpos.z - 0.17), (ex + ck.size + 0.25, ck.cpos.y + 0.36, ck.cpos.z - 0.1)], 0.03, M.CHROME(), segs=6))
    # --- seats
    seat_kind = "racing" if (sports or centre) else ("bench" if style == "pickup" else "bucket")
    if style == "pickup":
        I += bench("bench", -inner + 0.1, inner - 0.1, ck.hip.y, ck.seat_top, material=CLOTH("#4a4540"))
    else:
        I += seat("drv", ex, ck.hip.y, ck.seat_top, width=1.95, back=18 if sports else 14, kind=seat_kind, material=trim_m)
        if not centre:
            I += seat("pass", -ex, ck.hip.y, ck.seat_top, width=1.95, back=18 if sports else 14, kind=seat_kind, material=trim_m)
    if sports or centre:
        I += harness("harness", ex, ck.hip.y, ck.seat_top)
    rows = p.get("seat_rows", [])
    rear_row = style in ("sedan", "police", "muscle") and len(rows) > 1
    if rear_row:
        I += bench("rear", -inner + 0.15, inner - 0.15, rows[1] + 0.1, ck.seat_top - 0.05, material=trim_m, back=20)
    # --- pedals and floor
    ped_y = yc - 0.55
    I += pedals("pedal", ex + 0.05, ped_y, floor + 0.45, n=3 if (muscle or sports) else 2)
    y_back = (rows[1] - 1.2) if rear_row else (ck.eye.y - 1.6)
    y_front = yc - 0.3
    I.append(box("tub", (inner * 2, y_front - y_back, 0.12), (0, (y_front + y_back) / 2, floor), mat("SeatCarpet", "#1f1d1c", rough=0.95), bev=0.02))
    # --- door cards: armrests and pulls on the front doors
    for s_ in (-1, 1):
        if centre:
            break
        I.append(box("doorarm", (0.22, 1.2, 0.16), (s_ * (inner - 0.05), ck.eye.y + 0.5, belt - 0.55), trim_m, bev=0.06))
        I.append(box("doorpull", (0.08, 0.35, 0.1), (s_ * (inner - 0.04), ck.eye.y + 0.95, belt - 0.3), M.CHROME() if not sports else CARBON(), bev=0.03))
        I.append(box("speaker", (0.06, 0.45, 0.45), (s_ * (inner - 0.02), ck.eye.y + 0.9, floor + 0.55), M.DARK(), bev=0.05))
    # --- rear-view mirror and sun visors under the header (a monster truck has neither)
    if not centre:
        I.append(box("mirror", (0.62, 0.1, 0.2), (0, ywt + 0.05, roof - 0.42), M.DARK(), bev=0.04, rot=(math.radians(-8), 0, 0)))
        I.append(tube("mirrorstem", [(0, ywt + 0.15, roof - 0.12), (0, ywt + 0.08, roof - 0.34)], 0.025, M.DARK(), segs=6))
    for s_ in (-1, 1):
        if not centre:
            I.append(box("visor", (1.15, 0.5, 0.06), (s_ * 1.2, ywt - 0.15, roof - 0.16), HEADLINER("#8f8a82"), bev=0.02))
    # --- style extras
    if style == "police":
        # laptop terminal on a pedestal mount by the console, angled to the driver; radio + siren head
        lm = facing((0.55, back - 0.67, belt + 0.1), (ex, ck.eye.y, ck.eye.z))
        I.append(put(box("laptopbase", (0.95, 0.65, 0.06), (0, -0.25, 0), DASH("#2a2c30"), bev=0.02), lm))
        I += screen("laptop", lm, 0.85, 0.52, ui="#1fd16b")
        I.append(tube("laptopmount", [(0.55, back - 0.57, belt - 0.15), (0.5, back - 0.47, floor + 0.3)], 0.05, M.STEEL(), segs=8))
        I.append(box("radiohead", (0.6, 0.15, 0.2), (0, back - 0.12, belt - 0.78), PANEL("#16181b"), bev=0.03))
        I += toggles("siren", frame((0, back - 0.24, belt - 0.95), (1, 0, 0), (0, 0.4, 1)), 5, pitch=0.12, color="#d8231c")
        # prisoner partition behind the front seats: steel frame, bars and a plexi window
        py = ck.hip.y - 1.35
        I.append(tube("cagefrm", [(-inner, py, floor + 0.2), (-inner, py, roof - 0.3), (inner, py, roof - 0.3), (inner, py, floor + 0.2)], 0.05, M.STEEL(), segs=8))
        for k in range(9):
            x = -inner + 0.3 + k * (2 * inner - 0.6) / 8
            I.append(tube("cagebar", [(x, py, belt - 0.2), (x, py, roof - 0.32)], 0.02, M.STEEL(), segs=6))
        I.append(box("cagelow", (2 * inner, 0.08, belt - 0.2 - floor), (0, py, floor + (belt - 0.2 - floor) / 2), M.STEEL(), bev=0.02))
        I.append(box("shotgunrack", (0.3, 0.12, 1.2), (0, py + 0.12, belt + 0.5), M.DARK(), bev=0.03))
    if style == "muscle":
        I.append(box("gaugepod", (0.5, 0.65, 0.18), (0, back - 0.37, belt - 0.6), M.CHROME(), bev=0.05, rot=(math.radians(15), 0, 0)))
        for k, dx in enumerate((-0.15, 0.0, 0.15)):
            I += dial("podg", facing((dx, back - 0.52, belt - 0.5), (ex, ck.eye.y, ck.eye.z)), 0.065, ticks=5, needle=0.4 + 0.1 * k)
    if style == "monster":
        # containment seat in the middle of the body, switch panel and kill switch, gauge pod
        I += toggles("switches", facing((0.85, ck.cpos.y + 0.15, ck.cpos.z - 0.1), (ex, ck.eye.y, ck.eye.z)), 6)
        I.append(box("killsw", (0.22, 0.12, 0.22), (-0.85, ck.cpos.y + 0.1, ck.cpos.z - 0.25), KNOB("#e01616"), bev=0.04))
        for k, dx in enumerate((-0.32, 0.0, 0.32)):
            I += dial("pod", facing((dx, ck.cpos.y + 0.55, ck.cpos.z + 0.75), (ex, ck.eye.y, ck.eye.z)), 0.12, ticks=7, needle=0.3 + 0.15 * k)
        I.append(box("podbox", (1.0, 0.25, 0.34), (0, ck.cpos.y + 0.62, ck.cpos.z + 0.75), M.DARK(), bev=0.05))
        I.append(box("floorplate", (inner * 2, 3.6, 0.1), (0, ck.eye.y + 0.4, ck.seat_top - 1.3), M.ALLOY(), bev=0.02))
    add(G, "Interior", I)
    # --- the cab seen from inside
    rear = (rows[1] - 1.6) if rear_row else (p["roof_rear"] - 0.9)
    lin = lining("lining", body, (-hw - 0.5, rear, belt - 1.6), (hw + 0.5, yc - 0.05, roof + 0.5), HEADLINER() if style not in ("sports",) else mat("SeatHeadlinerAlcantara", "#1c1a19", rough=0.9))
    add(G, "Interior", [lin])
    control(G, ck, spokes=4 if style == "pickup" else (2 if muscle else 3), flat_bottom=sports, wood=muscle,
            grip=0.06 if muscle else 0.075)


# =============================================================================================
# Commercial vehicles
# =============================================================================================
def bus(s, G, body, fz, roof, half_w):
    """Transit bus driver's area: raised platform, air-ride seat, near-flat big wheel, wraparound
    dash with gauges and switch pods, fare box, door controls, driver's barrier."""
    ck = Cockpit(s)
    I = []
    ex, ey = ck.eye.x, ck.eye.y
    plat = ck.seat_top - 1.3
    I.append(box("platform", (3.4, 3.4, plat - fz), (ex, ey + 0.6, fz + (plat - fz) / 2), mat("BusFloor", "#3c3f45", rough=0.8), bev=0.03))
    I += seat("drv", ex, ey, ck.seat_top, width=2.0, back=12, kind="bucket", material=CLOTH("#26292e"))
    I.append(cyl("airride", 0.3, ck.seat_top - 0.4 - plat, (ex, ey + 0.2, plat + (ck.seat_top - 0.4 - plat) / 2), M.DARK(), "Z", segs=14))
    # wraparound dash below the 2.6 m tall windscreen
    # the wheel lies nearly flat, so its front edge reaches cpos + r sin(tilt) forward and stays above
    # the hub height: the dash and the gauge panel start just ahead of that edge
    dz = ck.cpos.z
    front = ck.cpos.y + ck.size * math.sin(math.radians(ck.tilt)) + 0.16
    dy = front + 0.35
    I.append(box("dash", (half_w * 2 - 0.6, 1.2, 0.5), (0, front + 0.6, dz - 0.15), DASH(), bev=0.15))
    I.append(box("dashface", (3.4, 0.4, 1.1), (ex + 0.2, front + 0.2, dz - 0.4), DASH("#24262a"), bev=0.1, rot=(math.radians(-20), 0, 0)))
    toward = (ex, ey, ck.eye.z)
    for k, dx in enumerate((-0.45, 0.0, 0.45)):
        I += dial("busg", facing((ex + dx, front + 0.08, dz - 0.02), toward), 0.17, needle=0.25 + 0.15 * k)
    I += toggles("busswL", facing((ex - 1.15, front + 0.1, dz - 0.05), toward), 5)
    I += toggles("busswR", facing((ex + 1.25, front + 0.1, dz - 0.05), toward), 5)
    I += [cyl("doorbtn", 0.08, 0.06, (ex + 1.6 + k * 0.25, front + 0.45, dz + 0.12), KNOB("#1fd16b" if k == 0 else "#e01616"), "Z", segs=12, bev=0.01) for k in range(2)]
    I.append(box("farebox", (0.65, 0.65, 2.3), (ex + 2.1, ey + 0.4, fz + 1.15), M.STEEL(), bev=0.06))
    I += screen("farescreen", facing((ex + 2.1, ey + 0.1, fz + 2.05), toward), 0.4, 0.25, ui="#1fd16b", bars=2)
    I.append(box("barrier", (0.06, 2.0, 2.4), (ex + 1.55, ey - 0.7, plat + 1.9), mat("BarrierGlass", "#9fb3bf", rough=0.05, alpha=0.35), bev=0.01))
    I.append(tube("barrierframe", [(ex + 1.55, ey - 1.7, plat + 0.7), (ex + 1.55, ey - 1.7, plat + 3.1), (ex + 1.55, ey + 0.3, plat + 3.1)], 0.04, M.STEEL(), segs=6))
    I += pedals("pedal", ex + 0.1, dy - 0.2, plat + 0.45, n=2, gap=0.5)
    I.append(box("destctl", (0.5, 0.25, 0.18), (ex - 1.3, ey + 0.4, roof - 0.55), PANEL(), bev=0.04))
    I.append(box("sunblind", (2.6, 0.06, 0.6), (ex + 0.2, ck.cpos.y + 0.9, roof - 0.65), mat("BlindMesh", "#202225", rough=0.9, alpha=0.6), bev=0.01))
    add(G, "Interior", I)
    control(G, ck, spokes=2, grip=0.07)


def heavy_truck(s, G, body, cab_lo, cab_hi, hood):
    """Conventional heavy truck cab: air-ride seat, flat dash with two rows of round gauges, yellow
    (parking) and red (trailer) air-brake knobs, tall gear lever, engine doghouse between the seats."""
    ck = Cockpit(s)
    I = []
    ex, ey = ck.eye.x, ck.eye.y
    floor = cab_lo[2] + 0.35
    I += seat("drv", ex, ey, ck.seat_top, width=2.0, back=12, material=CLOTH("#3b3a37"))
    I += seat("pass", -ex, ey, ck.seat_top, width=2.0, back=12, material=CLOTH("#3b3a37"))
    for x in (ex, -ex):
        I.append(cyl("airride", 0.32, ck.seat_top - 0.4 - floor, (x, ey + 0.2, floor + (ck.seat_top - 0.4 - floor) / 2), M.DARK(), "Z", segs=14))
    dy = ck.cpos.y + 0.75
    top = ck.cpos.z + 0.2
    I.append(box("dash", (cab_hi[0] - cab_lo[0] - 0.8, 0.9, top - floor), (0, dy + 0.15, floor + (top - floor) / 2), DASH("#2a2b2e"), bev=0.12))
    I.append(box("dashpanel", (3.1, 0.12, 0.9), (ex + 0.4, dy - 0.32, top - 0.48), PANEL("#1b1c1f"), bev=0.04))
    toward = (ex, ey, ck.eye.z)
    for row, z in enumerate((top - 0.25, top - 0.68)):
        for k in range(5):
            I += dial("tg", facing((ex - 0.75 + k * 0.4 + 0.4, dy - 0.39, z), toward), 0.15 if row else 0.17, ticks=7, needle=0.2 + 0.12 * k)
    for k, (col, shape) in enumerate((("#f2c21a", 4), ("#d8231c", 8))):
        I.append(cyl("airknob", 0.11, 0.16, (ex + 1.85 + k * 0.32, dy - 0.45, top - 0.55), KNOB(col), "Y", segs=shape, bev=0.01))
    I.append(tube("gearlever", [(ex + 1.05, ey + 1.0, floor + 0.2), (ex + 0.95, ey + 0.85, floor + 1.7)], 0.05, M.STEEL(), segs=8))
    I.append(lathe("gearknob", [(0, 0), (0.12, 0.03), (0.14, 0.18), (0.1, 0.3), (0, 0.32)], mat("ShiftKnob", "#101011", rough=0.2), segs=14, axis="Z", loc=(ex + 0.95, ey + 0.85, floor + 1.68)))
    I.append(box("doghouse", (1.4, 2.2, 1.0), (0, dy - 1.4, floor + 0.5), SOFT("#3a3a3c"), bev=0.3, segs=3))
    I += pedals("pedal", ex + 0.1, dy - 0.25, floor + 0.45, n=3, gap=0.4)
    I.append(box("visor", (2.2, 0.5, 0.06), (ex, cab_hi[1] - 0.9, cab_hi[2] - 0.35), HEADLINER("#5b5853"), bev=0.02))
    I.append(box("cbradio", (0.7, 0.4, 0.2), (0, ey + 0.6, cab_hi[2] - 0.4), PANEL(), bev=0.04))
    I.append(box("floor", (cab_hi[0] - cab_lo[0] - 0.6, cab_hi[1] - cab_lo[1] - 0.6, 0.1), (0, (cab_lo[1] + cab_hi[1]) / 2, floor - 0.05), RUBBER_MAT(), bev=0.02))
    add(G, "Interior", I)
    add(G, "Interior", [lining("lining", body, cab_lo, (cab_hi[0], cab_hi[1] - 0.05, cab_hi[2]), HEADLINER("#77736b"))])
    control(G, ck, spokes=4, grip=0.08)


def armoured(s, G, body, cab_lo, cab_hi):
    """MRAP-style armoured cab: steel dash with switch panels and a display, radio rack between the
    seats, grab handles, four-point harness seats, small thick windscreen panes (cut through)."""
    ck = Cockpit(s)
    I = []
    ex, ey = ck.eye.x, ck.eye.y
    floor = cab_lo[2] + 0.3
    green = mat("ArmourInterior", "#59614f", rough=0.75)
    green_lining = mat("LiningArmour", "#6a7360", rough=0.75)
    I += seat("drv", ex, ey, ck.seat_top, width=1.9, back=10, kind="racing", material=CLOTH("#2e3328"))
    I += seat("cmd", -ex, ey, ck.seat_top, width=1.9, back=10, kind="racing", material=CLOTH("#2e3328"))
    I += harness("harness", ex, ey, ck.seat_top, color="#3d4a2b")
    dy = ck.cpos.y + 0.7
    top = ck.cpos.z + 0.15
    I.append(box("dash", (2 * cab_hi[0] - 0.8, 0.9, top - floor), (0, dy + 0.2, floor + (top - floor) / 2), green, bev=0.08))
    toward = (ex, ey, ck.eye.z)
    for k in range(3):
        I += toggles("sw", facing((ex - 0.6 + k * 0.7, dy - 0.28, top - 0.1), toward), 4, color="#9aa0a6")
    I += dial("speedo", facing((ex, dy - 0.3, top - 0.45), toward), 0.2, needle=0.3)
    I += screen("bft", facing((-ex * 0.2, dy - 0.25, top + 0.25), toward), 0.7, 0.5, ui="#1fd16b")
    I.append(box("radiorack", (0.9, 1.6, 1.6), (0, ey - 0.4, floor + 0.8), PANEL("#2d3227"), bev=0.04))
    for k in range(3):
        I.append(box("radio", (0.85, 0.08, 0.38), (0, ey + 0.42, floor + 0.4 + k * 0.48), PANEL("#1c1f1a"), bev=0.03))
        I += [cyl("rknob", 0.05, 0.06, (dx, ey + 0.47, floor + 0.4 + k * 0.48), M.DARK(), "Y", segs=10, bev=0) for dx in (-0.25, 0.25)]
    for s_ in (-1, 1):
        I.append(tube("grab", [(s_ * 1.5, ey - 0.6, cab_hi[2] - 0.25), (s_ * 1.5, ey - 0.6, cab_hi[2] - 0.45), (s_ * 1.5, ey + 0.6, cab_hi[2] - 0.45), (s_ * 1.5, ey + 0.6, cab_hi[2] - 0.25)], 0.04, M.STEEL(), segs=6))
    I += pedals("pedal", ex + 0.05, dy - 0.25, floor + 0.45, n=2)
    I.append(box("floor", (2 * cab_hi[0] - 0.6, cab_hi[1] - cab_lo[1] - 0.4, 0.1), (0, (cab_lo[1] + cab_hi[1]) / 2, floor - 0.05), M.STEEL(), bev=0.02))
    add(G, "Interior", I)
    add(G, "Interior", [lining("lining", body, cab_lo, cab_hi, green_lining, inset=0.08)])
    control(G, ck, spokes=4, grip=0.08)


# =============================================================================================
# Aircraft
# =============================================================================================
def light_aircraft(s, G, body, cz, panel_y, cabin_lo, cabin_hi):
    """Four-seat light aircraft: glare shield, six-pack in front of the left seat (airspeed,
    attitude, altimeter / turn, heading, VSI), engine gauges right, radio stack centre, dual yokes,
    black throttle and red mixture knobs, rudder pedals, front and rear seats."""
    ck = Cockpit(s)
    I = []
    ex, ey = ck.eye.x, ck.eye.y
    floor = cz - 0.75
    toward = (ex, ey, ck.eye.z)
    ptop = ck.cpos.z + 0.55
    I.append(box("panel", (3.1, 0.35, ptop - (cz - 0.3)), (0, panel_y, (ptop + cz - 0.3) / 2), PANEL("#2a2c30"), bev=0.06))
    I.append(box("glareshield", (3.1, 0.6, 0.1), (0, panel_y - 0.1, ptop + 0.02), M.DARK(), bev=0.04, rot=(math.radians(-6), 0, 0)))
    for row, z in enumerate((ptop - 0.28, ptop - 0.72)):
        for k in range(3):
            I += dial("six", facing((ex - 0.42 + k * 0.42, panel_y - 0.19, z), toward), 0.17, needle=0.15 + 0.2 * k + row * 0.1)
    for k in range(4):
        I += dial("eng", facing((0.45 + k * 0.28, panel_y - 0.19, ptop - 0.32), toward), 0.1, ticks=5, needle=0.3 + 0.1 * k)
    I += screen("gps", facing((0.15, panel_y - 0.19, ptop - 0.78), toward), 0.55, 0.32, ui="#1fd16b", bars=3)
    I.append(box("radiostack", (0.6, 0.06, 0.4), (0.15, panel_y - 0.2, cz - 0.05), PANEL("#141518"), bev=0.03))
    for k, col in enumerate(("#111214", "#d8231c")):   # throttle (black), mixture (red)
        I.append(tube("plunger", [(-0.1 + k * 0.22, panel_y - 0.18, cz - 0.15), (-0.1 + k * 0.22, panel_y - 0.4, cz - 0.15)], 0.025, M.CHROME(), segs=6))
        I.append(cyl("knob", 0.08, 0.1, (-0.1 + k * 0.22, panel_y - 0.45, cz - 0.15), KNOB(col), "Y", segs=12, bev=0.02))
    I.append(lathe("compass", [(0, 0), (0.16, 0), (0.16, 0.18), (0.1, 0.25), (0, 0.25)], M.DARK(), segs=16, axis="Z", loc=(0, panel_y - 0.2, ptop + 0.07)))
    # right-seat yoke (static) mirrors the pilot's
    m2 = wheel_frame((-ck.cpos.x, ck.cpos.y, ck.cpos.z), ck.tilt)
    I += yoke("yoke2", m2, ck.size)
    I.append(put(cyl("yokeshaft2", 0.07, 1.4, (0, -0.15, -0.8), M.CHROME(), "Z", segs=12, bev=0), m2))
    for x in (ex, -ex):
        I += seat("seat", x, ey, ck.seat_top, width=1.35, back=12, material=LEATHER("#3a3632"), back_h=2.0)
        I += seat("rear", x, ey - 2.3, ck.seat_top - 0.05, width=1.35, back=14, material=LEATHER("#3a3632"), back_h=1.9)
        I += pedals("rudder", x, panel_y - 0.9, floor + 0.35, n=2, gap=0.45)
    I.append(box("floor", (cabin_hi[0] - cabin_lo[0], cabin_hi[1] - cabin_lo[1], 0.1), (0, (cabin_lo[1] + cabin_hi[1]) / 2, floor), mat("SeatCarpet", "#2b2826", rough=0.95), bev=0.02))
    add(G, "Interior", I)
    add(G, "Interior", [lining("lining", body, cabin_lo, (cabin_hi[0], cabin_hi[1], cz + 1.4), HEADLINER("#b4b0a8"))])
    control(G, ck)


def flight_deck(s, G, body, deck_z, ws_y, half_w, ceil):
    """Four-engine transport flight deck: pilot and co-pilot seats with the flight engineer's seat
    behind, glass panel (six displays), glare shield with autopilot panel, centre pedestal with four
    power levers, overhead panel of switch rows, dual yokes and rudder pedals, rear bulkhead."""
    ck = Cockpit(s)
    I = []
    ex, ey = ck.eye.x, ck.eye.y
    toward = (ex, ey, ck.eye.z)
    py = ck.cpos.y + 0.75
    ptop = ck.cpos.z + 0.35
    I.append(box("deck", (2 * half_w - 0.6, ws_y - ey + 4.5, 0.15), (0, (ws_y + ey - 4.5) / 2, deck_z), mat("SeatCarpet", "#2a2b2d", rough=0.95), bev=0.02))
    I.append(box("panel", (2 * half_w - 1.0, 0.4, ptop - deck_z - 0.6), (0, py, deck_z + 0.6 + (ptop - deck_z - 0.6) / 2), PANEL("#3a3f45"), bev=0.06))
    I.append(box("glare", (2 * half_w - 1.0, 0.7, 0.14), (0, py - 0.1, ptop + 0.04), M.DARK(), bev=0.05))
    I += toggles("ap", facing((0, py - 0.46, ptop + 0.04), toward), 7, pitch=0.13)
    for k, x in enumerate((ex - 0.5, ex + 0.5, -0.45, 0.45, -ex - 0.5, -ex + 0.5)):
        I += screen("mfd", facing((x, py - 0.22, ptop - 0.42), toward), 0.6, 0.6, ui="#2b7fe0" if k % 2 == 0 else "#1fd16b")
    I.append(box("pedestal", (1.0, 2.2, 1.1), (0, py - 1.3, deck_z + 0.55), PANEL("#2f3338"), bev=0.08))
    for k in range(4):
        x = -0.36 + k * 0.24
        I.append(tube("powerlever", [(x, py - 1.0, deck_z + 1.1), (x, py - 1.25, deck_z + 1.55)], 0.03, M.CHROME(), segs=6))
        I.append(box("powerknob", (0.14, 0.14, 0.12), (x, py - 1.27, deck_z + 1.6), KNOB("#e8e8e4"), bev=0.04))
    I.append(box("overhead", (2.6, 2.4, 0.25), (0, ey + 0.3, ceil - 0.2), PANEL("#3a3f45"), bev=0.06))
    for k in range(5):
        I += toggles("ohsw", frame((0, ey + 1.2 - k * 0.45, ceil - 0.34), (1, 0, 0), (0, 1, 0)), 8, pitch=0.25)
    m2 = wheel_frame((-ck.cpos.x, ck.cpos.y, ck.cpos.z), ck.tilt)
    I += yoke("yoke2", m2, ck.size)
    for x in (ex, -ex):
        I.append(put(cyl("column", 0.1, 1.4, (0, -0.15, -0.8), M.DARK(), "Z", segs=12, bev=0), wheel_frame((x, ck.cpos.y, ck.cpos.z), ck.tilt)))
        I += seat("seat", x, ey, ck.seat_top, width=1.7, back=12, material=LEATHER("#2f2b28"))
        I += pedals("rudder", x, py - 0.8, deck_z + 0.4, n=2, gap=0.5)
    I += seat("fe", 0.0, ey - 2.4, ck.seat_top, width=1.6, back=10, material=LEATHER("#2f2b28"))
    I.append(box("bulkhead", (2 * half_w - 0.4, 0.12, ceil - deck_z), (0, ey - 3.6, deck_z + (ceil - deck_z) / 2), PANEL("#5b6067"), bev=0.02))
    I.append(box("bulkdoor", (1.4, 0.14, 3.2), (0, ey - 3.58, deck_z + 1.6), M.DARK(), bev=0.03))
    add(G, "Interior", I)
    add(G, "Interior", [lining("lining", body, (-half_w - 1, ey - 3.7, deck_z - 0.5), (half_w + 1, ws_y + 1.8, ceil + 1.0), mat("LiningPanel", "#8d939a", rough=0.6), skip_down=False)])
    control(G, ck)


def helicopter(s, G, body, cabin_lo, cabin_hi):
    """Light helicopter: pilot in the right seat, cyclic between the knees, collective lever to the
    left of each seat, anti-torque pedals, T-shaped instrument console under the bubble."""
    ck = Cockpit(s)
    I = []
    ex, ey = ck.eye.x, ck.eye.y
    floor = cabin_lo[2] + 0.4
    toward = (ex, ey, ck.eye.z)
    cy = ey + 2.0
    I.append(box("console", (2.6, 0.5, 0.9), (0, cy, floor + 1.55), PANEL("#2a2c30"), bev=0.08, rot=(math.radians(-25), 0, 0)))
    I.append(box("pedestal", (0.8, 1.2, 1.2), (0, cy - 0.6, floor + 0.6), PANEL("#2a2c30"), bev=0.08))
    for k in range(5):
        x = -0.9 + k * 0.45
        I += dial("hg", facing((x, cy - 0.28, floor + 1.62), toward), 0.15, needle=0.2 + 0.12 * k)
    I += toggles("hsw", facing((0, cy - 0.85, floor + 1.1), toward), 4)
    for x in (ex, -ex):
        I += seat("seat", x, ey, ck.seat_top, width=1.45, back=10, material=CLOTH("#2a2a2c"), back_h=2.1)
        I += pedals("pedal", x, ey + 1.6, floor + 0.3, n=2, gap=0.5)
        I.append(tube("cyclic", [(x, ck.right.y + 0.1, floor + 0.1), (x, ck.right.y + 0.05, ck.right.z - 0.15)], 0.045, M.DARK(), segs=8))
        I.append(box("cyclicgrip", (0.16, 0.16, 0.3), (x, ck.right.y, ck.right.z), RUBBER_MAT(), bev=0.05))
        cx = x - 0.8     # collective: left hand, beside each seat
        I.append(tube("collective", [(cx, ey - 0.4, floor + 0.3), (cx, ck.left.y, ck.left.z)], 0.05, M.DARK(), segs=8))
        I.append(cyl("collectivegrip", 0.08, 0.35, (cx, ck.left.y + 0.1, ck.left.z + 0.05), RUBBER_MAT(), "Y", segs=10, bev=0.02))
    I.append(box("floor", (cabin_hi[0] - cabin_lo[0] - 0.6, 6.0, 0.1), (0, ey + 1.0, floor - 0.05), RUBBER_MAT(), bev=0.02))
    add(G, "Interior", I)
    add(G, "Interior", [lining("lining", body, cabin_lo, cabin_hi, HEADLINER("#5c5b58"))])


# =============================================================================================
# Train, bulldozer, tank, kart, rocket sled
# =============================================================================================
def steam_cab(s, G, cab_lo, cab_hi, fb_top, blue, black):
    """Hollow steam-locomotive cab. The rear of the firebox is the cab's front sheet (the backhead):
    firebox door, steam pressure gauge, two water gauge glasses, injector valves. Above it, front
    windows either side of the boiler look forward along it. The engineer sits on a seat box on the
    right (US practice) with the regulator (throttle) lever and brake valve in reach and the
    Johnson-bar reverser at his right side; the fireman's seat box is on the left. Side windows,
    open rear to the tender, wooden floor."""
    ck = Cockpit(s)
    x0, y0, z0 = cab_lo
    x1, y1, z1 = cab_hi
    W, I = [], []
    t = 0.18
    floor = z0 + 0.6
    fz0, fz1 = fb_top + 0.05, z1 - 0.28          # front windows: above the firebox, under the roof
    sz0, sz1 = ck.eye.z - 1.25, ck.eye.z + 0.55   # side windows
    yf = y1 - t / 2
    # front sheet: black backhead below the windows, blue band, centre post, glass either side
    W.append(box("backhead", (2 * x1, t, fz0 - z0), (0, yf, (z0 + fz0) / 2), black, bev=0.03))
    W.append(box("front_top", (2 * x1, t, z1 - fz1), (0, yf, (fz1 + z1) / 2), blue, bev=0.03))
    W.append(box("front_post", (1.6, t, fz1 - fz0), (0, yf, (fz0 + fz1) / 2), blue, bev=0.03))
    for sx in (-1, 1):
        W.append(box("front_edge", (0.35, t, fz1 - fz0), (sx * (x1 - 0.175), yf, (fz0 + fz1) / 2), blue, bev=0.03))
        gx0, gx1 = 0.8, x1 - 0.35
        G["Glass"].append(box("frontglass", (gx1 - gx0, 0.05, fz1 - fz0), (sx * (gx0 + gx1) / 2, yf, (fz0 + fz1) / 2), M.GLASS(), bev=0.01))
        I.append(tube("frontframe", [(sx * gx0, yf - 0.12, fz0), (sx * gx0, yf - 0.12, fz1), (sx * gx1, yf - 0.12, fz1), (sx * gx1, yf - 0.12, fz0), (sx * gx0, yf - 0.12, fz0)], 0.045, BRASS(), segs=6))
        # side walls with a long window and the open door gap at the rear
        x = sx * (x1 - t / 2)
        W.append(box("side_low", (t, y1 - y0, sz0 - z0), (x, (y0 + y1) / 2, (z0 + sz0) / 2), blue, bev=0.03))
        W.append(box("side_top", (t, y1 - y0, z1 - sz1), (x, (y0 + y1) / 2, (sz1 + z1) / 2), blue, bev=0.03))
        for yy in (y1 - 0.25, y1 - 3.2, y0 + 2.2):
            W.append(box("side_post", (t, 0.45, sz1 - sz0), (x, yy, (sz0 + sz1) / 2), blue, bev=0.03))
        G["Glass"].append(box("sideglass", (0.05, 2.5, sz1 - sz0), (x, y1 - 1.7, (sz0 + sz1) / 2), M.GLASS(), bev=0.01))
        W.append(box("side_rear", (t, 0.9, z1 - z0), (x, y0 + 0.45, (z0 + z1) / 2), blue, bev=0.03))
    W.append(box("cabfloor", (2 * x1, y1 - y0, 0.2), (0, (y0 + y1) / 2, floor - 0.1), mat("Deck", "#4b3a2a", rough=0.85), bev=0.02))
    G["Body"] += W
    I.append(inner_box("roofliner", (x0 + 0.2, y0, z1 - 0.05), (x1 - 0.2, y1 - 0.2, z1 + 0.6), mat("CabRoofInside", "#5a4a38", rough=0.85), open_faces=("bottom", "front", "back", "left", "right")))
    # backhead fittings
    by = y1 - t - 0.04
    toward = (ck.eye.x, ck.eye.y, ck.eye.z)
    I.append(box("fireboxdoor", (1.2, 0.14, 0.9), (0, by - 0.05, floor + 1.15), M.STEEL(), bev=0.06))
    I.append(tube("doorhandle", [(-0.35, by - 0.18, floor + 1.15), (0.35, by - 0.18, floor + 1.15)], 0.04, BRASS(), segs=6))
    I.append(box("doorchain", (0.05, 0.05, 1.0), (0.7, by - 0.1, floor + 1.9), M.STEEL(), bev=0))
    I += dial("steam", facing((0.0, by - 0.05, fz0 - 0.55), toward), 0.32, needle=0.62, ring=BRASS(), face=mat("GaugeFaceWhite", "#efe9dc", rough=0.4))
    for sx in (-1.1, 1.1):   # water gauge glasses
        I.append(cyl("waterglass", 0.06, 0.85, (sx, by - 0.12, fz0 - 0.95), mat("WaterGlass", "#9fc6d6", rough=0.05, alpha=0.6), "Z", segs=10, bev=0))
        for dz_ in (-0.48, 0.48):
            I.append(box("gaugecock", (0.18, 0.2, 0.12), (sx, by - 0.12, fz0 - 0.95 + dz_), BRASS(), bev=0.03))
    for k in range(4):   # injector, blower and steam valves
        I.append(cyl("valve", 0.11, 0.05, (-1.9 + k * 1.25, by - 0.08, fz0 - 0.25), BRASS(), "Y", segs=12, bev=0.01))
    r = ck.right
    piv = Vector((0.9, by - 0.12, fz0 - 0.2))
    I.append(cyl("regpivot", 0.13, 0.22, tuple(piv), BRASS(), "Y", segs=12, bev=0.02))
    I.append(tube("regulator", [piv, r], 0.045, M.STEEL(), segs=8))
    I.append(cyl("reggrip", 0.07, 0.3, tuple(r), mat("WoodGrip", "#5a3418", rough=0.5), "X", segs=10, bev=0.02))
    lft = ck.left
    I.append(box("brakevalve", (0.35, 0.3, 0.3), (lft.x, by - 0.15, lft.z - 0.1), BRASS(), bev=0.05))
    I.append(tube("brakehandle", [(lft.x, by - 0.25, lft.z - 0.05), lft], 0.035, M.STEEL(), segs=6))
    I.append(tube("johnsonbar", [(x1 - 0.75, ck.eye.y + 0.7, floor + 0.1), (x1 - 0.8, ck.eye.y + 0.35, floor + 2.3)], 0.06, M.STEEL(), segs=8))
    I.append(box("quadrant", (0.1, 1.2, 0.3), (x1 - 0.62, ck.eye.y + 0.65, floor + 0.3), M.STEEL(), bev=0.03))
    for sx in (1, -1):   # seat boxes: engineer right, fireman left
        sxx = ck.eye.x if sx > 0 else -ck.eye.x
        I.append(box("seatbox", (1.6, 1.6, ck.seat_top - floor), (sxx, ck.eye.y + 0.2, floor + (ck.seat_top - floor) / 2), mat("WoodBox", "#6b4a2b", rough=0.75), bev=0.04))
        I.append(box("seatpad", (1.5, 1.5, 0.18), (sxx, ck.eye.y + 0.2, ck.seat_top - 0.05), LEATHER("#2b1a12"), bev=0.06))
        I.append(box("armrest", (0.5, 1.6, 0.2), (sx * (x1 - 0.45), ck.eye.y + 0.4, sz0 - 0.05), mat("WoodBox", "#6b4a2b", rough=0.75), bev=0.05))
    add(G, "Interior", I)


def dozer_cab(s, G, cab_lo, cab_hi):
    """ROPS dozer cab: air-suspension seat with armrest consoles, left joystick (steering and
    direction), right joystick (blade), touchscreen display on the right front post, decelerator."""
    ck = Cockpit(s)
    I = []
    ex, ey = ck.eye.x, ck.eye.y
    floor = cab_lo[2] + 0.25
    I += seat("seat", ex, ey, ck.seat_top, width=2.0, back=10, material=CLOTH("#262729"))
    I.append(cyl("seatbase", 0.45, ck.seat_top - 0.4 - floor, (ex, ey + 0.1, floor + (ck.seat_top - 0.4 - floor) / 2), M.DARK(), "Z", segs=14))
    toward = (ex, ey, ck.eye.z)
    for g in (ck.right, ck.left):
        sgn = 1 if g.x > ex else -1
        I.append(box("armconsole", (0.6, 1.6, 0.35), (g.x + sgn * 0.08, ey + 0.4, g.z - 0.55), mat("DozerConsole", "#2a2b2e", rough=0.6), bev=0.08))
        I.append(tube("stickshaft", [(g.x, g.y + 0.05, g.z - 0.4), (g.x, g.y, g.z - 0.1)], 0.04, M.DARK(), segs=8))
        I.append(lathe("joystick", [(0, 0), (0.1, 0.02), (0.11, 0.2), (0.08, 0.32), (0, 0.34)], RUBBER_MAT(), segs=12, axis="Z", loc=(g.x, g.y, g.z - 0.15)))
    I += screen("display", facing((cab_hi[0] - 0.6, cab_hi[1] - 0.45, ck.eye.z - 0.7), toward), 0.6, 0.42, ui="#f0b60a")
    I.append(box("decel", (0.3, 0.5, 0.08), (ex - 0.4, ey + 1.8, floor + 0.2), RUBBER_MAT(), bev=0.03, rot=(math.radians(-25), 0, 0)))
    I.append(box("floor", (cab_hi[0] - cab_lo[0] - 0.5, cab_hi[1] - cab_lo[1] - 0.5, 0.08), (0, (cab_lo[1] + cab_hi[1]) / 2, floor), RUBBER_MAT(), bev=0.02))
    I.append(inner_box("roofliner", (cab_lo[0] + 0.1, cab_lo[1] + 0.1, cab_hi[2] - 0.12), (cab_hi[0] - 0.1, cab_hi[1] - 0.1, cab_hi[2]), HEADLINER("#77787a"), open_faces=("bottom", "front", "back", "left", "right")))
    add(G, "Interior", I)


def tank_driver(s, G, hatch_xy, hull_top):
    """Driver's position head-out of the open hatch: hatch ring, lid swung open, three periscopes
    ahead of the hatch, raised seat and T-bar handlebars inside."""
    ck = Cockpit(s)
    I = []
    hx, hy = hatch_xy
    dark = mat("OliveDark", "#3a4128", rough=0.7)
    I.append(lathe("hatchring", [(0.95, 0), (1.15, 0), (1.15, 0.18), (0.95, 0.18)], dark, segs=28, axis="Z", loc=(hx, hy, hull_top - 0.02), close=True))
    lid = cyl("hatchlid", 1.0, 0.14, (0, 0, 0), dark, "Z", segs=24)
    lid.location = (0, 0, 0)
    put(lid, Matrix.Translation((hx, hy - 1.15, hull_top + 0.95)) @ Matrix.Rotation(math.radians(80), 4, "X"))
    I.append(lid)
    for k, a in enumerate((-35, 0, 35)):
        d = Vector((math.sin(math.radians(a)), math.cos(math.radians(a)), 0))
        c = Vector((hx, hy, hull_top + 0.12)) + d * 1.35
        I.append(box("periscope", (0.55, 0.32, 0.28), tuple(c), dark, bev=0.05, rot=(0, 0, -math.radians(a))))
        I.append(box("prism", (0.45, 0.04, 0.16), tuple(c + d * 0.17 + Vector((0, 0, 0.02))), mat("Prism", "#22343a", rough=0.05, metal=0.6), bev=0.01, rot=(0, 0, -math.radians(a))))
    I += seat("seat", ck.eye.x, ck.eye.y, ck.seat_top, width=1.6, back=20, material=CLOTH("#2e3328"), back_h=1.8)
    I.append(inner_box("well", (hx - 1.0, hy - 1.0, ck.seat_top - 0.6), (hx + 1.0, hy + 1.6, hull_top - 0.05), mat("TankInterior", "#d8d6cc", rough=0.8), open_faces=("top",)))
    add(G, "Interior", I)
    control(G, ck)


def kart(s, G):
    ck = Cockpit(s)
    control(G, ck, spokes=3, grip=0.06, shroud=False)


def sled_seat(s, G):
    """Open seat on top of the sled after Sonic Wind No. 1: jet-style seat, harness, hand grips."""
    ck = Cockpit(s)
    I = []
    I += seat("seat", ck.eye.x, ck.eye.y, ck.seat_top, width=1.8, back=12, kind="racing", material=LEATHER("#202022"), back_h=2.4)
    I += harness("harness", ck.eye.x, ck.eye.y, ck.seat_top, color="#e8a70f")
    I.append(box("headbox", (1.2, 0.5, 0.8), (ck.eye.x, ck.eye.y - 1.25, ck.seat_top + 2.6), LEATHER("#202022"), bev=0.15))
    for g in (ck.right, ck.left):
        I.append(tube("gripbar", [(g.x, g.y + 0.6, ck.seat_top - 0.5), (g.x, g.y + 0.1, g.z - 0.1)], 0.05, M.STEEL(), segs=8))
        I.append(cyl("grip", 0.08, 0.35, (g.x, g.y, g.z), RUBBER_MAT(), "Z", segs=12, bev=0.02))
    I.append(box("footrest", (1.6, 0.3, 0.1), (0, ck.eye.y + 2.2, ck.seat_top - 0.6), M.STEEL(), bev=0.03, rot=(math.radians(-30), 0, 0)))
    add(G, "Interior", I)
