"""Main battle tank: welded hull, torsion-bar running gear with individual track links, cast turret."""
import math

from mathutils import Vector

import rcp_model as M
import rcp_cars as C
from rcp_model import box, cyl, lathe, loft, tube, mat


def road_wheel(x, y, z, r, side, green, w=1.1):
    parts = [lathe("rw_tyre", [(r * 0.86, -w / 2), (r, -w / 2 + 0.06), (r, w / 2 - 0.06), (r * 0.86, w / 2)], M.RUBBER(), segs=28, axis="X", cap=False),
             lathe("rw_disc", [(0, w * 0.34), (r * 0.28, w * 0.34), (r * 0.4, w * 0.18), (r * 0.78, w * 0.3), (r * 0.87, w * 0.5), (r * 0.87, -w * 0.5), (0, -w * 0.5)], green, segs=28, axis="X"),
             cyl("rw_cap", r * 0.16, 0.12, (w * 0.4, 0, 0), M.STEEL(), "X", segs=12)]
    parts += M.bolts([(w * 0.36, r * 0.25 * math.cos(a), r * 0.25 * math.sin(a)) for a in [M.TAU * k / 8 for k in range(8)]], r * 0.035, M.STEEL(), "X", 0.06)
    ob = M.join(parts, "roadwheel")
    ob.scale.x = side
    return M.place(ob, (x, y, z))


def sprocket(x, y, z, r, side, green, teeth=13, w=1.2):
    parts = [lathe("sp_hub", [(0, w * 0.5), (r * 0.35, w * 0.5), (r * 0.5, w * 0.3), (r * 0.5, -w * 0.3), (0, -w * 0.3)], green, segs=20, axis="X")]
    for off in (-w * 0.32, w * 0.32):
        parts.append(lathe("sp_ring", [(r * 0.45, off - 0.06), (r * 0.9, off - 0.06), (r * 0.9, off + 0.06), (r * 0.45, off + 0.06)], M.STEEL(), segs=26, axis="X", close=True))
        for k in range(teeth):
            a = M.TAU * k / teeth
            t = box("tooth", (0.12, r * 0.2, r * 0.2), (off, r * 0.95 * math.cos(a), r * 0.95 * math.sin(a)), M.STEEL(), bev=0.03, rot=(a, 0, 0), segs=1)
            parts.append(t)
    ob = M.join(parts, "sprocket")
    ob.scale.x = side
    return M.place(ob, (x, y, z))


def running_gear(G, x, width, green, wheels_y, rw_z, rw_r, spr, idl, rollers, pitch=0.62):
    """Both sides: road wheels, sprocket, idler, return rollers and the track itself."""
    loop = [spr] + rollers + [idl] + [(y, rw_z, rw_r) for y in sorted(wheels_y, reverse=True)]
    for side in (-1, 1):
        sx = side * x
        for y in wheels_y:
            G["Trim"].append(road_wheel(sx, y, rw_z, rw_r, side, green, width * 0.42))
            G["Trim"].append(tube("arm", [(sx - side * width * 0.35, y, rw_z), (sx - side * width * 0.45, y + rw_r * 1.1, rw_z + rw_r * 0.55)], 0.16, M.STEEL(), segs=8))
        G["Trim"].append(sprocket(sx, spr[0], spr[1], spr[2], side, green, w=width * 0.5))
        G["Trim"].append(road_wheel(sx, idl[0], idl[1], idl[2], side, green, width * 0.42))
        for ry, rz, rr in rollers:
            G["Trim"].append(cyl("roller", rr, width * 0.5, (sx, ry, rz), M.STEEL(), "X", segs=14))
        G["Trim"].append(M.track("track", sx, width, loop, pitch))


