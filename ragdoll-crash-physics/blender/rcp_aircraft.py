"""Light aircraft, twin turboprop freighter and light helicopter: lofted fuselages, real aerofoil
wings / tails, twisted propeller and rotor blades, landing gear."""
import math

from mathutils import Vector

import rcp_model as M
import rcp_cars as C
from rcp_model import box, cyl, lathe, loft, tube, mat, oval

N = 20
UPPER_SIDE = {1, 2, 3, 6, 7, 8}
TOP = {4, 5}


def fuselage(stations, materials, power=2.5, subdiv=2):
    """stations: (y, half_w, half_h, z_centre, flag). flag: '' | 'ws' | 'side' | 'bubble' | 'dark'."""
    rings = [oval(y, w, h, zc, N, power) for y, w, h, zc, _ in stations]
    flags = [s[4] for s in stations]

    def mat_fn(i, j):
        f = flags[i]
        if f == "ws" and (j in UPPER_SIDE or j in TOP):
            return 1
        if f == "side" and j in UPPER_SIDE:
            return 1
        if f == "bubble" and j not in (13, 14, 15, 16):
            return 1
        if f == "doors" and j in (19, 0, 1, 2, 3, 6, 7, 8, 9, 10):
            return 1
        if f == "dark":
            return 2
        return 0
    sh = loft("fuselage", rings, materials=materials, mat_fn=mat_fn)
    M.subsurf(sh, subdiv)
    return sh


def prop(name, pivot, blades, length, chord, spinner_r, material, axis="Y", pitch=(40, 14)):
    parts = [lathe("spinner", [(0, spinner_r * 1.9), (spinner_r * 0.35, spinner_r * 1.6), (spinner_r * 0.75, spinner_r * 0.9), (spinner_r, 0), (spinner_r, -spinner_r * 0.5), (0, -spinner_r * 0.5)],
                   M.CHROME(), segs=24, axis="Y")]
    for k in range(blades):
        b = M.blade("blade", length, chord, material, pitch[0], pitch[1], axis="Y")
        b.rotation_euler = (0, M.TAU * k / blades, 0)
        M.apply_xf(b)
        parts.append(b)
        tip = box("tipstripe", (length * 0.07, 0.03, chord * 0.5), (length * 0.96, 0, 0), M.mat("TipYellow", "#f2c010", rough=0.5), bev=0.005)
        tip.rotation_euler = (0, M.TAU * k / blades, 0)
        M.apply_xf(tip)
        parts.append(tip)
    ob = M.join(parts, name)
    M.place(ob, pivot)
    return ob


def gear_wheel(G, w, i):
    x, y, z = w["pos"][0], -w["pos"][2], w["pos"][1]
    ob = M.wheel("Wheel%d" % (i + 1), w["radius"], w["width"], "kart", 1 if x >= 0 else -1, "#d9dce0", rim_frac=0.5)
    M.place(ob, (x, y, z))
    M.set_origin(ob, (x, y, z))
    G["Wheels"].append(ob)
    return x, y, z


