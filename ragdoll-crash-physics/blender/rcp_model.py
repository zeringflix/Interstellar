"""Modelling toolkit for the RAGDOLL CRASH PHYSICS vehicles (Blender 4.x / 5.x, bpy).

Everything is real geometry, generated procedurally:
  loft()      skins a list of cross-section rings (car bodies, fuselages, wings, turrets)
  lathe()     revolves a profile (tyres, rims, nozzles, domes, chimneys)
  tube()      pipe along a polyline / smooth curve (roll bars, frames, skids, handrails)
  project()   drops a flat outline onto a body with ray casts so lights, grilles, door seams,
              stripes and badges follow the real curved surface
  wheel()     tyre with sidewall + tread grooves, rim barrel, spokes, lugs, brake disc, caliper
Blender axes: +X right, +Y FRONT of the vehicle, +Z up, 1 unit = 1 Roblox stud. z = 0 is the ground.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

TAU = math.tau
_mats = {}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()


def srgb(h):
    h = h.lstrip("#")
    return tuple((int(h[i:i + 2], 16) / 255) ** 2.2 for i in (0, 2, 4))


def mat(name, color, rough=0.5, metal=0.0, alpha=1.0, emit=0.0, coat=0.0, spec=0.5):
    key = (name, color)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    rgb = srgb(color)
    b.inputs["Base Color"].default_value = rgb + (1,)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    for nm, val in (("Coat Weight", coat), ("Coat Roughness", 0.05), ("Specular IOR Level", spec)):
        if nm in b.inputs:
            b.inputs[nm].default_value = val
    if emit:
        b.inputs["Emission Color"].default_value = rgb + (1,)
        b.inputs["Emission Strength"].default_value = emit
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
        if "Transmission Weight" in b.inputs:
            b.inputs["Transmission Weight"].default_value = 0.0
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    m.diffuse_color = rgb + (alpha,)
    _mats[key] = m
    return m


# ---- shared material library ------------------------------------------------
def paint(color):
    return mat("Paint", color, rough=0.28, metal=0.25, coat=1.0)


def matte(color, rough=0.75):
    return mat("Matte", color, rough=rough)


GLASS = lambda: mat("Glass", "#1d2b33", rough=0.04, alpha=0.42, spec=1.0)
RUBBER = lambda: mat("Rubber", "#0f0f10", rough=0.88)
CHROME = lambda: mat("Chrome", "#e8eaee", rough=0.12, metal=1.0)
ALLOY = lambda: mat("Alloy", "#b9bec6", rough=0.3, metal=1.0)
STEEL = lambda: mat("Steel", "#6d737c", rough=0.45, metal=0.9)
DARK = lambda: mat("DarkTrim", "#17181b", rough=0.6)
PLASTIC = lambda: mat("Plastic", "#26282c", rough=0.7)
INTERIOR = lambda: mat("Interior", "#2b2623", rough=0.85)
SEAT = lambda: mat("Seat", "#4a4039", rough=0.9)
HEADLIGHT = lambda: mat("HeadLamp", "#d5dbe2", rough=0.07, metal=0.85, emit=0.05)
TAILLIGHT = lambda: mat("TailLamp", "#b80f16", rough=0.15, emit=0.35)
AMBER = lambda: mat("Amber", "#ff8c12", rough=0.2, emit=0.3)
PLATE = lambda: mat("Plate", "#f2f2ee", rough=0.5)


def link(name, me, material=None):
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if material is not None:
        me.materials.append(material)
    return ob


def from_bm(name, bm, material=None, smooth=True):
    me = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    return link(name, me, material)


def select(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def apply_mods(ob):
    select([ob])
    for m in list(ob.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except RuntimeError:
            ob.modifiers.remove(m)


def subsurf(ob, levels=2, apply=True):
    m = ob.modifiers.new("sub", "SUBSURF")
    m.levels = m.render_levels = levels
    if apply:
        apply_mods(ob)
    return ob


def bevel(ob, width=0.03, segments=2, angle=35):
    m = ob.modifiers.new("bev", "BEVEL")
    m.width, m.segments, m.limit_method, m.angle_limit = width, segments, "ANGLE", math.radians(angle)
    m.harden_normals = True
    apply_mods(ob)
    return ob


def weighted_normals(ob):
    try:
        m = ob.modifiers.new("wn", "WEIGHTED_NORMAL")
        m.keep_sharp = True
        apply_mods(ob)
    except Exception:
        pass
    return ob


def solidify(ob, thickness, offset=-1):
    m = ob.modifiers.new("sol", "SOLIDIFY")
    m.thickness, m.offset = thickness, offset
    apply_mods(ob)
    return ob


def boolean(target, cutter, op="DIFFERENCE", keep=False):
    m = target.modifiers.new("bool", "BOOLEAN")
    m.operation, m.object, m.solver = op, cutter, "EXACT"
    apply_mods(target)
    if not keep:
        bpy.data.objects.remove(cutter)
    return target


def join(objs, name):
    objs = [o for o in objs if o is not None]
    select(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = name
    return ob


def set_origin(ob, world):
    bpy.context.scene.cursor.location = Vector(world)
    select([ob])
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return ob


def apply_xf(ob):
    select([ob])
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def place(ob, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    ob.location, ob.rotation_euler, ob.scale = loc, rot, scale
    return apply_xf(ob)


def mirror_x(ob, name=None):
    """Duplicate mirrored across the YZ plane (left/right pairs)."""
    dup = ob.copy()
    dup.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(dup)
    dup.scale.x = -1
    apply_xf(dup)
    bm = bmesh.new()
    bm.from_mesh(dup.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(dup.data)
    bm.free()
    if name:
        dup.name = name
    return dup


def tris(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


# ---- primitives ---------------------------------------------------------------
def box(name, size, loc, material, bev=0.04, rot=(0, 0, 0), segs=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    b = min(bev, min(size) * 0.45)
    if b > 0.004:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=b, segments=segs, profile=0.6, affect="EDGES")
    ob = from_bm(name, bm, material)
    return place(ob, loc, rot)


def cyl(name, radius, depth, loc, material, axis="X", segs=32, bev=0.03, r2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=radius, radius2=radius if r2 is None else r2, depth=depth)
    caps = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6]
    b = min(bev, depth * 0.3, radius * 0.3)
    if b > 0.004:
        bmesh.ops.bevel(bm, geom=caps, offset=b, segments=2, affect="EDGES")
    ob = from_bm(name, bm, material)
    rot = {"X": (0, math.pi / 2, 0), "Y": (-math.pi / 2, 0, 0), "Z": (0, 0, 0)}[axis]
    return place(ob, loc, rot)


def lathe(name, profile, material, segs=48, axis="X", loc=(0, 0, 0), close=False, cap=True):
    """Revolve profile [(radius, height), ...] around the local Z axis, then orient to `axis`."""
    bm = bmesh.new()
    rings = []
    for r, h in profile:
        rings.append([bm.verts.new((r * math.cos(TAU * i / segs), r * math.sin(TAU * i / segs), h)) for i in range(segs)])
    for a, b in zip(rings, rings[1:] + ([rings[0]] if close else [])):
        for i in range(segs):
            j = (i + 1) % segs
            try:
                bm.faces.new((a[i], a[j], b[j], b[i]))
            except ValueError:
                pass
    if not close and cap:
        for ring in (rings[0], rings[-1]):
            if (ring[0].co.x ** 2 + ring[0].co.y ** 2) > 1e-8:
                try:
                    bm.faces.new(ring)
                except ValueError:
                    pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    ob = from_bm(name, bm, material)
    rot = {"X": (0, math.pi / 2, 0), "Y": (-math.pi / 2, 0, 0), "Z": (0, 0, 0)}[axis]
    return place(ob, loc, rot)


def loft(name, rings, material=None, cap=True, closed=True, mat_fn=None, materials=None, smooth=True):
    """Skin consecutive rings (lists of 3-tuples, equal length). mat_fn(ring_i, point_j) -> material slot."""
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in ring] for ring in rings]
    n = len(rings[0])
    for i in range(len(vr) - 1):
        for j in range(n if closed else n - 1):
            k = (j + 1) % n
            try:
                f = bm.faces.new((vr[i][j], vr[i][k], vr[i + 1][k], vr[i + 1][j]))
                if mat_fn:
                    f.material_index = mat_fn(i, j)
            except ValueError:
                pass
    if cap and closed:
        for ring in (vr[0], vr[-1]):
            try:
                bm.faces.new(ring)
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    ob = from_bm(name, bm, None, smooth)
    for m in materials or ([material] if material else []):
        ob.data.materials.append(m)
    return ob


def smooth_path(points, per=6):
    """Catmull-Rom resample of a polyline."""
    pts = [Vector(p) for p in points]
    out = []
    for i in range(len(pts) - 1):
        p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, len(pts) - 1)]
        for s in range(per):
            t = s / per
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(pts[-1])
    return out


def tube(name, points, radius, material, segs=10, smooth=0, closed=False):
    """Pipe along a path. smooth > 0 resamples with a spline first."""
    pts = smooth_path(points, smooth) if smooth else [Vector(p) for p in points]
    rings = []
    up = Vector((0, 0, 1))
    for i, p in enumerate(pts):
        a = pts[i - 1] if i > 0 else (pts[-1] if closed else p)
        b = pts[i + 1] if i < len(pts) - 1 else (pts[0] if closed else p)
        t = (b - a).normalized() if (b - a).length > 1e-6 else Vector((0, 1, 0))
        ref = up if abs(t.dot(up)) < 0.95 else Vector((1, 0, 0))
        u = t.cross(ref).normalized()
        v = t.cross(u).normalized()
        rings.append([tuple(p + (u * math.cos(TAU * k / segs) + v * math.sin(TAU * k / segs)) * radius) for k in range(segs)])
    if closed:
        rings.append(rings[0])
    return loft(name, rings, material, cap=not closed)


def text(name, body, size, loc, rot, material, extrude=0.01, align="CENTER"):
    cu = bpy.data.curves.new(name, "FONT")
    cu.body, cu.size, cu.extrude, cu.align_x, cu.align_y = body, size, extrude, align, "CENTER"
    ob = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(ob)
    select([ob])
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.view_layer.objects.active
    ob.data.materials.append(material)
    return place(ob, loc, rot)


# ---- surface projection ---------------------------------------------------------
class Surface:
    """Ray-cast helper around a finished body mesh."""

    def __init__(self, ob):
        dg = bpy.context.evaluated_depsgraph_get()
        self.bvh = BVHTree.FromObject(ob, dg)

    def hit(self, origin, direction):
        loc, normal, _, _ = self.bvh.ray_cast(Vector(origin), Vector(direction).normalized(), 500)
        return loc, normal

    def project(self, name, side, outline, material, offset=0.02, res=0.12, thickness=0.0, round_r=0.0):
        """Project a rectangle onto the body.
        side: 'L' (from -X), 'R' (+X), 'F' (+Y, front), 'B' (-Y, rear), 'T' (top).
        outline: (u0, v0, u1, v1) in the plane seen from that side:
           L/R: u = y, v = z      F/B: u = x, v = z      T: u = x, v = y
        Vertices that miss the body are dropped, so a patch can run off an edge safely."""
        u0, v0, u1, v1 = outline
        nu, nv = max(1, int(abs(u1 - u0) / res)), max(1, int(abs(v1 - v0) / res))
        bm = bmesh.new()
        grid = {}
        far = 300
        for i in range(nu + 1):
            for j in range(nv + 1):
                u, v = u0 + (u1 - u0) * i / nu, v0 + (v1 - v0) * j / nv
                if round_r > 0:  # rounded corners: grid points outside a corner arc are pulled onto the arc
                    ulo, uhi, vlo, vhi = min(u0, u1), max(u0, u1), min(v0, v1), max(v0, v1)
                    rr = min(round_r, (uhi - ulo) / 2, (vhi - vlo) / 2)
                    cu = ulo + rr if u < ulo + rr else (uhi - rr if u > uhi - rr else None)
                    cv = vlo + rr if v < vlo + rr else (vhi - rr if v > vhi - rr else None)
                    if cu is not None and cv is not None:
                        dd = math.hypot(u - cu, v - cv)
                        if dd > rr:
                            u, v = cu + (u - cu) / dd * rr, cv + (v - cv) / dd * rr
                if side == "R":
                    o, d = (far, u, v), (-1, 0, 0)
                elif side == "L":
                    o, d = (-far, u, v), (1, 0, 0)
                elif side == "F":
                    o, d = (u, far, v), (0, -1, 0)
                elif side == "B":
                    o, d = (u, -far, v), (0, 1, 0)
                else:
                    o, d = (u, v, far), (0, 0, -1)
                loc, nrm = self.hit(o, d)
                if loc is not None and nrm.dot(Vector(d)) < -0.12:
                    grid[(i, j)] = bm.verts.new(loc + nrm * offset)
        for i in range(nu):
            for j in range(nv):
                q = [grid.get(k) for k in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))]
                if all(q):
                    bm.faces.new(q)
        if not bm.faces:
            bm.free()
            return None
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
        bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=1e-4)
        ob = from_bm(name, bm, material)
        if thickness:
            solidify(ob, thickness, offset=1)
        return ob

    def point(self, side, u, v):
        far = 300
        o, d = {"R": ((far, u, v), (-1, 0, 0)), "L": ((-far, u, v), (1, 0, 0)), "F": ((u, far, v), (0, -1, 0)),
                "B": ((u, -far, v), (0, 1, 0)), "T": ((u, v, far), (0, 0, -1))}[side]
        return self.hit(o, d)


def cut_arch(ob, y0, z0, radius, min_x):
    """Open a round wheel arch in a body side without booleans: vertices inside the arch circle are
    pushed radially onto it (clean round lip), then the faces left inside are removed."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for v in bm.verts:
        if abs(v.co.x) < min_x:
            continue
        dy, dz = v.co.y - y0, v.co.z - z0
        d = math.hypot(dy, dz)
        if d < radius:
            if d < 1e-4:
                dy, dz, d = 0.0, 1.0, 1.0
            v.co.y, v.co.z = y0 + dy / d * radius, z0 + dz / d * radius
    dead = []
    for f in bm.faces:
        c = f.calc_center_median()
        if abs(c.x) >= min_x and math.hypot(c.y - y0, c.z - z0) < radius * 1.004:
            dead.append(f)
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()


