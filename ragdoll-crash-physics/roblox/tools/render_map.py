"""Top-down render of the procedurally built map (from tests/out/map.json, written by tests/map_spec.luau)."""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFont
here = os.path.dirname(os.path.abspath(__file__))
d = json.load(open(os.path.join(here, "..", "tests", "out", "map.json")))
S, R = 2, 380          # pixels per stud, half-extent shown
W = R * 2 * S
im = Image.new("RGB", (W, W), "#5faa4d")
dr = ImageDraw.Draw(im, "RGBA")
def px(x, z): return ((x + R) * S, (z + R) * S)
for p in sorted(d["parts"], key=lambda p: p["pos"][1] + p["size"][1] / 2):
    if p["transparency"] >= 1 or p["name"] in ("Baseplate", "Hill"): continue
    x, y, z = p["pos"]; sx, sy, sz = p["size"]
    c, s = math.cos(p["yaw"]), math.sin(p["yaw"])
    pts = [px(x + c * ax + s * az, z - s * ax + c * az) for ax, az in ((-sx/2, -sz/2), (sx/2, -sz/2), (sx/2, sz/2), (-sx/2, sz/2))]
    col = "#" + p["color"]
    if p["ball"]:
        a, b = px(x - sx/2, z - sz/2), px(x + sx/2, z + sz/2); dr.ellipse([a, b], fill=col, outline="#00000060")
    else:
        dr.polygon(pts, fill=col, outline="#00000050" if min(sx, sz) > 1.5 else None)
for name, s in d["spawns"].items():
    a = px(s[0], s[2]); dr.ellipse([a[0]-6, a[1]-6, a[0]+6, a[1]+6], fill="#ffffff", outline="#000000")
    dr.text((a[0]+9, a[1]-6), "spawn: " + name, fill="#000000")
for p in d["presets"]["Showcase"]:
    a = px(p[0], p[2]); dr.ellipse([a[0]-3, a[1]-3, a[0]+3, a[1]+3], fill="#f5cd30", outline="#000000")
for z in d["zones"]:
    a = px(z[1], z[2]); dr.text((a[0]-40, a[1]+10), z[0].upper(), fill="#102040")
dr.text((10, 10), "RAGDOLL CRASH PHYSICS - map top view (north = -Z = up). yellow dots: Showcase dummies", fill="#000000")
out = os.path.join(here, "..", "..", "docs", "map_topdown.png")
os.makedirs(os.path.dirname(out), exist_ok=True)
im.save(out); print("wrote", out)