def pant(x, y, z, r, w, paint):
    """Streamlined wheel spat covering the top of a wheel."""
    rings = [oval(y + r * 1.7, w * 0.25, r * 0.25, z + r * 0.35, 12, 2.2, x), oval(y + r * 0.9, w * 0.85, r * 0.75, z + r * 0.35, 12, 2.2, x),
             oval(y, w * 0.95, r * 0.85, z + r * 0.38, 12, 2.2, x), oval(y - r * 1.2, w * 0.7, r * 0.6, z + r * 0.42, 12, 2.2, x),
             oval(y - r * 2.3, w * 0.12, r * 0.15, z + r * 0.5, 12, 2.2, x)]
    ob = loft("pant", rings, paint)
    M.subsurf(ob, 1)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, z - r * 0.1), plane_no=(0, 0, -1), clear_outer=True)
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def register(builder, spec, car_dims):
    @builder("SmallPlane")
    def small_plane():
        s = spec("SmallPlane")
        G = C.new_groups()
        white, red = M.paint("#f3f4f6"), M.paint("#d4241c")
        cz = 3.8
        st = [(12.3, 0.5, 0.5, cz, ""), (11.7, 1.25, 1.2, cz, ""), (10.2, 1.5, 1.45, cz, ""), (8.4, 1.6, 1.55, cz + 0.05, ""),
              (7.2, 1.65, 1.6, cz + 0.1, "ws"), (5.3, 1.7, 2.15, cz + 0.65, "side"), (3.55, 1.7, 2.15, cz + 0.65, ""), (3.25, 1.7, 2.15, cz + 0.65, "side"),
              (1.4, 1.7, 2.1, cz + 0.6, "side"), (-0.6, 1.55, 1.85, cz + 0.45, ""), (-5.0, 1.05, 1.25, cz + 0.3, ""), (-10.0, 0.6, 0.8, cz + 0.4, ""),
              (-14.6, 0.25, 0.5, cz + 0.6, ""), (-16.0, 0.08, 0.25, cz + 0.7, "")]
        shell = fuselage(st, [white, M.GLASS(), M.DARK()])
        surf = M.Surface(shell)
        body, glass = C.split_glass(shell)
        G["Body"].append(body)
        G["Glass"].append(glass)
        P = surf.project
        for side in ("L", "R"):
            sg = 1 if side == "R" else -1
            G["Body"].append(P("cheat", side, (-13.5, cz - 0.15, 11.0, cz + 0.2), red, 0.01, res=0.2))
            G["Body"].append(P("cheat2", side, (-12.0, cz - 0.42, 9.0, cz - 0.3), red, 0.01, res=0.2))
            # cabin door: the cut runs round the door AND its window (light-aircraft doors carry the
            # window), hinged on the front edge; a small baggage door further back
            G["Trim"].append(C.groove_path(surf, side, C.rounded_rect(1.55, cz - 1.05, 5.15, cz + 2.15, 0.45), M.DARK(), radius=0.02))
            G["Trim"] += C.hinges(surf, side, 5.05, (cz - 0.5, cz + 1.3), M.CHROME(), length=0.3, radius=0.045)
            G["Trim"].append(C.groove_path(surf, side, C.rounded_rect(-1.7, cz - 0.85, -0.5, cz + 0.25, 0.15), M.DARK(), radius=0.018))
            G["Trim"] += C.latch(surf, side, -1.1, cz + 0.05, M.CHROME(), w=0.22, h=0.08)
            G["Trim"].append(P("cowlseam", side, (8.35, cz - 1.4, 8.4, cz + 1.4), M.DARK(), 0.008, res=0.1))
            loc, _ = surf.point(side, -6.5, cz + 0.75)
            G["Trim"].append(M.text("reg", "N172RC", 0.62, (loc.x + sg * 0.03, -6.5, cz + 0.85), (math.pi / 2, 0, sg * math.pi / 2), M.matte("#14161a", 0.5)))
            G["Trim"].append(tube("exhaust", [(sg * 0.7, 9.6, cz - 1.3), (sg * 0.8, 9.2, cz - 1.75), (sg * 0.8, 8.6, cz - 1.9)], 0.13, M.STEEL(), segs=10, smooth=3))
            G["Trim"].append(P("inlet", "F", (sg * 0.95 - 0.42, cz + 0.1, sg * 0.95 + 0.42, cz + 0.7), M.DARK(), 0.01, res=0.06, round_r=0.3))
            G["Trim"].append(box("step", (0.5, 0.5, 0.06), (sg * 1.85, 1.2, cz - 1.5), M.STEEL(), bev=0.02))
            # cabin door: flush pull handle near the rear edge, under the window, set in a recess
            G["Trim"].append(P("handlepocket", side, (1.75, cz - 0.42, 2.45, cz - 0.18), M.mat("Pocket", "#121315", rough=0.35), 0.01, res=0.04, round_r=0.1))
            G["Trim"].append(C.pull_handle(surf, side, 2.1, cz - 0.3, 0.55, M.CHROME(), flush=True))
        G["Trim"].append(P("chin", "F", (-0.5, cz - 1.15, 0.5, cz - 0.6), M.DARK(), 0.01, res=0.06, round_r=0.25))
        # wing: NACA 2413, taper, 5 degrees of dihedral
        dih = math.tan(math.radians(5))
        wz = cz - 0.85
        def wst(x, chord):
            return ((x, 4.36 - abs(x) * 0.03 - (5.2 - chord) * 0.25, wz + abs(x) * dih), chord, -1.5 * abs(x) / 17, "X")
        wing = M.airfoil("wing", [wst(-17.0, 2.0), wst(-16.6, 3.3), wst(-9, 4.3), wst(-1.6, 5.2), wst(1.6, 5.2), wst(9, 4.3), wst(16.6, 3.3), wst(17.0, 2.0)], white, 0.13, 0.02)
        wsurf = M.Surface(wing)
        G["Body"].append(wing)
        for sg in (-1, 1):
            x0, x1 = sorted((sg * 13.4, sg * 16.9))
            G["Body"].append(wsurf.project("tipstripe", "T", (x0, -1.5, x1, 4.6), red, 0.01, res=0.2))
            a0, a1 = sorted((sg * 9.6, sg * 16.2))
            G["Trim"].append(wsurf.project("aileron", "T", (a0, 0.42, a1, 0.47), M.DARK(), 0.008, res=0.2))
            f0, f1 = sorted((sg * 2.0, sg * 9.4))
            G["Trim"].append(wsurf.project("flap", "T", (f0, 0.25, f1, 0.3), M.DARK(), 0.008, res=0.2))
            G["Trim"].append(wsurf.project("gap", "T", (sg * 9.5 - 0.03, -0.9, sg * 9.5 + 0.03, 0.45), M.DARK(), 0.008, res=0.2))
            G["Lights"].append(box("nav", (0.25, 0.5, 0.2), (sg * 17.05, 3.4, wz + 17 * dih), M.mat("NavR" if sg < 0 else "NavG", "#e01616" if sg < 0 else "#19c23a", rough=0.2, emit=1.0), bev=0.08))
            G["Body"].append(loft("fillet", [oval(5.4, 0.6, 0.5, wz + 0.2, 10, 2, sg * 1.7), oval(1.5, 1.0, 0.75, wz + 0.25, 10, 2, sg * 1.8), oval(-2.0, 0.5, 0.4, wz + 0.4, 10, 2, sg * 1.5)], white))
        G["Lights"].append(box("landing", (0.6, 0.12, 0.25), (-7.0, 3.95, wz + 7 * dih + 0.05), M.HEADLIGHT(), bev=0.05))
        G["Trim"].append(tube("pitot", [(-8.5, 2.5, wz + 8.5 * dih - 0.25), (-8.5, 2.6, wz + 8.5 * dih - 0.6), (-8.5, 3.6, wz + 8.5 * dih - 0.6)], 0.04, M.STEEL(), segs=6))
        # tail
        tz = cz + 0.75
        G["Body"].append(M.airfoil("tailplane", [((-6.0, -13.1, tz), 1.6, 0, "X"), ((-5.7, -12.9, tz), 2.2, 0, "X"), ((0, -12.3, tz), 3.4, 0, "X"), ((5.7, -12.9, tz), 2.2, 0, "X"), ((6.0, -13.1, tz), 1.6, 0, "X")], white, 0.1, 0))
        fin = M.airfoil("fin", [((0, -9.8, cz + 0.9), 5.6, 0, "Z"), ((0, -12.6, cz + 3.6), 3.4, 0, "Z"), ((0, -13.9, cz + 5.9), 2.2, 0, "Z"), ((0, -14.3, cz + 6.2), 1.2, 0, "Z")], white, 0.1, 0)
        G["Body"].append(fin)
        fs = M.Surface(fin)
        for side in ("L", "R"):
            G["Body"].append(fs.project("finstripe", side, (-16.5, cz + 4.2, -12.0, cz + 6.1), red, 0.01, res=0.15))
            G["Trim"].append(fs.project("rudder", side, (-14.75, cz + 1.2, -14.7, cz + 6.0), M.DARK(), 0.008, res=0.15))
        G["Lights"].append(cyl("beacon", 0.14, 0.25, (0, -14.6, cz + 6.35), M.mat("Beacon", "#e01616", rough=0.2, emit=1.5), "Z", segs=12))
        for xk in (-0.5, 0.5):
            G["Trim"].append(box("antenna", (0.04, 0.5, 0.7), (xk, 2.0 + xk, cz + 3.1), M.matte("#e8e8e8", 0.5), bev=0.01, rot=(math.radians(-20), 0, 0)))
        # propeller
        pv = s["spinners"][0]["pivot"]
        G["Spin"].append(prop("Spin1", (pv[0], -pv[2], pv[1]), 2, 3.75, 0.62, 0.55, M.matte("#1a1b1e", 0.4)))
        # landing gear
        for i, w in enumerate(s["wheels"]):
            x, y, z = gear_wheel(G, w, i)
            G["Body"].append(pant(x, y, z, w["radius"], w["width"], white))
            if abs(x) < 0.1:
                G["Trim"].append(tube("nosestrut", [(0, y + 0.3, cz - 1.4), (0, y, z + 0.9)], 0.13, M.CHROME(), segs=10))
                for sx in (-1, 1):
                    G["Trim"].append(tube("fork", [(0, y, z + 0.95), (sx * 0.5, y, z + 0.7), (sx * 0.5, y, z)], 0.07, M.STEEL(), segs=8))
            else:
                sgn = 1 if x > 0 else -1
                leg = loft("leg", [[(sgn * 1.0, y + 0.45, cz - 1.3), (sgn * 1.0, y - 0.45, cz - 1.3), (sgn * 1.0, y - 0.45, cz - 1.42), (sgn * 1.0, y + 0.45, cz - 1.42)],
                                   [(x - sgn * 0.55, y + 0.3, z + 0.2), (x - sgn * 0.55, y - 0.3, z + 0.2), (x - sgn * 0.55, y - 0.3, z + 0.08), (x - sgn * 0.55, y + 0.3, z + 0.08)]], white)
                G["Body"].append(leg)
                G["Trim"].append(cyl("stub", 0.1, 0.6, (x - sgn * 0.3, y, z), M.STEEL(), "X", segs=8))
        # cabin: four seats, panel and dual yokes (see rcp_interior.light_aircraft)
        import rcp_interior as I
        I.light_aircraft(s, G, body, cz, 6.3, (-1.9, -0.4, cz - 0.9), (1.9, 7.15, cz + 3.0))
        return G

    @builder("CargoPlane")
    def cargo_plane():
        s = spec("CargoPlane")
        G = C.new_groups()
        grey, blue = M.paint("#c3c9d0"), M.paint("#1f5fbf")
        cz = 7.2
        st = [(17.9, 0.3, 0.3, 6.1, "dark"), (17.2, 1.5, 1.4, 6.2, "dark"), (15.9, 2.9, 2.6, 6.55, ""), (15.3, 3.3, 3.0, 6.7, "ws"),
              (13.6, 4.0, 3.8, 7.0, ""), (11.0, 4.5, 4.2, cz, ""), (-6.0, 4.5, 4.2, cz, ""), (-12.0, 4.0, 3.6, 8.0, ""),
              (-18.0, 2.6, 2.4, 9.4, ""), (-23.0, 1.0, 1.2, 10.6, ""), (-25.2, 0.3, 0.5, 11.0, "")]
        shell = fuselage(st, [grey, M.GLASS(), M.matte("#1c1e22", 0.5)], power=2.7)
        surf = M.Surface(shell)
        body, glass = C.split_glass(shell)
        G["Body"].append(body)
        G["Glass"].append(glass)
        P = surf.project
        for side in ("L", "R"):
            sg = 1 if side == "R" else -1
            G["Body"].append(P("cheat", side, (-21.0, cz + 0.2, 15.0, cz + 0.95), blue, 0.012, res=0.3))
            G["Body"].append(P("cheat2", side, (-19.0, cz - 0.3, 14.0, cz - 0.05), blue, 0.012, res=0.3))
            for k in range(6):
                yy = 8.0 - k * 2.6
                G["Glass"].append(P("porthole", side, (yy - 0.42, cz + 1.5, yy + 0.42, cz + 2.34), M.GLASS(), 0.03, res=0.07, round_r=0.42))
                G["Trim"].append(P("portring", side, (yy - 0.52, cz + 1.4, yy + 0.52, cz + 2.44), M.DARK(), 0.015, res=0.07, round_r=0.52))
            # crew entry door (forward, hinged at its front edge) and the paratroop door aft
            G["Trim"].append(C.groove_path(surf, side, C.rounded_rect(10.2, cz - 2.6, 12.06, cz + 1.2, 0.35), M.DARK(), radius=0.03))
            G["Trim"] += C.hinges(surf, side, 11.95, (cz - 1.8, cz + 0.4), M.STEEL(), length=0.4, radius=0.06)
            G["Trim"].append(P("crewpocket", side, (10.35, cz - 1.0, 10.95, cz - 0.7), M.mat("Pocket", "#121315", rough=0.35), 0.01, res=0.04, round_r=0.08))
            G["Trim"].append(C.pull_handle(surf, side, 10.65, cz - 0.85, 0.5, M.STEEL(), flush=True))
            G["Trim"].append(C.groove_path(surf, side, C.rounded_rect(-8.4, cz - 2.8, -5.74, cz + 0.6, 0.35), M.DARK(), radius=0.03))
            G["Trim"] += C.latch(surf, side, -7.07, cz - 1.7, M.STEEL(), w=0.4, h=0.14)
            G["Trim"].append(C.grab_handle(surf, side, -5.5, cz - 2.4, cz - 0.4, M.STEEL(), standoff=0.12))
            loc, _ = surf.point(side, 0.5, cz - 1.5)
            G["Trim"].append(M.text("title", "RCP AIR CARGO", 1.0, (loc.x + sg * 0.04, 0.5, cz - 1.5), (math.pi / 2, 0, sg * math.pi / 2), M.matte("#1f3f7a", 0.5)))
            # main gear sponson
            sp = loft("sponson", [oval(5.5, 0.4, 0.5, 3.3, 12, 2.2, sg * 4.2), oval(3.0, 1.3, 1.6, 3.3, 12, 2.2, sg * 4.5), oval(-0.75, 1.5, 1.8, 3.3, 12, 2.2, sg * 4.6),
                                  oval(-4.5, 1.3, 1.6, 3.4, 12, 2.2, sg * 4.5), oval(-7.5, 0.4, 0.5, 3.6, 12, 2.2, sg * 4.2)], grey)
            M.subsurf(sp, 1)
            G["Body"].append(sp)
        G["Trim"].append(P("ramp", "B", (-2.6, 7.2, 2.6, 7.26), M.DARK(), 0.01, res=0.15))
        # high wing
        wz = cz + 4.0
        def wst(x, chord):
            return ((x, 6.54 - (7.8 - chord) * 0.3, wz), chord, 0, "X")
        wing = M.airfoil("wing", [wst(-34.6, 2.6), wst(-34.0, 4.4), wst(-14, 6.8), wst(-4.4, 7.8), wst(4.4, 7.8), wst(14, 6.8), wst(34.0, 4.4), wst(34.6, 2.6)], grey, 0.15, 0.025)
        wsurf = M.Surface(wing)
        G["Body"].append(wing)
        G["Body"].append(box("wingbox", (9.4, 8.6, 1.3), (0, 2.5, wz - 0.2), grey, bev=0.5, segs=3))
        for sg in (-1, 1):
            a0, a1 = sorted((sg * 20, sg * 33.5))
            G["Trim"].append(wsurf.project("aileron", "T", (a0, 0.6, a1, 0.66), M.DARK(), 0.01, res=0.3))
            f0, f1 = sorted((sg * 5, sg * 19.6))
            G["Trim"].append(wsurf.project("flap", "T", (f0, 0.4, f1, 0.46), M.DARK(), 0.01, res=0.3))
            x0, x1 = sorted((sg * 30, sg * 34.4))
            G["Body"].append(wsurf.project("tip", "T", (x0, 0, x1, 7), blue, 0.012, res=0.3))
            G["Lights"].append(box("nav", (0.3, 0.6, 0.25), (sg * 34.7, 5.2, wz), M.mat("NavR" if sg < 0 else "NavG", "#e01616" if sg < 0 else "#19c23a", rough=0.2, emit=1.0), bev=0.08))
        # nacelles + four-blade propellers
        for i, sp in enumerate(s["spinners"]):
            pv = sp["pivot"]
            ex, ey, ez = pv[0], -pv[2], pv[1]
            nac = loft("nacelle", [oval(ey - 0.1, 0.95, 0.95, ez, 16, 2, ex), oval(ey - 0.9, 1.45, 1.5, ez - 0.1, 16, 2, ex), oval(ey - 5.5, 1.5, 1.6, ez - 0.1, 16, 2, ex),
                                   oval(ey - 9.5, 1.0, 1.1, ez + 0.3, 16, 2, ex), oval(ey - 12.5, 0.25, 0.3, ez + 0.9, 16, 2, ex)], grey)
            M.subsurf(nac, 1)
            G["Body"].append(nac)
            G["Trim"].append(cyl("intake", 0.5, 0.6, (ex, ey - 0.9, ez - 1.3), M.DARK(), "Y", segs=18))
            G["Trim"].append(tube("jetpipe", [(ex + 1.2, ey - 6.0, ez - 0.4), (ex + 1.6, ey - 7.5, ez - 0.5)], 0.4, M.STEEL(), segs=12))
            G["Spin"].append(prop("Spin%d" % (i + 1), (ex, ey, ez), 4, 5.6, 0.95, 0.75, M.matte("#1a1b1e", 0.4), pitch=(46, 18)))
        # T-less conventional tail
        tz = cz + 2.6
        G["Body"].append(M.airfoil("tailplane", [((-9.2, -20.3, tz), 2.2, 0, "X"), ((-8.8, -20.0, tz), 3.2, 0, "X"), ((0, -18.6, tz), 5.4, 0, "X"), ((8.8, -20.0, tz), 3.2, 0, "X"), ((9.2, -20.3, tz), 2.2, 0, "X")], grey, 0.11, 0))
        fin = M.airfoil("fin", [((0, -14.5, cz + 3.0), 9.0, 0, "Z"), ((0, -18.2, cz + 7.5), 5.6, 0, "Z"), ((0, -20.3, cz + 10.8), 3.6, 0, "Z"), ((0, -20.9, cz + 11.2), 2.0, 0, "Z")], grey, 0.11, 0)
        G["Body"].append(fin)
        fs = M.Surface(fin)
        for side in ("L", "R"):
            sg = 1 if side == "R" else -1
            G["Body"].append(fs.project("finband", side, (-25.0, cz + 8.6, -18.0, cz + 11.0), blue, 0.012, res=0.2))
            loc, _ = fs.point(side, -20.4, cz + 6.6)
            if loc is not None:
                G["Trim"].append(M.text("tailnum", "RC-130", 0.95, (loc.x + sg * 0.04, -20.4, cz + 6.6), (math.pi / 2, 0, sg * math.pi / 2), M.matte("#14161a", 0.5)))
        G["Lights"].append(cyl("beacon", 0.2, 0.3, (0, -21.4, cz + 11.4), M.mat("Beacon", "#e01616", rough=0.2, emit=1.5), "Z", segs=12))
        for i, w in enumerate(s["wheels"]):
            x, y, z = gear_wheel(G, w, i)
            if abs(x) < 0.1:
                G["Trim"].append(tube("nosestrut", [(0, y, 3.4), (0, y, z)], 0.22, M.CHROME(), segs=12))
                G["Trim"].append(cyl("noseaxle", 0.12, 1.6, (0, y, z), M.STEEL(), "X", segs=8))
            else:
                sgn = 1 if x > 0 else -1
                G["Trim"].append(tube("mainstrut", [(x - sgn * 0.2, y, 3.2), (x - sgn * 0.75, y, z)], 0.24, M.CHROME(), segs=12))
                G["Trim"].append(cyl("mainaxle", 0.14, 1.4, (x - sgn * 0.4, y, z), M.STEEL(), "X", segs=8))
        # flight deck in the nose (see rcp_interior.flight_deck)
        import rcp_interior as I
        I.flight_deck(s, G, body, s["seat"][1] + 0.3 - 1.25, 15.25, 3.6, 10.6)
        return G

    @builder("Helicopter")
    def helicopter():
        s = spec("Helicopter")
        G = C.new_groups()
        red, white = M.paint("#c9211b"), M.paint("#f3f4f6")
        st = [(6.95, 0.45, 0.55, 3.3, "bubble"), (6.1, 1.8, 1.65, 3.65, "bubble"), (4.2, 2.8, 2.4, 4.1, "doors"), (1.6, 3.0, 2.6, 4.2, ""),
              (1.2, 3.0, 2.6, 4.2, "doors"), (-1.6, 3.0, 2.6, 4.2, ""), (-2.4, 2.9, 2.5, 4.25, ""), (-4.2, 2.1, 1.9, 4.7, ""), (-5.7, 0.9, 0.95, 5.3, "")]
        shell = fuselage(st, [red, M.GLASS(), M.DARK()], power=2.3)
        surf = M.Surface(shell)
        body, glass = C.split_glass(shell)
        G["Body"].append(body)
        G["Glass"].append(glass)
        P = surf.project
        boom = loft("boom", [oval(-4.6, 0.8, 0.8, 5.35, 14, 2), oval(-10, 0.6, 0.62, 5.45, 14, 2), oval(-16.6, 0.34, 0.38, 5.6, 14, 2), oval(-17.4, 0.12, 0.16, 5.62, 14, 2)], red)
        G["Body"].append(boom)
        cowl = loft("cowl", [oval(2.4, 0.5, 0.3, 6.6, 14, 2.2), oval(1.2, 1.5, 0.9, 6.75, 14, 2.2), oval(-2.5, 1.5, 0.95, 6.85, 14, 2.2), oval(-5.0, 0.9, 0.6, 6.5, 14, 2.2), oval(-6.2, 0.3, 0.25, 6.2, 14, 2.2)], white)
        M.subsurf(cowl, 1)
        G["Body"].append(cowl)
        G["Trim"].append(tube("exhaust", [(0, -3.6, 7.2), (0, -4.6, 7.6), (0, -5.3, 7.75)], 0.33, M.STEEL(), segs=14, smooth=3))
        for k in range(4):
            G["Trim"].append(box("cowlvent", (0.05, 0.9, 0.12), (1.47, -0.5 - k * 0.0, 6.6 + k * 0.14), M.DARK(), bev=0.01))
            G["Trim"].append(box("cowlvent", (0.05, 0.9, 0.12), (-1.47, -0.5, 6.6 + k * 0.14), M.DARK(), bev=0.01))
        for side in ("L", "R"):
            sg = 1 if side == "R" else -1
            G["Body"].append(P("stripe", side, (-5.0, 2.55, 3.4, 2.95), white, 0.012, res=0.15))
            # crew door: hinged at the front, handle near the rear edge. Cabin door behind it SLIDES
            # back on top and bottom rails, so its handle is at the front edge.
            G["Trim"].append(C.groove_path(surf, side, C.rounded_rect(1.45, 1.95, 4.25, 5.9, 0.4), M.DARK(), radius=0.022))
            G["Trim"] += C.hinges(surf, side, 4.1, (2.7, 5.1), M.CHROME(), length=0.35, radius=0.05)
            G["Trim"].append(C.pull_handle(surf, side, 1.95, 3.5, 0.5, M.CHROME()))
            G["Trim"].append(C.groove_path(surf, side, C.rounded_rect(-1.55, 1.95, 1.4, 5.9, 0.3), M.DARK(), radius=0.022))
            G["Trim"].append(C.pull_handle(surf, side, 1.0, 3.5, 0.5, M.CHROME()))
            for zr in (5.95, 1.92):
                G["Trim"].append(C.groove_path(surf, side, [(1.3 - 5.4 * k / 16, zr) for k in range(17)], M.STEEL(), radius=0.05, sink=0.05))
            loc, _ = surf.point(side, -3.3, 4.2)
            G["Trim"].append(M.text("reg", "N206RC", 0.5, (loc.x + sg * 0.04, -3.3, 4.2), (math.pi / 2, 0, sg * math.pi / 2), M.matte("#f4f4f4", 0.5)))
            G["Lights"].append(box("nav", (0.2, 0.4, 0.18), (sg * 3.05, -1.0, 3.2), M.mat("NavR" if sg < 0 else "NavG", "#e01616" if sg < 0 else "#19c23a", rough=0.2, emit=1.0), bev=0.06))
            # skid with upturned toe + step
            x = sg * 3.2
            G["Trim"].append(tube("skid", [(x, 6.3, 1.25), (x, 5.7, 0.6), (x, 4.6, 0.36), (x, 0, 0.35), (x, -6.0, 0.35)], 0.2, M.matte("#1d1e21", 0.5), segs=12, smooth=5))
            G["Trim"].append(box("skidstep", (0.9, 2.4, 0.08), (x - sg * 0.1, 2.0, 1.15), M.STEEL(), bev=0.02))
        for yy in (3.2, -2.6):   # arched cross tubes
            G["Trim"].append(tube("cross", [(-3.2, yy, 0.4), (-2.9, yy, 1.1), (-1.6, yy, 1.75), (1.6, yy, 1.75), (2.9, yy, 1.1), (3.2, yy, 0.4)], 0.15, M.matte("#1d1e21", 0.5), segs=10, smooth=4))
        G["Lights"].append(cyl("landing", 0.3, 0.2, (0, 5.2, 1.85), M.HEADLIGHT(), "Y", segs=16))
        G["Lights"].append(cyl("beacon", 0.16, 0.25, (0, -8.0, 6.2), M.mat("Beacon", "#e01616", rough=0.2, emit=1.5), "Z", segs=12))
        G["Trim"].append(tube("pitot", [(0.6, 6.6, 3.0), (0.6, 7.6, 2.9)], 0.04, M.STEEL(), segs=6))
        # tail surfaces
        G["Body"].append(M.airfoil("stab", [((-2.6, -11.6, 5.5), 1.3, 0, "X"), ((0, -11.4, 5.5), 1.7, 0, "X"), ((2.6, -11.6, 5.5), 1.3, 0, "X")], white, 0.1, 0))
        for sx in (-2.6, 2.6):
            G["Body"].append(box("endplate", (0.08, 1.5, 1.3), (sx, -12.3, 5.5), white, bev=0.03))
        G["Body"].append(M.airfoil("fin", [((0, -14.6, 4.0), 2.6, 0, "Z"), ((0, -15.2, 5.6), 2.6, 0, "Z"), ((0, -16.3, 8.3), 1.6, 0, "Z"), ((0, -16.6, 8.6), 0.9, 0, "Z")], white, 0.1, 0))
        G["Trim"].append(tube("tailskid", [(0, -15.6, 4.1), (0, -16.4, 3.2), (0, -17.2, 3.0)], 0.07, M.STEEL(), segs=8, smooth=3))
        G["Trim"].append(cyl("gearbox", 0.36, 0.9, (0.45, -16.6, 6.6), M.STEEL(), "X", segs=14))
        # main rotor: mast, swashplate, hub, pitch links, stabiliser bar, two blades
        G["Trim"].append(cyl("mast", 0.22, 1.9, (0, 0, 7.6), M.STEEL(), "Z", segs=14))
        G["Trim"].append(lathe("swash", [(0.25, 0), (0.75, 0), (0.8, 0.12), (0.75, 0.24), (0.25, 0.24)], M.STEEL(), segs=24, axis="Z", loc=(0, 0, 7.55), close=True))
        blk = M.matte("#1b1c1f", 0.45)
        rp = s["spinners"][0]["pivot"]
        rz = rp[1]
        R = [cyl("hub", 0.55, 0.5, (0, 0, 0), M.STEEL(), "Z", segs=18), box("yoke", (3.2, 0.5, 0.22), (0, 0, 0.05), M.STEEL(), bev=0.08),
             cyl("cap", 0.3, 0.3, (0, 0, 0.35), M.CHROME(), "Z", segs=14), tube("stabbar", [(0, -2.4, -0.25), (0, 2.4, -0.25)], 0.05, M.STEEL(), segs=6)]
        for sy in (-2.4, 2.4):
            R.append(box("stabweight", (0.2, 0.5, 0.2), (0, sy, -0.25), M.STEEL(), bev=0.06))
        for k in range(2):
            b = M.blade("blade", 13.0, 0.9, blk, 9, 2, root=0.1, axis="Z", thick=0.11)
            tip = box("tipcap", (0.9, 0.7, 0.05), (12.6, 0.1, 0), M.mat("TipYellow", "#f2c010", rough=0.5), bev=0.01)
            link = tube("pitchlink", [(0.7, 0.35, -0.7), (0.9, 0.4, 0.0)], 0.04, M.STEEL(), segs=6)
            for o in (b, tip, link):
                o.rotation_euler = (0, 0, math.pi * k)
                M.apply_xf(o)
                R.append(o)
        rotor = M.join(R, "Spin1")
        M.place(rotor, (rp[0], -rp[2], rz))
        G["Spin"].append(rotor)
        tp = s["spinners"][1]["pivot"]
        TR = [cyl("trhub", 0.2, 0.5, (0, 0, 0), M.STEEL(), "X", segs=12)]
        for k in range(2):
            b = M.blade("trblade", 2.5, 0.42, blk, 14, 6, root=0.12, axis="Z", thick=0.12)
            b.rotation_euler = (0, -math.pi / 2, 0)
            M.apply_xf(b)
            b.rotation_euler = (math.pi * k, 0, 0)
            M.apply_xf(b)
            TR.append(b)
        trotor = M.join(TR, "Spin2")
        M.place(trotor, (tp[0], -tp[2], tp[1]))
        G["Spin"].append(trotor)
        # cabin: pilot (right) and co-pilot seats, cyclics, collectives, pedals, console; bench behind
        import rcp_interior as I
        I.helicopter(s, G, body, (-3.1, -1.6, 1.6), (3.1, 4.0, 6.9))
        G["Trim"].append(box("bench", (4.6, 1.3, 0.3), (0, -0.4, 2.6), M.SEAT(), bev=0.1))
        G["Trim"].append(box("benchback", (4.6, 0.25, 1.7), (0, -1.1, 3.45), M.SEAT(), bev=0.1))
        G["Trim"].append(box("panel", (1.9, 0.4, 0.9), (0, 4.8, 3.9), M.INTERIOR(), bev=0.12))
        return G