# ---- wheels ------------------------------------------------------------------------
def tyre(r, w, rim_r, material=None, grooves=3, bulge=0.06, lugs=0, lug_h=0.0):
    """Tyre cross-section revolved: bead, bulged sidewall, shoulder, grooved tread."""
    hw = w / 2
    sh = r - (r - rim_r) * 0.16  # shoulder radius
    prof = [(rim_r, -hw * 0.82), (rim_r + (r - rim_r) * 0.18, -hw * 0.96), (rim_r + (r - rim_r) * 0.55, -hw * (1 + bulge)),
            (sh, -hw * 0.97), (r - 0.012 * r, -hw * 0.84)]
    # tread with circumferential grooves
    gw = w * 0.035
    depth = r * 0.035
    xs = [(-hw * 0.84) + (hw * 1.68) * (k + 1) / (grooves + 1) for k in range(grooves)]
    for gx in xs:
        prof += [(r, gx - gw * 1.6), (r, gx - gw), (r - depth, gx - gw * 0.7), (r - depth, gx + gw * 0.7), (r, gx + gw), (r, gx + gw * 1.6)]
    prof += [(r - 0.012 * r, hw * 0.84), (sh, hw * 0.97), (rim_r + (r - rim_r) * 0.55, hw * (1 + bulge)),
             (rim_r + (r - rim_r) * 0.18, hw * 0.96), (rim_r, hw * 0.82)]
    ob = lathe("tyre", prof, material or RUBBER(), segs=56, axis="X", cap=False)
    parts = [ob]
    if lugs:  # chunky off-road / tractor lugs in a chevron pattern
        for k in range(lugs):
            a = TAU * k / lugs
            for sx in (-1, 1):
                lug = box("lug", (hw * 0.95, r * 0.16, lug_h), (0, 0, 0), material or RUBBER(), bev=lug_h * 0.2)
                lug.location = (sx * hw * 0.5, 0, r + lug_h * 0.3)
                lug.rotation_euler = (0, 0, sx * math.radians(24))
                apply_xf(lug)
                lug.rotation_euler = (a + (0.5 * TAU / lugs if sx > 0 else 0), 0, 0)
                apply_xf(lug)
                parts.append(lug)
    return parts


