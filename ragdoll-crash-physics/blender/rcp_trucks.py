"""School bus, dump truck and armoured truck."""
import math

import bpy
from mathutils import Vector

import rcp_model as M
import rcp_cars as C
from rcp_model import box, cyl, lathe, loft, tube, mat, section, oval


def place_wheels(G, wheels, style, rim=None, rim_frac=0.6):
    for i, w in enumerate(wheels):
        x, y, z = w["pos"][0], -w["pos"][2], w["pos"][1]
        ob = M.wheel("Wheel%d" % (i + 1), w["radius"], w["width"], style, 1 if x > 0 else -1, rim, rim_frac=rim_frac)
        M.place(ob, (x, y, z))
        M.set_origin(ob, (x, y, z))
        G["Wheels"].append(ob)


def shell_from(stations, materials, subdiv=2):
    rings = [s[0] for s in stations]
    flags = [s[1] for s in stations]

    def mat_fn(i, j):
        f = flags[i]
        if f == "glass" and j in M.SIDE_GLASS:
            return 1
        if f == "ws" and j in M.TOP_STRIPS:
            return 1
        return 0
    sh = loft("shell", rings, materials=materials, mat_fn=mat_fn)
    M.subsurf(sh, subdiv)
    return sh


def register(builder, spec, car_dims):
    @builder("CityBus")
    def bus():
        """Low-floor 12 m transit bus: raked one-piece windscreen, glazed sides with real pillars,
        two double doors, roof pods, LED destination sign, full saloon interior."""
        s = spec("CityBus")
        G = C.new_groups()
        white = M.paint("#eef0f2")
        teal = M.paint("#0b8f8a")
        blk = M.matte("#111214", 0.5)
        hw, c, belt, roof = 4.5, 1.1, 3.75, 8.2
        S = []
        add = lambda y, w, zf, zb, zd, wd, flag="", cr=0.1: S.append((section(y, hw * w, zf, zb, zd, hw * wd, cr, 0, 0.93), flag))
        add(-18.05, 0.9, c + 0.6, belt, roof - 1.0, 0.72, cr=0.04)
        add(-17.85, 0.99, c + 0.1, belt + 1.2, roof - 0.3, 0.88)
        add(-17.0, 1.0, c, belt + 1.2, roof, 0.9)            # engine bay: high waist, no glass
        add(-14.6, 1.0, c, belt, roof, 0.9)
        y = -14.2
        for k in range(8):   # eight glazed bays, slim pillars
            add(y, 1.0, c, belt, roof, 0.9, "glass")
            add(y + 3.25, 1.0, c, belt, roof, 0.9, "")
            y += 3.6
        add(14.7, 1.0, c, belt - 0.5, roof, 0.9, "glass")     # driver's side window, lower sill
        add(16.9, 0.99, c, belt - 0.5, roof - 0.05, 0.88, "ws")
        add(17.85, 0.95, c + 0.05, belt - 0.6, belt - 0.2, 0.84, cr=0.05)   # base of the raked screen
        add(18.05, 0.86, c + 0.5, belt - 1.4, belt - 1.2, 0.7, cr=0.03)
        shell = shell_from(S, [white, M.GLASS()])
        ws = s["wheels"]
        for w in ws[::2]:
            M.cut_arch(shell, -w["pos"][2], w["radius"] * 0.98, w["radius"] * 1.14, 2.6)
        surf = M.Surface(shell)
        body, glass = C.split_glass(shell)
        G["Body"].append(body)
        G["Glass"].append(glass)
        P = surf.project
        led = M.mat("LED", "#ffa21a", rough=0.4, emit=2.5)
        for side in ("L", "R"):
            sg = 1 if side == "R" else -1
            # livery: teal skirt band sweeping up at the rear
            G["Body"].append(P("skirt", side, (-17.6, c + 0.15, 17.4, 2.35), teal, 0.012, res=0.3))
            G["Body"].append(P("sweep", side, (-17.6, 2.35, -12.0, belt + 1.1), teal, 0.012, res=0.3))
            G["Trim"].append(P("windowband", side, (-14.5, belt - 0.12, 16.8, belt + 0.02), blk, 0.014, res=0.3))
            G["Trim"].append(P("cantrail", side, (-14.5, roof - 0.62, 16.8, roof - 0.5), blk, 0.014, res=0.3))
            loc, _ = surf.point(side, -15.8, belt + 0.5)
            G["Trim"].append(M.text("fleet", "4207", 0.6, (loc.x + sg * 0.03, -15.8, belt + 0.5), (math.pi / 2, 0, sg * math.pi / 2), blk))
            loc, _ = surf.point(side, 2.0, 2.95)
            G["Trim"].append(M.text("operator", "RCP TRANSIT", 0.7, (loc.x + sg * 0.03, 2.0, 2.95), (math.pi / 2, 0, sg * math.pi / 2), M.matte("#0b8f8a", 0.5)))
            G["Lights"].append(P("sidemarker", side, (17.0, 2.5, 17.35, 2.7), M.AMBER(), 0.02))
            for yy in (-12.5, -6, 0.5, 7):
                G["Lights"].append(P("marker", side, (yy, c + 0.5, yy + 0.3, c + 0.62), M.AMBER(), 0.02))
            # lower body service panels between the axles, each with a flush latch; skip the kerb-side door
            for y0, y1 in ((-8.0, -5.4), (-5.1, -2.0), (2.1, 5.2), (5.5, 9.0)):
                if side == "R" and y1 > -1.8 and y0 < 1.9:
                    continue
                G["Trim"].append(C.groove_path(surf, side, C.rounded_rect(y0, c + 0.42, y1, 2.25, 0.12), blk, radius=0.02))
                G["Trim"] += C.latch(surf, side, (y0 + y1) / 2, 2.0, M.CHROME())
            if side == "L":  # fuel flap and the engine bay radiator grille at the rear corner
                G["Trim"].append(C.groove_path(surf, side, C.rounded_rect(-9.4, 1.55, -8.5, 2.3, 0.1), blk, radius=0.02))
                G["Trim"].append(P("radgrille", side, (-16.6, 2.0, -13.6, 4.2), blk, 0.012, res=0.1, round_r=0.12))
                for k in range(8):
                    G["Trim"].append(P("radslat", side, (-16.5, 2.12 + k * 0.26, -13.7, 2.2 + k * 0.26), M.STEEL(), 0.03, thickness=0.02))
            for yy in (9.0, -8.1):  # rubber mud flaps behind each axle
                G["Trim"].append(box("mudflap", (0.9, 0.08, 1.3), (sg * 3.95, yy, 1.05), M.RUBBER(), bev=0.02))
            # drop-arm mirrors
            loc, _ = surf.point(side, 16.0, 6.9)
            G["Trim"].append(tube("mirrorarm", [(loc.x, 17.2, 7.3), (loc.x + sg * 0.9, 18.0, 7.2), (loc.x + sg * 1.0, 18.3, 6.2)], 0.07, blk, segs=8, smooth=4))
            G["Trim"].append(box("mirror", (0.16, 0.6, 1.5), (loc.x + sg * 1.0, 18.3, 5.6), blk, bev=0.08))
        # doors (kerb side): front and centre double doors, each leaf glazed
        for y0 in (13.3, -1.6):
            G["Trim"].append(P("doorframe", "R", (y0 - 0.1, c + 0.25, y0 + 3.3, roof - 0.55), blk, 0.016, res=0.12))
            for k in range(2):
                a = y0 + 0.08 + k * 1.6
                G["Body"].append(P("leaf", "R", (a, c + 0.35, a + 1.5, roof - 0.65), white, 0.03, res=0.2))
                G["Glass"].append(P("leafglass", "R", (a + 0.12, c + 1.0, a + 1.38, roof - 0.85), M.GLASS(), 0.045, res=0.15, round_r=0.1))
            mid = y0 + 1.64  # rubber centre seal where the two leaves meet
            G["Trim"].append(C.groove_path(surf, "R", [(mid, c + 0.35 + (roof - 1.0 - c) * k / 10) for k in range(11)], M.RUBBER(), radius=0.05, sink=0.03))
            G["Trim"].append(C.groove_path(surf, "R", [(y0 - 0.05 + 3.3 * k / 12, roof - 0.5) for k in range(13)], M.STEEL(), radius=0.06, sink=0.05))  # door rail
        # front: sign, lamps, wipers, bumper, bike-rack bar
        G["Trim"].append(box("signbox", (6.6, 0.25, 1.0), (0, 17.25, roof - 0.52), blk, bev=0.05, rot=(math.radians(-14), 0, 0)))
        G["Lights"].append(M.text("dest", "42  CRASH TEST DEPOT", 0.52, (0, 17.4, roof - 0.55), (math.pi / 2 + math.radians(14), 0, math.pi), led, extrude=0.01))
        for sx in (-1, 1):
            G["Lights"].append(P("headlamp", "F", (sx * 3.2 - 0.75, 1.95, sx * 3.2 + 0.75, 2.6), M.HEADLIGHT(), 0.03, res=0.06, thickness=0.03, round_r=0.2))
            G["Lights"].append(P("drl", "F", (sx * 3.2 - 0.75, 2.7, sx * 3.2 + 0.75, 2.82), mat("DRL", "#f4f8ff", rough=0.2, emit=1.5), 0.03, res=0.06))
            G["Lights"].append(P("indicator", "F", (sx * 3.2 - 0.75, 1.68, sx * 3.2 + 0.75, 1.85), M.AMBER(), 0.03, res=0.06))
            a, _ = surf.point("F", sx * 1.0, 3.5)
            if a is not None:
                G["Trim"].append(tube("wiper", [(sx * 1.0, 18.1, 3.25), (sx * 1.6, 17.75, 5.0), (sx * 2.2, 17.35, 6.6)], 0.045, blk, segs=6))
        G["Trim"].append(P("frontmask", "F", (-4.1, 1.5, 4.1, 3.05), blk, 0.012, res=0.1, round_r=0.3))
        G["Trim"].append(box("bumperF", (8.9, 0.5, 0.75), (0, 18.2, 1.25), blk, bev=0.18, segs=3))
        G["Trim"].append(box("bumperR", (8.9, 0.45, 0.8), (0, -18.2, 1.3), blk, bev=0.18, segs=3))
        G["Trim"].append(box("plate", (1.5, 0.05, 0.42), (0, 18.47, 1.3), M.PLATE(), bev=0.02))
        # rear: engine louvres, light clusters, high brake light, route number
        G["Trim"].append(P("enginedoor", "B", (-3.4, 1.9, 3.4, 4.9), blk, 0.012, res=0.12, round_r=0.15))
        for k in range(9):
            G["Trim"].append(P("louvre", "B", (-3.1, 2.15 + k * 0.3, 3.1, 2.26 + k * 0.3), M.STEEL(), 0.04, thickness=0.03))
        G["Glass"].append(P("rearglass", "B", (-3.3, 5.4, 3.3, 7.1), M.mat("TintGlass", "#101418", rough=0.05, alpha=0.75), 0.03, res=0.15, round_r=0.2))
        for sx in (-1, 1):
            G["Lights"].append(P("tail", "B", (sx * 3.9 - 0.3, 2.2, sx * 3.9 + 0.3, 4.6), M.TAILLIGHT(), 0.03, res=0.08, thickness=0.03, round_r=0.15))
            G["Lights"].append(P("tailamber", "B", (sx * 3.9 - 0.3, 4.75, sx * 3.9 + 0.3, 5.2), M.AMBER(), 0.03, res=0.08, round_r=0.12))
        G["Lights"].append(P("highbrake", "B", (-1.2, 7.45, 1.2, 7.6), M.TAILLIGHT(), 0.03, res=0.08))
        G["Lights"].append(M.text("rearnum", "42", 0.6, (2.6, -18.02, 7.5), (math.pi / 2, 0, 0), led, extrude=0.01))
        G["Trim"].append(cyl("exhaust", 0.18, 0.8, (-3.6, -18.1, 1.0), M.STEEL(), "Y", segs=12))
        # roof: air-con pod, battery pod, hatches, antenna
        pod = loft("aircon", [oval(11.0, 2.3, 0.25, roof + 0.25, 12, 3), oval(10.2, 2.6, 0.5, roof + 0.42, 12, 3), oval(3.0, 2.6, 0.5, roof + 0.42, 12, 3), oval(2.2, 2.3, 0.25, roof + 0.25, 12, 3)], white)
        M.subsurf(pod, 1)
        G["Body"].append(pod)
        for k in range(5):
            G["Trim"].append(box("acgrille", (3.6, 0.9, 0.06), (0, 4.0 + k * 1.4, roof + 0.93), blk, bev=0.02))
        G["Body"].append(box("roofpod", (4.6, 5.0, 0.6), (0, -11.5, roof + 0.3), white, bev=0.2, segs=3))
        for yy in (-4.0, -7.2):
            G["Trim"].append(box("hatch", (2.2, 2.0, 0.14), (0, yy, roof + 0.12), M.matte("#d8dbe0", 0.6), bev=0.05))
        G["Trim"].append(tube("antenna", [(1.5, 14.5, roof + 0.05), (1.5, 14.2, roof + 1.6)], 0.03, blk, segs=6))
        # saloon: floor, seat pairs, yellow grab rails and stanchions, driver's cab
        seat = M.mat("BusSeat", "#1f4f8f", rough=0.85)
        yellow = M.mat("GrabRail", "#f2c21a", rough=0.35, metal=0.3)
        fz = c + 0.35
        G["Trim"].append(box("floor", (8.3, 34.5, 0.15), (0, -0.3, fz), M.mat("BusFloor", "#3c3f45", rough=0.8), bev=0.02))
        for k in range(9):
            yy = -13.2 + k * 2.9
            for sx in (-1, 1):
                if sx > 0 and (-2.2 < yy < 2.4 or yy > 12.2):
                    continue        # door wells
                G["Trim"].append(box("seat", (2.6, 1.2, 0.3), (sx * 2.7, yy, fz + 1.15), seat, bev=0.1))
                G["Trim"].append(box("seatback", (2.6, 0.25, 1.7), (sx * 2.7, yy - 0.6, fz + 1.95), seat, bev=0.12))
                G["Trim"].append(tube("seatgrab", [(sx * 1.5, yy - 0.6, fz + 2.8), (sx * 1.4, yy - 0.6, fz + 3.1), (sx * 3.6, yy - 0.6, fz + 3.1)], 0.04, yellow, segs=6))
        for sx in (-1.35, 1.35):
            G["Trim"].append(tube("handrail", [(sx, -15.5, roof - 0.9), (sx, 14.5, roof - 0.9)], 0.05, yellow, segs=8))
            for yy in (-12, -6, 0.2, 6, 12):
                G["Trim"].append(tube("stanchion", [(sx, yy, fz + 0.1), (sx, yy, roof - 0.9)], 0.05, yellow, segs=8))
        G["Trim"] += [box("drvseat", (1.6, 1.4, 0.3), (-2.4, 15.4, fz + 1.3), M.SEAT(), bev=0.1), box("drvback", (1.6, 0.3, 2.0), (-2.4, 14.7, fz + 2.2), M.SEAT(), bev=0.1),
                      box("dash", (8.0, 1.0, 1.3), (0, 17.0, fz + 1.5), M.INTERIOR(), bev=0.25), box("farebox", (0.6, 0.6, 2.2), (0.9, 16.0, fz + 1.2), M.STEEL(), bev=0.06),
                      box("cabscreen", (0.08, 2.2, 3.4), (-0.9, 15.0, fz + 2.4), M.GLASS(), bev=0.01)]
        ring = [(-2.4 + 0.8 * math.cos(a), 16.3 - 0.25 * math.sin(a), fz + 2.5 + 0.75 * math.sin(a)) for a in [M.TAU * k / 20 for k in range(20)]]
        G["Trim"].append(tube("swheel", ring, 0.06, M.PLASTIC(), segs=8, closed=True))
        for w in ws[::2]:
            for sx in (-1, 1):
                cup = lathe("liner", [(0, 0), (w["radius"] * 1.13, 0), (w["radius"] * 1.13, 2.4)], M.matte("#0c0c0d", 0.95), segs=28, axis="X", cap=False)
                cup.scale.x = sx
                M.place(cup, (sx * 2.0, -w["pos"][2], w["radius"] * 0.98))
                G["Trim"].append(cup)
        place_wheels(G, ws, "steel", "#c9ccd1")
        return G

    @builder("DumpTruck")
    def dump():
        s = spec("DumpTruck")
        G = C.new_groups()
        orange = M.paint("#f07d12")
        steel = M.mat("Chassis", "#25272b", rough=0.5, metal=0.7)
        # ---- cab (conventional, short bonnet)
        hw, c, belt, roof, hood = 4.4, 3.2, 6.6, 9.0, 6.5
        S = []
        add = lambda y, w, zf, zb, zd, wd, flag="", cr=0.1: S.append((section(y, hw * w, zf, zb, zd, hw * wd, cr, 0, 0.92), flag))
        add(6.4, 0.9, c + 0.3, belt, roof - 0.7, 0.72, cr=0.05)
        add(6.6, 1.0, c, belt, roof - 0.15, 0.86)
        add(7.0, 1.0, c, belt, roof, 0.88, "glass")
        add(9.3, 1.0, c, belt, roof, 0.88, "ws")
        add(9.95, 0.98, c, hood - 0.05, hood + 0.1, 0.84)
        add(10.4, 0.92, c, hood - 0.15, hood - 0.02, 0.76)
        add(12.5, 0.84, c, hood - 0.5, hood - 0.38, 0.68)
        add(13.0, 0.8, c + 0.15, hood - 0.8, hood - 0.7, 0.62, cr=0.05)
        add(13.15, 0.7, c + 0.6, hood - 1.6, hood - 1.5, 0.5, cr=0.03)
        shell = shell_from(S, [orange, M.GLASS()])
        surf = M.Surface(shell)
        body, glass = C.split_glass(shell)
        G["Body"].append(body)
        G["Glass"].append(glass)
        P = surf.project
        G["Trim"].append(P("grille", "F", (-2.5, 3.6, 2.5, 5.9), M.DARK(), 0.02, res=0.1, round_r=0.2))
        for k in range(8):
            G["Trim"].append(P("slat", "F", (-2.35, 3.78 + k * 0.27, 2.35, 3.88 + k * 0.27), M.CHROME(), 0.045, thickness=0.03))
        G["Trim"].append(M.text("badge", "RCP", 0.55, (0, 13.22, 6.05), (math.pi / 2, 0, math.pi), M.CHROME(), extrude=0.03))
        for side in ("L", "R"):
            sgn = 1 if side == "R" else -1
            # cab door: the cut runs round the whole door including its window; hinged at the front,
            # pull handle under the window near the rear edge, grab handle on the A-pillar for climbing in
            G["Trim"].append(C.groove_path(surf, side, C.rounded_rect(6.8, 3.45, 9.6, 8.85, 0.35), M.DARK()))
            G["Trim"].append(P("pocket", side, (7.0, 6.05, 7.95, 6.42), M.mat("Pocket", "#121315", rough=0.35), 0.01, res=0.04, round_r=0.1))
            G["Trim"].append(C.pull_handle(surf, side, 7.48, 6.22, 0.8, M.CHROME()))
            G["Trim"] += C.hinges(surf, side, 9.5, (4.4, 7.6), M.CHROME())
            G["Trim"].append(C.grab_handle(surf, side, 9.85, 4.2, 7.4, M.CHROME()))
            # wide front wings over the steer tyres
            wing = loft("wing", [[(sgn * 3.4, 12.6, 3.4), (sgn * 5.1, 12.6, 3.4), (sgn * 5.1, 12.6, 3.55), (sgn * 3.4, 12.6, 3.55)],
                                 [(sgn * 3.4, 11.6, 5.3), (sgn * 5.1, 11.6, 5.3), (sgn * 5.1, 11.6, 5.45), (sgn * 3.4, 11.6, 5.45)],
                                 [(sgn * 3.4, 9.5, 5.75), (sgn * 5.1, 9.5, 5.75), (sgn * 5.1, 9.5, 5.9), (sgn * 3.4, 9.5, 5.9)],
                                 [(sgn * 3.4, 7.6, 5.3), (sgn * 5.1, 7.6, 5.3), (sgn * 5.1, 7.6, 5.45), (sgn * 3.4, 7.6, 5.45)],
                                 [(sgn * 3.4, 6.9, 4.0), (sgn * 5.1, 6.9, 4.0), (sgn * 5.1, 6.9, 4.15), (sgn * 3.4, 6.9, 4.15)]], orange)
            M.subsurf(wing, 1)
            G["Body"].append(wing)
            G["Lights"].append(cyl("headlamp", 0.5, 0.25, (sgn * 3.55, 13.0, 4.6), M.HEADLIGHT(), "Y", segs=24))
            G["Trim"].append(cyl("lampring", 0.6, 0.2, (sgn * 3.55, 12.95, 4.6), M.CHROME(), "Y", segs=24))
            G["Lights"].append(box("turn", (0.5, 0.2, 0.3), (sgn * 4.55, 12.75, 4.6), M.AMBER(), bev=0.06))
            # mirrors, steps, tanks, stacks
            G["Trim"].append(tube("mirrorframe", [(sgn * 4.3, 9.6, 6.7), (sgn * 5.5, 9.9, 6.8), (sgn * 5.5, 9.9, 8.6), (sgn * 4.3, 9.6, 8.7)], 0.06, M.CHROME(), segs=8))
            G["Trim"].append(box("mirror", (0.14, 0.7, 1.5), (sgn * 5.5, 9.85, 7.7), M.DARK(), bev=0.06))
            G["Trim"].append(cyl("tank", 1.0, 3.2, (sgn * 3.7, 5.0, 2.9), M.ALLOY(), "Y", segs=28, bev=0.12))
            for yy in (4.0, 6.0):
                G["Trim"].append(lathe("strap", [(1.03, -0.08), (1.03, 0.08)], M.DARK(), segs=28, axis="Y", loc=(sgn * 3.7, yy, 2.9), cap=False))
            for zz in (2.3, 3.2):
                G["Trim"].append(box("step", (1.1, 1.6, 0.1), (sgn * 4.3, 8.2, zz), M.ALLOY(), bev=0.02))
            G["Trim"].append(cyl("stack", 0.28, 6.4, (sgn * 3.95, 6.0, 8.2), M.CHROME(), "Z", segs=20))
            G["Trim"].append(cyl("heatshield", 0.4, 2.6, (sgn * 3.95, 6.0, 6.6), M.matte("#3a3c40", 0.6), "Z", segs=20))
            G["Trim"].append(tube("stacktip", [(sgn * 3.95, 6.0, 11.3), (sgn * 3.95, 5.9, 11.7), (sgn * 3.95, 5.5, 11.95)], 0.26, M.CHROME(), segs=14, smooth=4))
            G["Trim"].append(box("rail", (0.5, 26.0, 1.1), (sgn * 2.0, -0.2, 3.3), steel, bev=0.05))
            for yy in (-7.5, -3.0):
                G["Trim"].append(box("mudflap", (2.4, 0.08, 2.2), (sgn * 4.6, yy - 2.95 if yy < -5 else yy + 2.9, 2.0), M.RUBBER(), bev=0.02)) if yy < -5 else None
            G["Lights"].append(box("tail", (0.9, 0.2, 0.5), (sgn * 2.6, -13.15, 3.4), M.TAILLIGHT(), bev=0.08))
        for k in range(5):
            G["Lights"].append(box("marker", (0.3, 0.2, 0.14), ((k - 2) * 1.3, 9.5, roof + 0.12), M.AMBER(), bev=0.04))
        for sx in (-1, 1):
            G["Trim"].append(lathe("horn", [(0.05, 0), (0.07, 0.9), (0.2, 1.4)], M.CHROME(), segs=14, axis="Y", loc=(sx * 1.0, 8.2, roof + 0.3), cap=False))
        G["Trim"].append(box("bumper", (9.6, 0.8, 1.3), (0, 13.45, 3.0), M.CHROME(), bev=0.2, segs=3))
        for sx in (-1, 1):
            G["Trim"].append(tube("towhook", [(sx * 2.4, 13.8, 2.9), (sx * 2.4, 14.25, 2.9), (sx * 2.9, 14.25, 2.9), (sx * 2.9, 13.8, 2.9)], 0.09, M.STEEL(), segs=8, smooth=4))
        for yy in (-10.0, -5.3, 0.5, 6.0, 11.0):
            G["Trim"].append(box("xmember", (4.0, 0.5, 0.7), (0, yy, 3.3), steel, bev=0.05))
        # ---- dump body: plate + ribs (as real ones are fabricated)
        y0, y1, bw = -12.3, 4.7, 4.8          # rear, front, half width
        fz, tz = 4.4, 9.1
        plate = orange
        G["Body"].append(box("bedfloor", (bw * 2, y1 - y0, 0.3), (0, (y0 + y1) / 2, fz), plate, bev=0.04))
        for sx in (-1, 1):
            G["Body"].append(box("bedside", (0.25, y1 - y0, tz - fz), (sx * bw, (y0 + y1) / 2, (fz + tz) / 2), plate, bev=0.04))
            G["Body"].append(box("toprail", (0.6, y1 - y0 + 0.2, 0.5), (sx * (bw + 0.05), (y0 + y1) / 2, tz + 0.1), plate, bev=0.1))
            for k in range(7):
                yy = y0 + 0.9 + k * (y1 - y0 - 1.8) / 6
                G["Body"].append(loft("rib", [[(sx * bw, yy - 0.25, fz - 0.1), (sx * bw, yy + 0.25, fz - 0.1), (sx * (bw + 0.5), yy + 0.18, fz + 0.3), (sx * (bw + 0.5), yy - 0.18, fz + 0.3)],
                                               [(sx * bw, yy - 0.25, tz), (sx * bw, yy + 0.25, tz), (sx * (bw + 0.3), yy + 0.18, tz), (sx * (bw + 0.3), yy - 0.18, tz)]], plate, smooth=False))
            G["Trim"].append(tube("gatechain", [(sx * (bw - 0.2), y0 - 0.05, tz - 0.2), (sx * (bw - 0.3), y0 - 0.5, 6.5), (sx * (bw - 0.2), y0 - 0.1, 5.0)], 0.05, M.STEEL(), segs=6, smooth=5))
        G["Body"].append(box("bulkhead", (bw * 2, 0.3, tz - fz + 0.9), (0, y1, (fz + tz) / 2 + 0.45), plate, bev=0.04))
        visor = box("visor", (bw * 2 + 0.3, 4.8, 0.3), (0, y1 + 2.3, tz + 1.05), plate, bev=0.06, rot=(math.radians(4), 0, 0))
        G["Body"].append(visor)
        for sx in (-0.66, 0, 0.66):
            G["Body"].append(box("visorrib", (0.3, 4.6, 0.35), (sx * bw, y1 + 2.3, tz + 0.8), plate, bev=0.05, rot=(math.radians(4), 0, 0)))
        G["Body"].append(box("tailgate", (bw * 2 - 0.1, 0.25, tz - fz - 0.1), (0, y0 - 0.1, (fz + tz) / 2 + 0.05), M.paint("#d96c0c"), bev=0.04, rot=(math.radians(-3), 0, 0)))
        for zz in (5.4, 6.8, 8.2):
            G["Body"].append(box("gaterib", (bw * 2 - 0.3, 0.25, 0.4), (0, y0 - 0.33, zz), M.paint("#d96c0c"), bev=0.06))
        G["Trim"].append(cyl("hinge", 0.22, bw * 2 + 0.6, (0, y0 - 0.05, tz + 0.05), M.STEEL(), "X", segs=12))
        for sx in (-1, 1):   # sub-frame + tipping ram
            G["Trim"].append(box("subframe", (0.6, y1 - y0 - 1, 0.5), (sx * 2.0, (y0 + y1) / 2, 4.05), steel, bev=0.05))
        G["Trim"].append(tube("rambarrel", [(0, 5.4, 3.9), (0, 5.05, 6.4)], 0.42, M.matte("#2a2c30", 0.5), segs=18))
        G["Trim"].append(tube("ramrod", [(0, 5.05, 6.4), (0, 4.85, 8.0)], 0.26, M.CHROME(), segs=16))
        G["Trim"].append(cyl("pivot", 0.35, 5.0, (0, y0 + 1.0, 3.95), M.STEEL(), "X", segs=14))
        # dirt load
        load = loft("load", [M.oval(y0 + 1.2, bw - 0.5, 0.5, tz - 0.9, 12), M.oval(-6, bw - 0.4, 1.5, tz - 0.6, 12), M.oval(-1, bw - 0.4, 1.9, tz - 0.5, 12), M.oval(y1 - 1.0, bw - 0.5, 0.7, tz - 0.9, 12)],
                    M.matte("#5b4630", 0.95))
        M.subsurf(load, 1)
        G["Trim"].append(load)
        for y in sorted({-w["pos"][2] for w in s["wheels"]}):
            G["Trim"].append(cyl("axle", 0.5, 8.6, (0, y, 2.5), steel, "X", segs=16))
            G["Trim"].append(lathe("diff", [(0, -0.8), (0.6, -0.8), (1.1, -0.3), (1.1, 0.3), (0.6, 0.8), (0, 0.8)], steel, segs=20, axis="X", loc=(0, y, 2.5))) if y < 0 else None
        G["Trim"].append(box("driveshaft", (0.3, 12.0, 0.3), (0, 1.5, 2.7), M.STEEL(), bev=0.1))
        place_wheels(G, s["wheels"], "steel", "#e9e9e6", rim_frac=0.56)
        return G

    @builder("ArmoredTruck")
    def armored():
        s = spec("ArmoredTruck")
        G = C.new_groups()
        tan = M.mat("Armour", "#6f7a63", rough=0.7, metal=0.1)
        dark = M.mat("ArmourDark", "#30352c", rough=0.75)

        def hull(y, wb, wt, zb, zm, zt, wr):
            # faceted armour section: V-belly, vertical lower plate, inward-sloped upper plate
            half = [(0, zb - 0.55), (wb * 0.55, zb), (wb, zb + 0.5), (wb, zm), (wt, zt - 0.25), (wr, zt), (0, zt)]
            return [(x, y, z) for x, z in half] + [(-x, y, z) for x, z in reversed(half[1:-1])]
        rings = [hull(-10.2, 3.0, 2.8, 2.6, 4.6, 6.6, 2.2), hull(-9.6, 3.6, 3.35, 2.3, 4.8, 7.55, 2.9), hull(-2.0, 3.6, 3.35, 2.3, 4.8, 7.6, 2.9),
                 hull(1.6, 3.6, 3.3, 2.3, 4.8, 7.55, 2.85), hull(3.4, 3.5, 3.1, 2.3, 4.7, 5.35, 2.7), hull(8.6, 3.2, 2.8, 2.4, 4.3, 4.9, 2.4),
                 hull(10.1, 2.8, 2.3, 2.9, 4.0, 4.3, 1.9)]
        shell = loft("hull", rings, tan, smooth=False)
        M.bevel(shell, 0.07, 2, angle=20)
        G["Body"].append(shell)
        surf = M.Surface(shell)
        P = surf.project
        glassm = M.mat("ArmourGlass", "#263a33", rough=0.05, alpha=0.6)
        # windscreen (two panes) + side / rear vision blocks, each in a bolted frame
        def pane(side, o, name="pane"):
            fr = P(name + "frame", side, (o[0] - 0.14, o[1] - 0.14, o[2] + 0.14, o[3] + 0.14), dark, 0.03, res=0.1, thickness=0.09)
            gl = P(name, side, o, glassm, 0.13, res=0.1)
            G["Trim"].append(fr)
            G["Glass"].append(gl)
            pts = []
            for u in (o[0] - 0.07, o[2] + 0.07):
                for v in (o[1] - 0.07, o[3] + 0.07):
                    loc, nrm = surf.point(side, u, v)
                    if loc is not None:
                        pts.append(loc + nrm * 0.13)
            G["Trim"] += M.bolts(pts, 0.045, M.STEEL(), "X" if side in "LR" else "Y", 0.06)
        for x0 in (-2.55, 0.25):
            fr = P("wsframe", "T", (x0 - 0.12, 1.75, x0 + 2.42, 3.3), dark, 0.03, res=0.1, thickness=0.09)
            gl = P("ws", "T", (x0, 1.87, x0 + 2.3, 3.18), glassm, 0.13, res=0.1)
            G["Trim"].append(fr)
            G["Glass"].append(gl)
        for side in ("L", "R"):
            sgn = 1 if side == "R" else -1
            pane(side, (-0.2, 5.75, 1.3, 6.75))
            pane(side, (-4.6, 5.9, -3.0, 6.7))
            pane(side, (-7.9, 5.9, -6.3, 6.7))
            # two heavy armoured doors per side (crew + troop), each hinged on its FRONT edge with big
            # external hinges, a recessed pull handle near the rear edge and a step underneath
            for y0, y1 in ((-2.3, 1.75), (-6.6, -2.65)):
                G["Trim"].append(C.groove_path(surf, side, C.rounded_rect(y0, 2.9, y1, 7.2, 0.2), dark, radius=0.03))
                G["Trim"] += C.hinges(surf, side, y1 - 0.15, (3.4, 6.7), dark, length=0.6, radius=0.1)
                G["Trim"].append(P("pocket", side, (y0 + 0.2, 4.7, y0 + 1.1, 5.1), M.mat("Pocket", "#121315", rough=0.35), 0.01, res=0.04, round_r=0.1))
                G["Trim"].append(C.pull_handle(surf, side, y0 + 0.65, 4.9, 0.7, M.STEEL()))
                G["Trim"].append(box("step", (0.9, 2.6, 0.12), (sgn * 4.2, (y0 + y1) / 2, 2.2), M.STEEL(), bev=0.02))
            # stowage bins behind the doors + angular wings over the wheels
            G["Body"].append(box("bin", (0.9, 2.2, 1.5), (sgn * 4.1, -8.4, 3.3), tan, bev=0.06))
            G["Trim"].append(box("binlid", (0.95, 2.1, 0.06), (sgn * 4.1, -8.4, 4.08), dark, bev=0.02))
            for yc in (6.5, -6.5):
                G["Body"].append(loft("wing", [[(sgn * 3.3, yc + 2.9, 3.6), (sgn * 5.5, yc + 2.9, 3.6), (sgn * 5.5, yc + 2.9, 3.75), (sgn * 3.3, yc + 2.9, 3.75)],
                                                [(sgn * 3.3, yc + 1.7, 4.75), (sgn * 5.5, yc + 1.7, 4.75), (sgn * 5.5, yc + 1.7, 4.9), (sgn * 3.3, yc + 1.7, 4.9)],
                                                [(sgn * 3.3, yc - 1.7, 4.75), (sgn * 5.5, yc - 1.7, 4.75), (sgn * 5.5, yc - 1.7, 4.9), (sgn * 3.3, yc - 1.7, 4.9)],
                                                [(sgn * 3.3, yc - 2.9, 3.6), (sgn * 5.5, yc - 2.9, 3.6), (sgn * 5.5, yc - 2.9, 3.75), (sgn * 3.3, yc - 2.9, 3.75)]], tan, smooth=False))
            G["Lights"].append(box("headlamp", (0.8, 0.2, 0.55), (sgn * 2.2, 10.2, 3.75), M.HEADLIGHT(), bev=0.08))
            G["Trim"].append(tube("lampguard", [(sgn * 1.7, 10.2, 3.4), (sgn * 1.7, 10.5, 3.4), (sgn * 1.7, 10.5, 4.1), (sgn * 1.7, 10.2, 4.1)], 0.04, dark, segs=6))
            G["Trim"].append(tube("lampguard2", [(sgn * 2.7, 10.2, 3.4), (sgn * 2.7, 10.5, 3.4), (sgn * 2.7, 10.5, 4.1), (sgn * 2.7, 10.2, 4.1)], 0.04, dark, segs=6))
            G["Lights"].append(box("tail", (0.5, 0.15, 0.7), (sgn * 2.9, -10.3, 4.2), M.TAILLIGHT(), bev=0.06))
            G["Trim"].append(tube("shackle", [(sgn * 2.3, 10.5, 2.9), (sgn * 2.3, 10.95, 2.9), (sgn * 2.7, 10.95, 2.9), (sgn * 2.7, 10.5, 2.9)], 0.08, M.STEEL(), segs=8, smooth=4))
            G["Trim"].append(tube("antenna", [(sgn * 2.6, -9.2, 7.6), (sgn * 2.6, -9.3, 12.5)], 0.035, dark, segs=6))
            G["Trim"].append(cyl("antbase", 0.14, 0.5, (sgn * 2.6, -9.2, 7.75), dark, "Z", segs=10))
            G["Trim"].append(box("mirror", (0.12, 0.5, 0.9), (sgn * 4.2, 2.7, 6.4), dark, bev=0.05))
            G["Trim"].append(tube("mirrorarm", [(sgn * 3.3, 2.5, 6.0), (sgn * 4.2, 2.7, 6.0), (sgn * 4.2, 2.7, 6.9), (sgn * 3.25, 2.5, 6.9)], 0.04, dark, segs=6))
        # bull bar
        bar = dark
        for sx in (-1.5, 1.5):
            G["Trim"].append(box("ramupright", (0.35, 0.5, 2.6), (sx, 10.75, 3.6), bar, bev=0.05))
        for zz in (2.6, 3.5, 4.5):
            G["Trim"].append(box("rambar", (8.6, 0.4, 0.4), (0, 10.95, zz), bar, bev=0.08))
        G["Trim"].append(box("winch", (1.6, 0.7, 0.7), (0, 10.6, 3.0), M.STEEL(), bev=0.1))
        for k in range(7):   # bonnet louvres
            G["Trim"].append(P("louvre", "T", (-1.5, 4.6 + k * 0.42, 1.5, 4.72 + k * 0.42), dark, 0.02, thickness=0.04))
        # roof: hatch ring, gunner shield plates, hatch lid, light bar, snorkel
        G["Trim"].append(lathe("ring", [(1.25, 0), (1.5, 0), (1.5, 0.3), (1.25, 0.3)], dark, segs=28, axis="Z", loc=(0, -4.0, 7.6), close=True))
        G["Trim"].append(cyl("hatchlid", 1.2, 0.12, (0, -5.1, 8.5), tan, "Y", segs=24))
        for a in (-50, 0, 50):
            ra = math.radians(a)
            G["Body"].append(box("shield", (1.5, 0.1, 1.1), (1.55 * math.sin(ra), -4.0 + 1.55 * math.cos(ra), 8.45), tan, bev=0.02, rot=(0, 0, -ra)))
        G["Lights"].append(box("lightbar", (4.2, 0.3, 0.3), (0, 1.5, 7.85), M.HEADLIGHT(), bev=0.06))
        G["Trim"].append(tube("snorkel", [(3.3, 3.0, 5.0), (3.7, 3.0, 5.6), (3.7, 3.0, 8.3)], 0.22, dark, segs=12, smooth=3))
        G["Trim"].append(cyl("snorkelcap", 0.32, 0.4, (3.7, 3.0, 8.5), dark, "Z", segs=14))
        # rear: door, ladder, spare wheel, jerry cans
        G["Trim"].append(P("reardoor", "B", (-1.6, 3.0, 1.6, 7.0), dark, 0.012, res=0.1))
        G["Trim"] += C.hinges(surf, "B", -1.45, (3.6, 6.4), dark, length=0.6, radius=0.1)
        G["Trim"] += C.latch(surf, "B", 1.1, 4.9, M.STEEL(), w=0.5, h=0.16)
        G["Trim"].append(C.grab_handle(surf, "B", 1.9, 3.4, 6.2, M.STEEL()))
        G["Body"].append(P("reardoorpanel", "B", (-1.52, 3.08, 1.52, 6.92), tan, 0.03, res=0.2))
        fr = P("rearframe", "B", (-0.8, 5.7, 0.8, 6.6), dark, 0.05, res=0.1, thickness=0.08)
        G["Trim"].append(fr)
        G["Glass"].append(P("rearpane", "B", (-0.66, 5.84, 0.66, 6.46), glassm, 0.14, res=0.1))
        for zz in (2.4, 3.0):
            G["Trim"].append(box("rearstep", (3.0, 0.7, 0.1), (0, -10.5, zz), M.STEEL(), bev=0.02))
        spare = M.wheel("spare", 2.1, 1.7, "offroad", 1, "#30352c", rim_frac=0.58)
        M.place(spare, (-2.6, -10.75, 5.0), rot=(0, 0, math.radians(-90)))
        G["Trim"].append(spare)
        for k in range(2):
            G["Trim"].append(box("jerry", (0.5, 1.1, 1.5), (2.3 + k * 0.6, -10.35, 4.6), M.mat("Jerry", "#3b4a2d", rough=0.6), bev=0.1))
        loc, _ = surf.point("R", -5.0, 4.0)
        G["Trim"].append(M.text("id", "RCP-07", 0.6, (loc.x + 0.04, -5.2, 4.0), (math.pi / 2, 0, math.pi / 2), M.matte("#d9d9d0", 0.6)))
        loc, _ = surf.point("L", -5.0, 4.0)
        G["Trim"].append(M.text("id", "RCP-07", 0.6, (loc.x - 0.04, -5.2, 4.0), (math.pi / 2, 0, -math.pi / 2), M.matte("#d9d9d0", 0.6)))
        for y in (6.5, -6.5):
            G["Trim"].append(cyl("axle", 0.4, 8.2, (0, y, 2.1), dark, "X", segs=14))
            G["Trim"].append(lathe("diff", [(0, -0.7), (0.5, -0.7), (0.9, -0.3), (0.9, 0.3), (0.5, 0.7), (0, 0.7)], dark, segs=18, axis="X", loc=(0, y, 2.1)))
        place_wheels(G, s["wheels"], "offroad", "#30352c", rim_frac=0.58)
        return G