def register(builder, spec, car_dims):
    @builder("Tank")
    def tank():
        G = C.new_groups()
        green = M.mat("Olive", "#4a5a38", rough=0.72, metal=0.1)
        dark = M.mat("OliveDark", "#2f3a24", rough=0.75)
        blk = M.matte("#141414", 0.7)
        # ---- hull: side profile extruded between the tracks
        prof = [(-10.9, 1.45), (-11.5, 3.3), (-10.9, 3.95), (6.4, 3.95), (12.6, 2.7), (12.95, 2.05), (10.9, 1.0), (-10.2, 1.0)]
        hull = loft("hull", [[(x, y, z) for y, z in prof] for x in (-4.95, 4.95)], green, smooth=False)
        M.bevel(hull, 0.06, 2, angle=20)
        G["Body"].append(hull)
        for s in (-1, 1):
            # track guards with curved mud flaps front and rear
            guard = loft("guard", [[(s * 4.9, y, z), (s * 7.75, y, z), (s * 7.75, y, z + 0.1), (s * 4.9, y, z + 0.1)] for y, z in
                                   ((-12.1, 2.2), (-11.9, 2.85), (-11.3, 3.1), (11.2, 3.1), (12.2, 2.9), (12.9, 2.3), (13.15, 1.6))], green, smooth=False)
            G["Body"].append(guard)
            for k in range(6):   # side skirts, one plate per bay with a gap
                y0 = -10.6 + k * 3.55
                G["Body"].append(box("skirt", (0.12, 3.4, 1.35), (s * 7.72, y0 + 1.7, 2.42), green, bev=0.03))
                G["Trim"] += M.bolts([(s * 7.8, y0 + 0.3, 2.9), (s * 7.8, y0 + 3.1, 2.9)], 0.06, M.STEEL(), "X")
            # stowage boxes, tools, tow cable on the guards
            G["Body"].append(box("stowage", (2.0, 3.6, 0.8), (s * 6.3, -6.5, 3.6), green, bev=0.06))
            G["Trim"].append(box("stowlid", (2.05, 3.5, 0.05), (s * 6.3, -6.5, 4.02), dark, bev=0.02))
            G["Body"].append(box("stowage2", (2.0, 2.6, 0.7), (s * 6.3, 4.0, 3.55), green, bev=0.06))
            G["Trim"].append(tube("cable", [(s * 5.4, 10.6, 3.3), (s * 5.5, 6, 3.25), (s * 5.45, -2, 3.25), (s * 5.5, -3.6, 3.3), (s * 5.2, -4.0, 3.3)], 0.06, M.STEEL(), segs=6, smooth=4))
            G["Trim"].append(tube("towhook", [(s * 3.2, 12.75, 2.2), (s * 3.2, 13.3, 2.15), (s * 3.8, 13.3, 2.15), (s * 3.8, 12.75, 2.2)], 0.1, M.STEEL(), segs=8, smooth=4))
            G["Trim"].append(tube("towhookR", [(s * 3.2, -11.4, 2.4), (s * 3.2, -11.95, 2.4), (s * 3.8, -11.95, 2.4), (s * 3.8, -11.4, 2.4)], 0.1, M.STEEL(), segs=8, smooth=4))
            G["Lights"].append(cyl("headlamp", 0.3, 0.3, (s * 3.9, 10.9, 3.3), M.HEADLIGHT(), "Y", segs=16))
            G["Trim"].append(cyl("lampbody", 0.36, 0.5, (s * 3.9, 10.7, 3.3), dark, "Y", segs=16))
            for dx in (-0.45, 0.45):
                G["Trim"].append(tube("lampguard", [(s * 3.9 + dx, 10.3, 3.05), (s * 3.9 + dx, 11.25, 3.1), (s * 3.9 + dx, 11.2, 3.75), (s * 3.9 + dx, 10.4, 3.8)], 0.035, M.STEEL(), segs=6))
            G["Lights"].append(box("tail", (0.5, 0.12, 0.3), (s * 4.2, -11.5, 3.0), M.TAILLIGHT(), bev=0.05))
            G["Trim"].append(cyl("drum", 0.75, 2.2, (s * 2.2, -11.9, 3.2), green, "X", segs=24, bev=0.08))
            for dx in (-0.6, 0.6):
                G["Trim"].append(lathe("drumband", [(0.77, -0.06), (0.77, 0.06)], M.STEEL(), segs=24, axis="X", loc=(s * 2.2 + dx, -11.9, 3.2), cap=False))
            G["Trim"].append(tube("exhaust", [(s * 4.4, -9.0, 3.9), (s * 4.4, -9.6, 4.25), (s * 4.4, -10.6, 4.3)], 0.22, blk, segs=10, smooth=3))
        # engine deck grilles, driver's hatch, spare track links on the glacis
        for gx in (-2.4, 2.4):
            G["Trim"].append(box("grillbase", (3.6, 4.4, 0.08), (gx, -7.6, 3.98), blk, bev=0.02))
            for k in range(12):
                G["Trim"].append(box("slat", (3.5, 0.14, 0.12), (gx, -9.6 + k * 0.36, 4.05), dark, bev=0.02, rot=(math.radians(25), 0, 0), segs=1))
        # driver's hatch: open, the driver drives head-out (see rcp_interior.tank_driver)
        from rcp_trucks import cut_rect
        cut_rect(hull, "U", (-3.0, 4.2, -1.4, 5.8))
        import rcp_interior as I
        I.tank_driver(spec("Tank"), G, (-2.2, 5.0), 3.95)
        G["Trim"].append(box("periscope", (0.7, 0.3, 0.26), (-2.2, 6.2, 4.05), blk, bev=0.05))

        def u_handle(x, y, z, w=0.6, h=0.2, along="X"):
            if along == "X":
                pts = [(x - w / 2, y, z), (x - w / 2, y, z + h), (x + w / 2, y, z + h), (x + w / 2, y, z)]
            else:
                pts = [(x, y - w / 2, z), (x, y - w / 2, z + h), (x, y + w / 2, z + h), (x, y + w / 2, z)]
            return tube("uhandle", pts, 0.045, M.STEEL(), segs=6, smooth=3)
        # hatch hardware: hinge barrel on the rear edge, grab handle on the lid
        G["Trim"].append(tube("drvhinge", [(-2.9, 4.05, 4.12), (-1.5, 4.05, 4.12)], 0.11, dark, segs=10))
        G["Trim"].append(u_handle(-2.2, 5.5, 4.07))
        # engine deck access panels: a lifting handle at each end of every grille panel
        for gx in (-2.4, 2.4):
            for gy in (-9.95, -5.25):
                G["Trim"].append(u_handle(gx, gy, 4.02, 0.8, 0.18))
        glacis = math.atan2(3.95 - 2.7, 12.6 - 6.4)
        for k in range(5):
            G["Trim"].append(box("sparelink", (1.0, 0.5, 0.14), (1.2 + k * 1.05 - 2.6, 9.5, 3.42), M.STEEL(), bev=0.03, rot=(-glacis, 0, 0)))
        G["Trim"].append(M.text("num", "07", 1.1, (5.0, 0.5, 2.3), (math.pi / 2, 0, math.pi / 2), M.matte("#e6e6dc", 0.6)))
        # ---- running gear
        running_gear(G, 6.3, 2.6, green, [8.2, 5.0, 1.8, -1.4, -4.6, -7.8], 1.05, 0.93,
                     (-10.3, 1.8, 1.0), (10.6, 1.75, 0.9), [(-6.0, 2.42, 0.32), (0.0, 2.45, 0.32), (6.0, 2.42, 0.32)])
        # ---- turret (separate object; pivots on the ring)
        T = G["Turret"]
        def plan(z, rx, rf, rr, yc=-0.8, n=24):
            ring = []
            for k in range(n):
                a = M.TAU * k / n
                c, s_ = math.cos(a), math.sin(a)
                ry = rf if s_ > 0 else rr
                taper = 1 - 0.3 * max(0.0, s_) ** 2       # narrower towards the gun
                ring.append((rx * taper * math.copysign(abs(c) ** 0.75, c), yc + ry * math.copysign(abs(s_) ** 0.8, s_), z))
            return ring
        shell = loft("turret", [plan(4.3, 3.3, 4.0, 4.1), plan(4.6, 3.75, 4.6, 4.5), plan(5.5, 3.8, 4.7, 4.6), plan(6.25, 3.4, 4.0, 4.2), plan(6.55, 2.6, 2.8, 3.4)], green)
        M.subsurf(shell, 1)
        T.append(shell)
        T.append(lathe("ringbase", [(3.4, 3.95), (3.6, 3.95), (3.6, 4.35), (3.4, 4.35)], dark, segs=36, axis="Z", loc=(0, -0.5, 0), close=True))
        T.append(box("mantlet", (2.6, 1.3, 1.7), (0, 4.0, 5.55), green, bev=0.3, segs=3))
        gun = [(0, 0), (0.62, 0), (0.66, 0.5), (0.5, 0.9), (0.44, 1.2), (0.44, 4.6), (0.62, 4.75), (0.64, 6.4), (0.62, 6.55), (0.42, 6.75), (0.4, 10.2),
               (0.5, 10.3), (0.5, 10.9), (0.3, 10.9), (0.3, 9.5), (0, 9.5)]
        T.append(lathe("gun", gun, dark, segs=28, axis="Y", loc=(0, 4.2, 5.6)))
        T.append(cyl("bore", 0.3, 0.05, (0, 15.08, 5.6), blk, "Y", segs=20, bev=0))
        T.append(cyl("coax", 0.07, 1.6, (0.9, 4.9, 5.75), blk, "Y", segs=8))
        T.append(box("sight", (0.9, 1.0, 0.6), (1.6, 1.6, 6.75), green, bev=0.08))
        T.append(box("sightlens", (0.6, 0.05, 0.36), (1.6, 2.12, 6.75), M.mat("Lens", "#20405a", rough=0.05, metal=0.4), bev=0.02))
        # commander's cupola with vision blocks, hatch and machine gun
        cx, cy = -1.5, -1.6
        T.append(lathe("cupola", [(0.85, 0), (1.15, 0), (1.15, 0.5), (0.95, 0.62), (0.85, 0.62)], green, segs=28, axis="Z", loc=(cx, cy, 6.5), close=True))
        for k in range(8):
            a = M.TAU * k / 8
            T.append(box("vision", (0.42, 0.14, 0.2), (cx + 1.1 * math.cos(a), cy + 1.1 * math.sin(a), 6.85), blk, bev=0.03, rot=(0, 0, a + math.pi / 2)))
        T.append(cyl("cmdhatch", 0.9, 0.1, (cx, cy - 0.85, 7.6), dark, "Y", segs=24))
        T.append(cyl("ldrhatch", 0.85, 0.1, (1.6, -1.9, 6.65), dark, "Z", segs=24))
        T.append(tube("ldrhinge", [(1.0, -2.75, 6.75), (2.2, -2.75, 6.75)], 0.1, dark, segs=10))
        T.append(tube("ldrhandle", [(1.3, -1.5, 6.7), (1.3, -1.5, 6.88), (1.9, -1.5, 6.88), (1.9, -1.5, 6.7)], 0.045, M.STEEL(), segs=6, smooth=3))
        T.append(tube("cmdhinge", [(cx - 0.6, cy - 0.9, 7.12), (cx + 0.6, cy - 0.9, 7.12)], 0.1, dark, segs=10))
        # lifting eyes on the turret roof and grab rails along the turret sides
        for ex, ey in ((-2.6, 2.2), (2.6, 2.2), (-2.8, -3.6), (2.8, -3.6)):
            T.append(lathe("lifteye", [(0.12, -0.05), (0.22, -0.05), (0.22, 0.05), (0.12, 0.05)], M.STEEL(), segs=16, axis="X", loc=(ex, ey, 6.75), close=True))
        for s_ in (-1, 1):
            T.append(tube("turretrail", [(s_ * 3.55, 1.6, 5.2), (s_ * 3.85, 1.4, 5.6), (s_ * 3.85, -2.6, 5.6), (s_ * 3.55, -2.8, 5.2)], 0.05, M.STEEL(), segs=6, smooth=3))
        T.append(tube("mgmount", [(cx + 0.9, cy + 0.6, 7.1), (cx + 0.9, cy + 0.6, 7.75)], 0.08, M.STEEL(), segs=8))
        T.append(box("mgbody", (0.22, 1.4, 0.3), (cx + 0.9, cy + 0.9, 7.85), blk, bev=0.05))
        T.append(cyl("mgbarrel", 0.05, 1.8, (cx + 0.9, cy + 2.4, 7.9), blk, "Y", segs=8))
        T.append(box("ammobox", (0.4, 0.5, 0.4), (cx + 0.55, cy + 0.7, 7.75), green, bev=0.04))
        for s in (-1, 1):   # smoke dischargers and the stowage basket
            for k in range(4):
                p0 = Vector((s * 3.45, 1.2 + k * 0.5, 5.4 + (k % 2) * 0.42))
                T.append(tube("smoke", [p0, p0 + Vector((s * 0.35, 0.75, 0.35))], 0.17, dark, segs=10))
            T.append(tube("antenna", [(s * 2.2, -4.2, 6.5), (s * 2.25, -4.5, 12.0)], 0.035, blk, segs=6))
            T.append(cyl("antbase", 0.13, 0.5, (s * 2.2, -4.2, 6.7), blk, "Z", segs=10))
            for z in (4.9, 5.6, 6.2):
                T.append(tube("basket", [(s * 2.9, -4.6, z), (s * 3.0, -6.6, z), (0, -6.9, z)], 0.05, M.STEEL(), segs=6))
        for xk in (-2.4, -1.2, 0, 1.2, 2.4):
            T.append(tube("basketpost", [(xk, -6.85 + abs(xk) * 0.08, 4.9), (xk, -6.85 + abs(xk) * 0.08, 6.2)], 0.05, M.STEEL(), segs=6))
        T.append(box("pack", (3.6, 1.2, 0.8), (0, -6.0, 5.35), M.mat("Canvas", "#6b6648", rough=0.95), bev=0.25, segs=3))
        return G