def wheel(name, r, w, style="alloy5", side=1, color=None, caliper="#b3261e", rim_frac=0.64):
    """Complete wheel centred on the origin with its axle along X. side=+1: outer face towards +X."""
    rim_r = r * rim_frac
    hw = w / 2
    parts = []
    lugs = dict(offroad=14, monster=18, tractor=16).get(style, 0)
    parts += tyre(r, w, rim_r, grooves=4 if w > 1.2 else 3, bulge=0.10 if lugs else 0.06, lugs=lugs, lug_h=r * (0.09 if style == "monster" else 0.06))
    metal = mat("Rim", color, rough=0.32, metal=1.0) if color else ALLOY()
    # barrel with outer lip, drop centre and inner flange
    barrel = [(rim_r * 1.03, hw * 0.86), (rim_r * 1.03, hw * 0.78), (rim_r * 0.95, hw * 0.74), (rim_r * 0.9, hw * 0.3),
              (rim_r * 0.9, -hw * 0.6), (rim_r * 0.96, -hw * 0.76), (rim_r * 1.03, -hw * 0.8), (rim_r * 1.03, -hw * 0.86),
              (rim_r * 0.86, -hw * 0.86), (rim_r * 0.84, hw * 0.3), (rim_r * 0.9, hw * 0.74)]
    parts.append(lathe("barrel", barrel, metal, segs=48, axis="X", close=True))
    face_x = hw * 0.55
    if style in ("steel", "dually", "offroad", "tractor", "monster"):
        # dished steel centre with hand holes
        dish = [(0.0, face_x * 0.55), (rim_r * 0.3, face_x * 0.55), (rim_r * 0.42, face_x * 0.3), (rim_r * 0.75, face_x * 0.75),
                (rim_r * 0.9, face_x * 0.6), (rim_r * 0.9, face_x * 0.45), (rim_r * 0.75, face_x * 0.6), (rim_r * 0.42, face_x * 0.15),
                (rim_r * 0.3, face_x * 0.4), (0.0, face_x * 0.4)]
        centre = lathe("dish", dish, metal, segs=48, axis="X")
        nh = 8 if style != "monster" else 6
        for k in range(nh):
            a = TAU * k / nh
            cut = cyl("cut", rim_r * 0.11, w, (0, rim_r * 0.6 * math.cos(a), rim_r * 0.6 * math.sin(a)), None, "X", segs=16, bev=0)
            boolean(centre, cut)
        parts.append(centre)
        nl = 8
    else:
        n = dict(alloy5=5, sport10=10, mesh=14, kart=3).get(style, 5)
        pair = style == "sport10"
        hub = lathe("hub", [(0, face_x * 0.9), (rim_r * 0.2, face_x * 0.9), (rim_r * 0.3, face_x * 0.7), (rim_r * 0.3, face_x * 0.2), (0, face_x * 0.2)],
                    metal, segs=24, axis="X")
        parts.append(hub)
        for k in range(n):
            a = TAU * k / n
            # tapered, slightly dished spoke lofted from hub to barrel
            w0, w1 = rim_r * (0.16 if not pair else 0.07), rim_r * (0.1 if not pair else 0.05)
            t = rim_r * 0.09
            rings = []
            for rr, ww, xx in ((rim_r * 0.22, w0, face_x * 0.82), (rim_r * 0.55, (w0 + w1) / 2, face_x * 0.62), (rim_r * 0.9, w1, face_x * 0.78)):
                rings.append([(xx, -ww, rr), (xx, ww, rr), (xx - t, ww * 0.8, rr), (xx - t, -ww * 0.8, rr)])
            for off in ((-0.09, 0.09) if pair else (0,)):
                sp = loft("spoke", rings, metal)
                sp.rotation_euler = (a + off, 0, 0)
                apply_xf(sp)
                parts.append(sp)
        nl = 5 if style != "kart" else 3
        cap = lathe("cap", [(0, face_x * 0.98), (rim_r * 0.1, face_x * 0.97), (rim_r * 0.13, face_x * 0.9), (0, face_x * 0.9)], CHROME(), segs=16, axis="X")
        parts.append(cap)
    for k in range(nl):  # lug nuts
        a = TAU * (k + 0.5) / nl
        rr = rim_r * (0.2 if style not in ("steel", "dually", "offroad", "tractor", "monster") else 0.2)
        parts.append(cyl("nut", rim_r * 0.035, hw * 0.12, (face_x * 0.92, rr * math.cos(a), rr * math.sin(a)), CHROME(), "X", segs=6, bev=0.004))
    if style in ("alloy5", "sport10", "mesh"):
        disc = lathe("disc", [(rim_r * 0.25, 0.02), (rim_r * 0.8, 0.02), (rim_r * 0.8, -0.05), (rim_r * 0.25, -0.05)], STEEL(), segs=40, axis="X", close=True)
        parts.append(disc)
        parts.append(box("caliper", (hw * 0.5, rim_r * 0.5, rim_r * 0.3), (0, rim_r * 0.52, rim_r * 0.3), mat("Caliper", caliper, rough=0.4), bev=0.02))
    ob = join(parts, name)
    if side < 0:
        ob.scale.x = -1
        apply_xf(ob)
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
        bm.to_mesh(ob.data)
        bm.free()
    for p in ob.data.polygons:
        p.use_smooth = True
    return weighted_normals(ob)


