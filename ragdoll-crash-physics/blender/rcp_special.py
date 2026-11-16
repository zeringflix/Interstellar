"""Steam locomotive, bulldozer, go-kart and rocket sled."""
import math

from mathutils import Vector

import rcp_model as M
import rcp_cars as C
from rcp_model import box, cyl, lathe, loft, tube, mat, oval
from rcp_military import running_gear


def loco_wheel(x, y, z, r, side, spokes, colour, crank=0.0, pin_angle=0.0):
    """Spoked, flanged locomotive wheel with tyre, counterweight and crank pin."""
    red = colour
    parts = [lathe("tyre", [(r * 0.86, -0.38), (r * 1.06, -0.38), (r * 1.06, -0.26), (r, -0.2), (r * 0.985, 0.38), (r * 0.86, 0.38)], M.STEEL(), segs=40, axis="X", close=True),
             lathe("rim", [(r * 0.74, -0.2), (r * 0.87, -0.2), (r * 0.87, 0.24), (r * 0.74, 0.24)], red, segs=40, axis="X", close=True),
             lathe("boss", [(0, 0.42), (r * 0.2, 0.42), (r * 0.26, 0.3), (r * 0.26, -0.2), (0, -0.2)], red, segs=20, axis="X")]
    for k in range(spokes):
        a = M.TAU * k / spokes
        sp = loft("spoke", [[(0.16, -r * 0.07, r * 0.2), (0.16, r * 0.07, r * 0.2), (-0.1, r * 0.07, r * 0.2), (-0.1, -r * 0.07, r * 0.2)],
                            [(0.12, -r * 0.045, r * 0.76), (0.12, r * 0.045, r * 0.76), (-0.08, r * 0.045, r * 0.76), (-0.08, -r * 0.045, r * 0.76)]], red)
        sp.rotation_euler = (a, 0, 0)
        M.apply_xf(sp)
        parts.append(sp)
    if crank:
        cw = lathe("cw", [(r * 0.45, -0.12), (r * 0.76, -0.12), (r * 0.76, 0.2), (r * 0.45, 0.2)], red, segs=40, axis="X", close=True)
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(cw.data)
        ca, sa = math.cos(pin_angle), math.sin(pin_angle)
        dead = [f for f in bm.faces if (f.calc_center_median().y * ca + f.calc_center_median().z * sa) > -r * 0.42]
        bmesh.ops.delete(bm, geom=dead, context="FACES")
        bmesh.ops.holes_fill(bm, edges=bm.edges[:])
        bm.to_mesh(cw.data)
        bm.free()
        parts.append(cw)
        parts.append(cyl("pin", r * 0.085, 0.7, (0.6, crank * ca, crank * sa), M.STEEL(), "X", segs=12))
    ob = M.join(parts, "locowheel")
    ob.scale.x = side
    return M.place(ob, (x, y, z))


def rod(a, b, x, w=0.3, t=0.14, material=None):
    """Flat-sided connecting / coupling rod between two pins (points in the YZ plane) with round ends."""
    material = material or M.CHROME()
    a, b = Vector((x, a[0], a[1])), Vector((x, b[0], b[1]))
    parts = [tube("rodbar", [a, b], w * 0.5, material, segs=4)]
    for p in (a, b):
        parts.append(cyl("rodeye", w * 0.85, t * 1.6, p, material, "X", segs=14))
    return parts