# ---- body sections -------------------------------------------------------------------
def section(y, w, zf, zb, zd, wd, crown=0.06, flare=0.0, tuck=0.82):
    """One car-body cross-section ring at station y.
    w half-width, zf floor, zb beltline (shoulder), zd deck (hood / roof / boot height at this station),
    wd half-width of the deck, crown = roof / hood camber. Returns 20 points (closed ring)."""
    side_h = zb - zf
    half = [
        (0.0, zf),
        (w * tuck, zf),
        (w * 0.975, zf + side_h * 0.14),
        (w * (1.0 + flare), zf + side_h * 0.42),
        (w * (1.0 + flare * 0.6), zf + side_h * 0.8),
        (w * 0.965, zb),
        (w * 0.93, zb + (zd - zb) * 0.06 + 0.01),
        (w * 0.93 + (wd - w * 0.93) * 0.55, zb + (zd - zb) * 0.62),
        (wd, zd - (zd - zb) * 0.05),
        (wd * 0.55, zd + crown * 0.8),
        (0.0, zd + crown),
    ]
    ring = [(x, y, z) for x, z in half] + [(-x, y, z) for x, z in reversed(half[1:-1])]
    return ring


# point-pair indices of the 20-gon: side window strips and roof strips (both sides)
SIDE_GLASS = {6, 7, 12, 13}   # between points 6-7, 7-8 and mirrored
TOP_STRIPS = {8, 9, 10, 11}   # deck / roof / windscreen strips


# ---- more generators ---------------------------------------------------------------------
def oval(y, w, h, zc, n=20, power=2.4, xc=0.0):
    """Superellipse ring in the XZ plane at station y (fuselages, nacelles, tail booms)."""
    ring = []
    for k in range(n):
        a = TAU * k / n
        c, s = math.cos(a), math.sin(a)
        ring.append((xc + w * math.copysign(abs(c) ** (2 / power), c), y, zc + h * math.copysign(abs(s) ** (2 / power), s)))
    return ring


def naca(n=12, thick=0.12, camber=0.0, camber_pos=0.4):
    """Closed aerofoil outline, chord 0..1 (x back), list of (x, z)."""
    up, lo = [], []
    for k in range(n + 1):
        x = 0.5 * (1 - math.cos(math.pi * k / n))
        yt = 5 * thick * (0.2969 * math.sqrt(x) - 0.126 * x - 0.3516 * x ** 2 + 0.2843 * x ** 3 - 0.1015 * x ** 4)
        if camber and x < camber_pos:
            yc = camber / camber_pos ** 2 * (2 * camber_pos * x - x * x)
        elif camber:
            yc = camber / (1 - camber_pos) ** 2 * ((1 - 2 * camber_pos) + 2 * camber_pos * x - x * x)
        else:
            yc = 0
        up.append((x, yc + yt))
        lo.append((x, yc - yt))
    return up + list(reversed(lo[1:-1]))