def register(builder, spec, car_dims):
    @builder("Train")
    def train():
        G = C.new_groups()
        blue = M.paint("#1c4ea6")
        black = M.mat("LocoBlack", "#16171a", rough=0.45, metal=0.3)
        red = M.mat("LocoRed", "#b3201b", rough=0.4)
        brass = M.mat("Brass", "#c9a13b", rough=0.25, metal=1.0)
        BZ, BR = 7.0, 3.3
        # ---- boiler with cladding bands, smokebox, firebox
        boiler = lathe("boiler", [(BR, -5.2), (BR, 16.9)], blue, segs=44, axis="Y", loc=(0, 0, BZ), cap=False)
        G["Body"].append(boiler)
        for y in (-4.6, -1.0, 2.6, 6.2, 9.8, 13.4, 16.6):
            G["Trim"].append(lathe("band", [(BR + 0.03, -0.12), (BR + 0.03, 0.12)], brass, segs=44, axis="Y", loc=(0, y, BZ), cap=False))
        G["Body"].append(lathe("smokebox", [(0, 2.5), (BR * 0.5, 2.5), (BR + 0.16, 2.2), (BR + 0.16, 0), (BR, 0)], black, segs=44, axis="Y", loc=(0, 16.9, BZ)))
        G["Trim"].append(lathe("sbdoor", [(0, 0.62), (0.4, 0.6), (1.8, 0.4), (2.5, 0.12), (2.6, 0)], black, segs=36, axis="Y", loc=(0, 19.38, BZ)))
        G["Trim"].append(tube("dart", [(-0.9, 20.05, BZ), (0.9, 20.05, BZ)], 0.06, M.CHROME(), segs=6))
        G["Trim"].append(tube("dart2", [(0, 20.05, BZ - 0.9), (0, 20.05, BZ + 0.2)], 0.06, M.CHROME(), segs=6))
        for zz in (-1.3, 1.3):
            G["Trim"].append(box("hinge", (2.9, 0.1, 0.16), (-1.2, 19.75, BZ + zz), M.STEEL(), bev=0.03))
        G["Body"].append(box("firebox", (6.9, 5.4, 6.4), (0, -7.0, 6.6), blue, bev=0.5, segs=3))
        # chimney, domes, safety valves, whistle, bell
        G["Trim"].append(lathe("chimney", [(1.15, 0), (0.95, 0.5), (0.82, 1.2), (0.84, 2.6), (1.15, 3.0), (1.22, 3.25), (0.95, 3.3), (0.75, 3.0), (0.75, 0)], black, segs=28, axis="Z", loc=(0, 14.0, BZ + BR - 0.15)))
        G["Trim"].append(lathe("dome", [(1.5, 0), (1.35, 0.4), (1.3, 1.3), (1.0, 1.9), (0.5, 2.15), (0, 2.2)], brass, segs=28, axis="Z", loc=(0, 5.0, BZ + BR - 0.2)))
        G["Body"].append(lathe("sanddome", [(1.25, 0), (1.15, 0.3), (1.1, 1.0), (0.8, 1.4), (0, 1.5)], blue, segs=28, axis="Z", loc=(0, 9.8, BZ + BR - 0.2)))
        for sx in (-0.35, 0.35):
            G["Trim"].append(lathe("valve", [(0.16, 0), (0.16, 0.7), (0.24, 0.8), (0.1, 1.0), (0, 1.0)], brass, segs=12, axis="Z", loc=(sx, -5.2, BZ + BR + 0.1)))
        G["Trim"].append(lathe("whistle", [(0.07, 0), (0.07, 0.6), (0.16, 0.65), (0.16, 1.1), (0, 1.15)], brass, segs=12, axis="Z", loc=(0.9, -4.0, BZ + BR)))
        G["Trim"].append(lathe("bell", [(0.5, 0), (0.42, 0.25), (0.3, 0.6), (0.12, 0.8), (0, 0.82)], brass, segs=20, axis="Z", loc=(0, 1.2, BZ + BR + 0.5)))
        G["Trim"].append(tube("bellyoke", [(-0.65, 1.2, BZ + BR - 0.1), (-0.65, 1.2, BZ + BR + 1.3), (0.65, 1.2, BZ + BR + 1.3), (0.65, 1.2, BZ + BR - 0.1)], 0.06, black, segs=6))
        # headlamp + number plate
        G["Trim"].append(box("lampbracket", (0.9, 0.9, 0.5), (0, 18.6, BZ + BR + 0.25), black, bev=0.05))
        G["Trim"].append(cyl("lampbody", 0.72, 1.1, (0, 18.8, BZ + BR + 1.1), black, "Y", segs=24))
        G["Lights"].append(cyl("lamplens", 0.6, 0.1, (0, 19.38, BZ + BR + 1.1), M.HEADLIGHT(), "Y", segs=24))
        G["Trim"].append(box("plate", (1.9, 0.08, 0.6), (0, 19.2, BZ + 2.0), red, bev=0.03))
        G["Trim"].append(M.text("number", "475", 0.5, (0, 19.25, BZ + 2.0), (math.pi / 2, 0, math.pi), brass, extrude=0.02))
        # running boards, handrails, frames
        for s in (-1, 1):
            G["Body"].append(box("runningboard", (1.5, 26.5, 0.16), (s * 4.0, 6.3, 4.55), black, bev=0.04))
            G["Body"].append(box("frame", (0.3, 36.0, 1.5), (s * 3.3, 0.0, 2.75), black, bev=0.04))
            G["Trim"].append(tube("handrail", [(s * (BR + 0.25) * 0.86, -4.8, BZ + 1.75), (s * (BR + 0.25) * 0.86, 17.5, BZ + 1.75), (s * 2.3, 19.3, BZ + 1.9)], 0.06, M.CHROME(), segs=8))
            for y in (-3, 3, 9, 15):
                G["Trim"].append(tube("stanchion", [(s * BR * 0.86, y, BZ + 1.7), (s * (BR + 0.25) * 0.86, y, BZ + 1.75)], 0.05, brass, segs=6))
            for y in (6.5, 0, -6.5):   # splashers over the driving wheels
                arc = [(s * 4.0, y + 2.45 * math.cos(a), 2.15 + 2.45 * math.sin(a)) for a in [math.radians(d) for d in range(75, 106, 6)]]
                G["Body"].append(loft("splasher", [[(p[0] - 0.7, p[1], p[2]), (p[0] + 0.7, p[1], p[2]), (p[0] + 0.7, p[1], p[2] + 0.1), (p[0] - 0.7, p[1], p[2] + 0.1)] for p in arc], blue))
            # cylinder, slide bars, crosshead, connecting + coupling rods
            cx = s * 4.95
            G["Body"].append(cyl("cylinder", 1.05, 3.4, (cx, 13.6, 2.5), black, "Y", segs=28, bev=0.1))
            G["Trim"].append(cyl("cylcover", 0.8, 0.2, (cx, 15.38, 2.5), M.CHROME(), "Y", segs=24))
            G["Body"].append(box("steamchest", (1.5, 3.0, 1.0), (cx - s * 0.2, 13.6, 3.85), black, bev=0.1))
            G["Trim"].append(cyl("pistonrod", 0.1, 3.4, (cx, 10.4, 2.5), M.CHROME(), "Y", segs=8))
            for zz in (2.95, 2.05):
                G["Trim"].append(box("slidebar", (0.22, 3.6, 0.16), (cx, 10.0, zz), M.CHROME(), bev=0.02))
            G["Trim"].append(box("crosshead", (0.5, 0.8, 0.9), (cx, 9.2, 2.5), M.STEEL(), bev=0.06))
            pa = math.radians(-65)
            pins = [(y + 0.95 * math.cos(pa), 2.1 + 0.95 * math.sin(pa)) for y in (6.5, 0, -6.5)]
            G["Trim"] += rod(pins[0], pins[1], s * 5.05) + rod(pins[1], pins[2], s * 5.05)
            G["Trim"] += rod((9.2, 2.5), pins[1], s * 5.35, w=0.34)
            for y in (6.5, 0, -6.5):
                G["Trim"].append(loco_wheel(s * 4.3, y, 2.1, 2.1, s, 14, red, 0.95, pa))
            for y in (13.0, -13.0):
                G["Trim"].append(loco_wheel(s * 4.3, y, 1.5, 1.5, s, 10, red))
            G["Trim"].append(tube("pipe", [(s * 2.9, 4.5, 4.7), (s * 3.5, 4.5, 4.0), (s * 3.5, 12.0, 4.0), (s * 4.4, 13.0, 4.2)], 0.1, brass, segs=8, smooth=3))
            # cab side
            G["Glass"].append(box("cabwindow", (0.06, 2.6, 2.2), (s * 4.52, -12.6, 9.4), M.GLASS(), bev=0.01))
            G["Trim"].append(box("cabwinframe", (0.1, 3.0, 2.6), (s * 4.5, -12.6, 9.4), brass, bev=0.03))
            G["Trim"].append(M.text("rcp", "R C P", 0.9, (s * 4.56, -12.6, 6.6), (math.pi / 2, 0, s * math.pi / 2), brass, extrude=0.02))
            G["Trim"].append(tube("cabrail", [(s * 4.6, -16.9, 4.4), (s * 4.6, -16.9, 9.6)], 0.06, M.CHROME(), segs=8))
            for zz in (2.2, 3.2):
                G["Trim"].append(box("cabstep", (1.0, 1.3, 0.1), (s * 4.6, -16.2, zz), black, bev=0.02))
            G["Glass"].append(cyl("spectacle", 0.75, 0.08, (s * 2.6, -6.95, 10.0), M.GLASS(), "Y", segs=24))
            G["Trim"].append(lathe("specring", [(0.75, 0), (0.9, 0), (0.9, 0.12), (0.75, 0.12)], brass, segs=24, axis="Y", loc=(s * 2.6, -6.92, 10.0), close=True))
            G["Lights"].append(cyl("buflamp", 0.26, 0.4, (s * 3.4, 19.2, 3.9), M.HEADLIGHT(), "Y", segs=14))
            G["Trim"].append(cyl("buffer", 0.55, 0.3, (s * 2.8, -20.05, 3.0), M.STEEL(), "Y", segs=20))
            G["Trim"].append(cyl("bufferstem", 0.2, 0.8, (s * 2.8, -19.6, 3.0), black, "Y", segs=10))
        for y in (13.0, 6.5, 0, -6.5, -13.0):
            G["Trim"].append(cyl("axle", 0.22, 8.4, (0, y, 2.1 if abs(y) < 10 else 1.5), M.STEEL(), "X", segs=10))
        # cab: walls with door openings, arched roof
        cab = box("cab", (9.0, 9.6, 7.2), (0, -12.0, 7.6), blue, bev=0.12)
        G["Body"].append(cab)
        roof = loft("cabroof", [[(x, y, 11.3 + 0.9 * math.cos(x / 5.1 * math.pi / 2)) for x in (-5.1, -3.8, -2, 0, 2, 3.8, 5.1)] + [(x, y, 11.05 + 0.9 * math.cos(x / 5.1 * math.pi / 2)) for x in (5.1, 3.8, 2, 0, -2, -3.8, -5.1)]
                                for y in (-17.6, -6.4)], black)
        G["Body"].append(roof)
        G["Trim"].append(box("cabback", (3.2, 0.1, 4.6), (0, -16.86, 7.2), M.matte("#0c0c0d", 0.9), bev=0.02))
        # pilot (cowcatcher): slatted wedge
        G["Body"].append(box("bufferbeamF", (9.4, 0.7, 1.4), (0, 19.3, 2.9), red, bev=0.08))
        G["Body"].append(box("bufferbeamR", (9.4, 0.7, 1.4), (0, -19.4, 2.9), red, bev=0.08))
        for k in range(13):
            xk = (k - 6) * 0.7
            G["Body"].append(tube("pilotbar", [(xk, 19.6, 3.4), (xk * 0.42, 23.2, 0.55)], 0.11, red, segs=6))
        G["Body"].append(tube("pilotbase", [(-4.3, 19.7, 0.6), (-1.8, 23.3, 0.5), (1.8, 23.3, 0.5), (4.3, 19.7, 0.6)], 0.16, red, segs=8))
        G["Trim"].append(tube("coupler", [(0, 19.5, 2.6), (0, 21.0, 2.4)], 0.2, black, segs=10))
        G["Trim"].append(tube("couplerR", [(0, -19.5, 2.6), (0, -20.6, 2.6)], 0.22, black, segs=10))
        return G

    @builder("Bulldozer")
    def bulldozer():
        G = C.new_groups()
        yel = M.paint("#f0b60a")
        blk = M.mat("DozerBlack", "#1a1b1e", rough=0.6, metal=0.2)
        # main frame, engine bonnet with grille + louvres
        G["Body"].append(box("mainframe", (7.6, 12.0, 2.6), (0, -1.0, 3.3), yel, bev=0.15))
        G["Body"].append(box("bonnet", (5.0, 6.4, 2.6), (0, 2.2, 5.6), yel, bev=0.3, segs=3))
        G["Trim"].append(box("grille", (4.2, 0.12, 3.6), (0, 5.42, 4.9), blk, bev=0.04))
        for k in range(9):
            G["Trim"].append(box("grillebar", (4.0, 0.1, 0.12), (0, 5.5, 3.4 + k * 0.38), M.STEEL(), bev=0.02))
        for s in (-1, 1):
            for k in range(6):
                G["Trim"].append(box("louvre", (0.08, 0.5, 1.2), (s * 2.52, 0.3 + k * 0.75, 5.6), blk, bev=0.02))
            G["Trim"].append(M.text("model", "RCP D9", 0.55, (s * 2.56, 3.0, 6.55), (math.pi / 2, 0, s * math.pi / 2), blk))
        G["Trim"].append(cyl("stack", 0.24, 3.0, (1.5, 3.4, 8.3), blk, "Z", segs=16))
        G["Trim"].append(box("raincap", (0.6, 0.6, 0.06), (1.5, 3.5, 9.9), blk, bev=0.02, rot=(math.radians(25), 0, 0)))
        G["Trim"].append(lathe("precleaner", [(0.18, 0), (0.18, 0.9), (0.45, 1.0), (0.45, 1.5), (0.3, 1.7), (0, 1.7)], blk, segs=18, axis="Z", loc=(-1.5, 3.0, 6.9)))
        # ROPS cab with real glass panes
        for sx in (-2.9, 2.9):
            for sy in (-5.8, -1.4):
                G["Body"].append(box("post", (0.4, 0.4, 3.6), (sx, sy, 6.5), yel, bev=0.06))
        G["Body"].append(box("roof", (6.8, 5.6, 0.4), (0, -3.6, 8.5), yel, bev=0.12))
        G["Body"].append(box("cabbase", (6.2, 4.8, 0.5), (0, -3.6, 4.75), yel, bev=0.08))
        glass = M.GLASS()
        G["Glass"] += [box("gF", (5.4, 0.06, 3.0), (0, -1.4, 6.6), glass, bev=0.01), box("gR", (5.4, 0.06, 3.0), (0, -5.8, 6.6), glass, bev=0.01),
                       box("gL", (0.06, 4.0, 3.0), (-2.9, -3.6, 6.6), glass, bev=0.01), box("gRt", (0.06, 4.0, 3.0), (2.9, -3.6, 6.6), glass, bev=0.01)]
        G["Trim"] += [box("seat", (1.6, 1.4, 0.35), (0, -4.0, 5.5), M.SEAT(), bev=0.1), box("seatback", (1.6, 0.3, 1.7), (0, -4.7, 6.3), M.SEAT(), bev=0.1)]
        for sx in (-1.2, 1.2):
            G["Trim"].append(tube("lever", [(sx, -2.6, 5.0), (sx, -2.9, 6.2)], 0.05, blk, segs=6))
            G["Trim"].append(cyl("knob", 0.11, 0.2, (sx, -2.9, 6.3), blk, "Z", segs=10))
        for sx in (-2.4, -0.8, 0.8, 2.4):
            G["Lights"].append(box("worklight", (0.6, 0.3, 0.4), (sx, -0.95, 8.95), M.HEADLIGHT(), bev=0.08))
        G["Body"].append(box("fueltank", (6.4, 1.6, 2.6), (0, -6.9, 5.9), yel, bev=0.2))
        # undercarriage
        for s in (-1, 1):
            G["Body"].append(box("trackframe", (1.3, 10.6, 1.0), (s * 5.2, -1.0, 1.25), blk, bev=0.1))
            G["Trim"].append(box("fenderstep", (2.4, 12.0, 0.14), (s * 5.2, -1.2, 3.25), blk, bev=0.03))
            G["Trim"].append(tube("handrail", [(s * 3.9, -1.2, 3.3), (s * 3.9, -1.2, 5.6), (s * 3.9, 2.0, 5.8)], 0.05, blk, segs=6))
        running_gear(G, 5.2, 2.4, blk, [3.4, 1.2, -1.0, -3.2, -5.2], 0.66, 0.52,
                     (-7.2, 1.55, 1.2), (5.4, 1.4, 1.12), [(-2.5, 2.62, 0.28), (1.8, 2.6, 0.28)], pitch=0.74)
        # blade: curved mouldboard + side plates + cutting edge + ribs
        def arc(x, back=0.0):
            pts = []
            for k in range(9):
                t = k / 8
                pts.append((x, 9.55 - 0.95 * math.sin(math.pi * (0.1 + 0.8 * t)) - back, 0.3 + 4.6 * t))
            return pts
        rings = [arc(x) + list(reversed(arc(x, 0.28))) for x in (-7.5, -2.5, 2.5, 7.5)]
        G["Body"].append(loft("mouldboard", rings, yel))
        for s in (-1, 1):
            G["Body"].append(loft("sideplate", [[(s * 7.5, 10.2, 0.25), (s * 7.5, 8.2, 0.25), (s * 7.5, 8.2, 5.0), (s * 7.5, 9.9, 5.0)],
                                                 [(s * 7.7, 10.2, 0.25), (s * 7.7, 8.2, 0.25), (s * 7.7, 8.2, 5.0), (s * 7.7, 9.9, 5.0)]], yel, smooth=False))
            for x in (s * 2.6, s * 5.6):
                G["Body"].append(box("rib", (0.3, 0.9, 4.2), (x, 8.45, 2.6), yel, bev=0.04))
            # push arm, tilt brace, lift cylinder
            G["Body"].append(box("pusharm", (0.8, 9.6, 1.0), (s * 6.9, 3.6, 1.6), yel, bev=0.1))
            G["Trim"].append(cyl("trunnion", 0.5, 1.0, (s * 6.6, -1.0, 1.6), M.STEEL(), "X", segs=16))
            G["Trim"].append(tube("brace", [(s * 6.9, 5.0, 2.0), (s * 6.4, 8.3, 4.0)], 0.18, blk, segs=10))
            G["Trim"].append(tube("liftbarrel", [(s * 3.0, 4.6, 6.3), (s * 3.0, 6.5, 5.0)], 0.32, yel, segs=14))
            G["Trim"].append(tube("liftrod", [(s * 3.0, 6.5, 5.0), (s * 3.0, 8.2, 3.8)], 0.17, M.CHROME(), segs=12))
            G["Trim"].append(tube("hose", [(s * 2.7, 4.2, 6.2), (s * 2.5, 5.2, 6.6), (s * 2.9, 6.3, 5.4)], 0.06, blk, segs=6, smooth=4))
        G["Trim"].append(box("cuttingedge", (15.2, 0.25, 0.7), (0, 9.42, 0.45), M.STEEL(), bev=0.03, rot=(math.radians(-18), 0, 0)))
        G["Body"].append(box("spillguard", (15.0, 0.2, 0.7), (0, 9.2, 5.2), yel, bev=0.04, rot=(math.radians(20), 0, 0)))
        # rear ripper
        G["Body"].append(box("ripperbeam", (8.0, 1.0, 1.0), (0, -8.6, 3.2), yel, bev=0.1))
        for sx in (-2.8, 0, 2.8):
            G["Trim"].append(loft("shank", [[(sx - 0.2, -8.3, 3.6), (sx + 0.2, -8.3, 3.6), (sx + 0.2, -8.9, 3.6), (sx - 0.2, -8.9, 3.6)],
                                            [(sx - 0.2, -8.6, 1.8), (sx + 0.2, -8.6, 1.8), (sx + 0.2, -9.3, 1.8), (sx - 0.2, -9.3, 1.8)],
                                            [(sx - 0.15, -8.2, 0.5), (sx + 0.15, -8.2, 0.5), (sx + 0.15, -8.9, 0.7), (sx - 0.15, -8.9, 0.7)],
                                            [(sx - 0.1, -7.5, 0.2), (sx + 0.1, -7.5, 0.2), (sx + 0.1, -7.7, 0.35), (sx - 0.1, -7.7, 0.35)]], M.STEEL(), smooth=False))
        for sx in (-2.0, 2.0):
            G["Trim"].append(tube("ripcyl", [(sx, -7.4, 5.0), (sx, -8.4, 3.7)], 0.25, yel, segs=12))
            G["Lights"].append(box("tail", (0.5, 0.15, 0.3), (sx * 1.3, -7.75, 6.9), M.TAILLIGHT(), bev=0.05))
        return G

    @builder("GoKart")
    def gokart():
        s = spec("GoKart")
        G = C.new_groups()
        red = M.paint("#d8231c")
        frame = M.mat("KartFrame", "#23252a", rough=0.35, metal=0.8)
        z = 0.5
        # welded tube chassis
        for sx in (-1, 1):
            G["Trim"].append(tube("rail", [(sx * 0.9, 3.5, z), (sx * 1.15, 1.6, z), (sx * 1.5, -0.6, z), (sx * 1.5, -3.2, z)], 0.09, frame, segs=10, smooth=4))
            G["Trim"].append(tube("nerf", [(sx * 1.5, 1.4, z), (sx * 2.35, 1.0, z + 0.25), (sx * 2.35, -1.6, z + 0.25), (sx * 1.5, -2.0, z)], 0.08, M.CHROME(), segs=10, smooth=4))
            pod = loft("pod", [oval(1.5, 0.2, 0.16, z + 0.38, 12, 2.2, sx * 2.05), oval(0.9, 0.5, 0.3, z + 0.42, 12, 2.2, sx * 2.05), oval(-1.0, 0.55, 0.32, z + 0.44, 12, 2.2, sx * 2.05), oval(-1.9, 0.25, 0.2, z + 0.42, 12, 2.2, sx * 2.05)], red)
            M.subsurf(pod, 1)
            G["Body"].append(pod)
            G["Trim"].append(tube("stub", [(sx * 0.95, 2.6, z + 0.1), (sx * 1.9, 2.6, 0.8)], 0.07, frame, segs=8))
            G["Trim"].append(tube("tierod", [(0, 2.2, z + 0.2), (sx * 1.8, 2.3, 0.75)], 0.035, M.CHROME(), segs=6))
        for y in (3.5, 1.6, -1.0, -3.2):
            w = 0.9 if y > 2 else (1.15 if y > 0 else 1.5)
            G["Trim"].append(tube("cross", [(-w, y, z), (w, y, z)], 0.08, frame, segs=10))
        G["Trim"].append(tube("bumperF", [(-1.7, 3.4, z + 0.05), (-1.9, 4.0, z + 0.1), (0, 4.3, z + 0.1), (1.9, 4.0, z + 0.1), (1.7, 3.4, z + 0.05)], 0.08, M.CHROME(), segs=10, smooth=4))
        G["Trim"].append(tube("bumperR", [(-1.5, -3.2, z), (-1.9, -3.9, z + 0.35), (1.9, -3.9, z + 0.35), (1.5, -3.2, z)], 0.08, M.CHROME(), segs=10, smooth=4))
        G["Trim"].append(box("floorpan", (1.9, 2.6, 0.04), (0, 2.3, z - 0.05), M.ALLOY(), bev=0.01))
        # nose cone + number panel
        nose = loft("nose", [oval(4.4, 0.25, 0.12, z + 0.3, 12, 2.2), oval(3.7, 0.95, 0.3, z + 0.42, 12, 2.2), oval(2.7, 0.85, 0.42, z + 0.55, 12, 2.2), oval(2.2, 0.5, 0.3, z + 0.5, 12, 2.2)], red)
        M.subsurf(nose, 1)
        G["Body"].append(nose)
        G["Body"].append(box("numberpanel", (1.1, 0.08, 0.8), (0, 1.75, z + 1.55), red, bev=0.12, rot=(math.radians(-35), 0, 0)))
        G["Trim"].append(M.text("number", "7", 0.6, (0, 1.82, z + 1.56), (math.radians(125), 0, math.pi), M.matte("#f4f4f4", 0.5), extrude=0.01))
        # steering
        G["Trim"].append(tube("column", [(0, 2.4, z + 0.15), (0, 1.25, z + 1.75)], 0.06, frame, segs=8))
        wc = Vector((0, 1.2, z + 1.8))
        ax = Vector((0, -1.15, 1.6)).normalized()
        u, v = Vector((1, 0, 0)), ax.cross(Vector((1, 0, 0))).normalized()
        G["Trim"].append(tube("wheelrim", [wc + (u * math.cos(a) + v * math.sin(a)) * 0.62 for a in [M.TAU * k / 22 for k in range(22)]], 0.06, M.DARK(), segs=8, closed=True))
        for a in (math.radians(90), math.radians(210), math.radians(330)):
            G["Trim"].append(tube("spoke", [wc, wc + (u * math.cos(a) + v * math.sin(a)) * 0.6], 0.04, M.ALLOY(), segs=6))
        for sx in (-0.55, 0.55):
            G["Trim"].append(box("pedal", (0.3, 0.06, 0.5), (sx, 3.3, z + 0.3), M.ALLOY(), bev=0.02, rot=(math.radians(-25), 0, 0)))
        # bucket seat
        seat = loft("seat", [[(x, -0.2 + 0.1 * abs(x), z + 0.25 + 0.5 * (abs(x) / 0.85) ** 3) for x in (-0.9, -0.6, 0, 0.6, 0.9)],
                             [(x, -1.2, z + 0.12 + 0.75 * (abs(x) / 0.85) ** 3) for x in (-0.9, -0.6, 0, 0.6, 0.9)],
                             [(x, -1.75 + 0.12 * abs(x), z + 0.5 + 0.9 * (abs(x) / 0.85) ** 3) for x in (-0.9, -0.6, 0, 0.6, 0.9)],
                             [(x * 0.92, -2.05 + 0.2 * abs(x), z + 1.45) for x in (-0.9, -0.6, 0, 0.6, 0.9)],
                             [(x * 0.75, -2.2 + 0.2 * abs(x), z + 2.25) for x in (-0.9, -0.6, 0, 0.6, 0.9)]], M.matte("#141416", 0.6), closed=False, cap=False)
        M.subsurf(seat, 2)
        M.solidify(seat, 0.06)
        G["Trim"].append(seat)
        # engine: finned cylinder, head, air filter, exhaust, tank, chain drive
        ex = 1.05
        G["Trim"].append(box("crankcase", (0.9, 1.1, 0.7), (ex, -2.2, z + 0.4), M.ALLOY(), bev=0.1))
        for k in range(7):
            G["Trim"].append(box("fin", (0.95, 0.9, 0.035), (ex, -2.15, z + 0.85 + k * 0.09), M.ALLOY(), bev=0.01, segs=1))
        G["Trim"].append(box("head", (0.7, 0.7, 0.2), (ex, -2.15, z + 1.55), M.STEEL(), bev=0.05))
        G["Trim"].append(cyl("airfilter", 0.3, 0.6, (ex + 0.1, -1.3, z + 1.25), M.mat("Filter", "#b3201b", rough=0.6), "Y", segs=18))
        G["Trim"].append(tube("exhaust", [(ex, -2.6, z + 1.1), (ex + 0.2, -3.2, z + 1.0), (ex + 0.25, -3.6, z + 0.75)], 0.09, M.CHROME(), segs=10, smooth=4))
        G["Trim"].append(cyl("muffler", 0.2, 1.0, (ex + 0.25, -3.75, z + 0.6), M.CHROME(), "X", segs=16))
        G["Trim"].append(cyl("fueltank", 0.32, 0.9, (0, 1.9, z + 0.75), M.matte("#e8e8e4", 0.4), "X", segs=18, bev=0.1))
        ya = -s["wheels"][2]["pos"][2]
        G["Trim"].append(cyl("rearaxle", 0.09, 4.4, (0, ya, 0.8), M.CHROME(), "X", segs=12))
        G["Trim"].append(cyl("sprocket", 0.42, 0.04, (0.55, ya, 0.8), M.STEEL(), "X", segs=28, bev=0))
        G["Trim"].append(cyl("brakedisc", 0.38, 0.04, (-0.6, ya, 0.8), M.STEEL(), "X", segs=28, bev=0))
        G["Trim"].append(box("chainguard", (0.12, 1.3, 0.55), (0.55, ya + 0.45, 0.95), M.DARK(), bev=0.08))
        for i, w in enumerate(s["wheels"]):
            x, y, zz = w["pos"][0], -w["pos"][2], w["pos"][1]
            parts = M.tyre(w["radius"], w["width"], w["radius"] * 0.55, grooves=0, bulge=0.1)
            rim = lathe("rim", [(0, 0.2), (w["radius"] * 0.5, 0.2), (w["radius"] * 0.57, 0.3), (w["radius"] * 0.57, -0.3), (0, -0.3)], M.mat("KartRim", "#f0c20f", rough=0.3, metal=0.8), segs=24, axis="X")
            ob = M.join(parts + [rim], "Wheel%d" % (i + 1))
            if x < 0:
                ob.scale.x = -1
            M.place(ob, (x, y, zz))
            M.set_origin(ob, (x, y, zz))
            G["Wheels"].append(ob)
        return G

    @builder("RocketSled")
    def sled():
        G = C.new_groups()
        white, red = M.paint("#eeeff1"), M.paint("#d8231c")
        steel = M.mat("SledSteel", "#3a3d43", rough=0.4, metal=0.85)
        # truss frame on four slipper shoes
        for s in (-1, 1):
            G["Trim"].append(box("longeron", (0.5, 16.4, 0.5), (s * 2.6, 0, 0.95), steel, bev=0.06))
            G["Trim"].append(tube("upper", [(s * 1.9, 7.5, 1.7), (s * 1.9, -7.8, 1.9)], 0.14, steel, segs=8))
            for k in range(8):
                y0 = 7.4 - k * 2.15
                a, b = (s * 2.6, y0, 1.15), (s * 1.9, y0 - 1.07, 1.8)
                G["Trim"].append(tube("truss", [a, b, (s * 2.6, y0 - 2.15, 1.15)], 0.07, steel, segs=6))
            for y in (6.6, -6.6):   # slipper wrapping the rail head
                G["Trim"].append(box("slipper", (1.0, 2.2, 0.5), (s * 2.6, y, 0.45), M.STEEL(), bev=0.08))
                G["Trim"].append(box("slipperlip", (0.25, 2.2, 0.5), (s * 3.15, y, 0.2), M.STEEL(), bev=0.05))
            G["Body"].append(M.airfoil("fin", [((s * 2.7, -5.0, 1.6), 3.4, 0, "Z"), ((s * 2.7, -6.2, 4.1), 1.8, 0, "Z")], red, 0.07, 0))
        for y in (7.4, 3.0, -1.5, -6.0, -8.0):
            G["Trim"].append(tube("cross", [(-2.6, y, 1.15), (2.6, y, 1.15)], 0.12, steel, segs=8))
        G["Body"].append(box("deck", (4.6, 15.8, 0.12), (0, 0, 1.3), white, bev=0.03))
        # ogive nose fairing with canopy
        st = [oval(13.2, 0.06, 0.06, 1.75, 16, 2.2), oval(12.2, 0.55, 0.45, 1.8, 16, 2.2), oval(10.5, 1.25, 0.95, 1.95, 16, 2.2), oval(8.5, 1.85, 1.35, 2.2, 16, 2.2),
              oval(6.5, 2.2, 1.6, 2.4, 16, 2.2), oval(4.2, 2.25, 1.65, 2.45, 16, 2.2), oval(2.2, 2.1, 1.3, 2.3, 16, 2.2), oval(1.2, 1.5, 0.6, 2.0, 16, 2.2)]
        fl = ["", "", "", "", "", "", "", ""]
        nose = loft("nose", st, materials=[white, M.GLASS(), red], mat_fn=lambda i, j: 2 if i < 2 else (1 if (i in (4, 5) and j in (2, 3, 4, 5)) else 0))
        M.subsurf(nose, 2)
        surf = M.Surface(nose)
        body, glass = C.split_glass(nose)
        G["Body"].append(body)
        G["Glass"].append(glass)
        for side in ("L", "R"):
            sg = 1 if side == "R" else -1
            G["Body"].append(surf.project("stripe", side, (2.0, 1.75, 11.5, 2.0), red, 0.012, res=0.15))
            loc, _ = surf.point(side, 6.0, 2.6)
            if loc is not None:
                G["Trim"].append(M.text("name", "RCP-1", 0.55, (loc.x + sg * 0.04, 6.0, 2.6), (math.pi / 2, 0, sg * math.pi / 2), M.matte("#14161a", 0.5)))
        G["Trim"].append(tube("pitot", [(0, 13.2, 1.75), (0, 15.0, 1.75)], 0.035, M.CHROME(), segs=6))
        G["Trim"] += [box("seat", (1.5, 1.4, 0.3), (0, 4.2, 1.6), M.SEAT(), bev=0.1), box("seatback", (1.5, 0.3, 1.9), (0, 3.4, 2.5), M.SEAT(), bev=0.1, rot=(math.radians(-14), 0, 0)),
                      box("headrest", (0.8, 0.3, 0.5), (0, 3.15, 3.55), M.SEAT(), bev=0.1)]
        # twin solid rocket motors with bands, domes and bell nozzles
        for s in (-1, 1):
            x = s * 1.25
            motor = [(0, 10.6), (0.5, 10.5), (0.9, 10.0), (1.0, 9.4), (1.0, 0.4), (0.85, 0.1), (0.45, -0.3), (0.38, -0.6), (0.6, -1.1), (0.92, -1.9), (0.98, -2.2),
                     (0.9, -2.2), (0.55, -1.15), (0.3, -0.6), (0, -0.6)]
            G["Body"].append(lathe("motor", motor, white, segs=32, axis="Y", loc=(x, -8.6, 3.0)))
            for y in (0.2, -2.5, -5.2, -7.9):
                G["Trim"].append(lathe("band", [(1.03, -0.12), (1.03, 0.12)], red, segs=32, axis="Y", loc=(x, y, 3.0), cap=False))
                G["Trim"].append(box("cradle", (2.2, 0.3, 1.2), (x, y, 1.9), steel, bev=0.05))
            G["Trim"].append(lathe("nozzle", [(0.4, 0), (0.62, -0.5), (0.95, -1.3), (1.0, -1.6), (1.04, -1.6), (0.68, -0.5), (0.46, 0)], M.mat("Nozzle", "#2a2b2e", rough=0.35, metal=0.9), segs=32, axis="Y", loc=(x, -9.2, 3.0), close=True))
            flame = lathe("flame", [(0.0, 0.0), (0.7, -0.3), (0.82, -1.2), (0.6, -2.8), (0.25, -4.4), (0, -5.4)], M.mat("Flame", "#ff8a1a", rough=0.5, emit=6.0), segs=20, axis="Y", loc=(x, -10.3, 3.0))
            core = lathe("flamecore", [(0.0, 0.0), (0.4, -0.3), (0.45, -1.0), (0.25, -2.4), (0, -3.4)], M.mat("FlameCore", "#fff3c0", rough=0.5, emit=10.0), segs=16, axis="Y", loc=(x, -10.35, 3.0))
            G["Lights"] += [flame, core]
        G["Trim"].append(box("brakescoop", (2.4, 1.6, 0.5), (0, -7.0, 0.55), steel, bev=0.08, rot=(math.radians(12), 0, 0)))
        for k in range(6):
            G["Trim"].append(box("hazard", (0.5, 0.02, 0.5), (-1.5 + k * 0.6, -7.92, 1.6), M.matte("#f2c010" if k % 2 == 0 else "#141416", 0.5), bev=0.0))
        return G