def airfoil(name, stations, material, thick=0.12, camber=0.02, n=12):
    """Loft an aerofoil through stations [(leading_edge_xyz, chord, twist_deg, span_axis)], chord runs towards -Y.
    span_axis 'X' (wings / tailplanes) or 'Z' (fins)."""
    prof = naca(n, thick, camber)
    rings = []
    for le, chord, twist, axis in stations:
        t = math.radians(twist)
        ring = []
        for x, z in prof:
            cx, cz = x * chord, z * chord
            yy = -(cx * math.cos(t) - cz * math.sin(t))
            zz = cx * math.sin(t) * -1 + cz * math.cos(t)
            if axis == "X":
                ring.append((le[0], le[1] + yy, le[2] + zz))
            else:
                ring.append((le[0] + zz, le[1] + yy, le[2]))
        rings.append(ring)
    return loft(name, rings, material)


def blade(name, length, chord, material, pitch_root=38, pitch_tip=12, root=0.18, axis="Y", thick=0.1):
    """Twisted propeller / rotor blade from the hub (origin) out along +X, spinning about `axis`."""
    prof = naca(8, thick, 0.03)
    rings = []
    for k in range(9):
        f = k / 8
        r = length * (root + (1 - root) * f)
        c = chord * (0.55 + 0.75 * math.sin(math.pi * min(1.0, f * 0.9 + 0.12))) * (1 - 0.35 * f ** 3)
        p = math.radians(pitch_root + (pitch_tip - pitch_root) * f)
        ring = []
        for x, z in prof:
            u, v = (x - 0.35) * c, z * c
            a, b = u * math.cos(p) - v * math.sin(p), u * math.sin(p) + v * math.cos(p)
            ring.append((r, b, a) if axis == "Y" else (r, a, b))
        rings.append(ring)
    return loft(name, rings, material)


def track_path(wheels, n=420):
    """Closed belt around circles [(y, z, r), ...] given in order around the loop (convex hull walk)."""
    pts = []
    m = len(wheels)
    for i in range(m):
        y0, z0, r0 = wheels[i]
        y1, z1, r1 = wheels[(i + 1) % m]
        yp, zp, rp = wheels[i - 1]
        # outer tangent directions (belt travels clockwise seen from +X: top goes forward)
        def tangent(a, b):
            d = Vector((b[0] - a[0], b[1] - a[1]))
            L = d.length
            ang = math.atan2(d.y, d.x) + math.asin(max(-1, min(1, (a[2] - b[2]) / L)))
            return ang + math.pi / 2
        a_in = tangent((yp, zp, rp), (y0, z0, r0))
        a_out = tangent((y0, z0, r0), (y1, z1, r1))
        while a_out > a_in:
            a_out -= TAU
        if a_in - a_out > 1.5 * math.pi:   # nearly collinear wheels: no wrap
            a_out = a_in
        steps = max(2, int(abs(a_in - a_out) / 0.12))
        for k in range(steps + 1):
            a = a_in + (a_out - a_in) * k / steps
            pts.append(Vector((0, y0 + r0 * math.cos(a), z0 + r0 * math.sin(a))))
    # resample evenly
    pts.append(pts[0])
    lens = [0.0]
    for a, b in zip(pts, pts[1:]):
        lens.append(lens[-1] + (b - a).length)
    total = lens[-1]
    out, j = [], 0
    for k in range(n):
        s = total * k / n
        while lens[j + 1] < s:
            j += 1
        f = (s - lens[j]) / max(lens[j + 1] - lens[j], 1e-9)
        out.append(pts[j].lerp(pts[j + 1], f))
    return out, total


def track(name, x, width, wheels, pitch=0.62, pad="#151517", steel="#3c3f44"):
    """Crawler track: individual links (shoe plate, grouser bar, guide horn) laid around the wheel set."""
    path, total = track_path(wheels)
    count = int(total / pitch)
    parts = []
    msteel, mpad = mat("TrackSteel", steel, rough=0.55, metal=0.85), mat("TrackPad", pad, rough=0.9)
    n = len(path)
    for k in range(count):
        i = int(k * n / count)
        p, q = path[i], path[(i + 2) % n]
        t = (q - p).normalized()
        ang = math.atan2(t.z, t.y)
        link = box("shoe", (width, pitch * 0.86, 0.16), (0, 0, 0), msteel, bev=0.03, segs=1)
        gro = box("grouser", (width * 0.96, pitch * 0.2, 0.14), (0, 0, 0.13), mpad, bev=0.03, segs=1)
        horn = box("horn", (width * 0.12, pitch * 0.45, 0.3), (0, 0, -0.2), msteel, bev=0.05, segs=1)
        for o in (link, gro, horn):
            o.rotation_euler = (ang, 0, 0)
            o.location = (x, p.y, p.z)
            apply_xf(o)
            # the outward normal of the loop: rotate local +Z by ang -> shoe faces outwards
        parts += [link, gro, horn]
    return join(parts, name)


def bolts(points, radius, material, axis="X", depth=0.08):
    return [cyl("bolt", radius, depth, p, material, axis, segs=6, bev=0.01) for p in points]
