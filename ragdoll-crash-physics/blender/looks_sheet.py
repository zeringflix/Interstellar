"""Contact sheets of the five looks per vehicle: docs/looks_<n>.jpg (6 vehicles per sheet)."""
import json, os
from PIL import Image, ImageDraw, ImageFont
HERE = os.path.dirname(os.path.abspath(__file__))
order = json.load(open(os.path.join(HERE, "vehicles.json")))["order"]
names = {k: v["display"] for k, v in json.load(open(os.path.join(HERE, "vehicles.json")))["vehicles"].items()}
CAMO = {"Tank", "ArmoredTruck"}
def look_names(k):
    return ["Factory Clean", "Daily Use", "Battered"] + (["Arctic Camo", "Desert Camo"] if k in CAMO else ["Two-Tone Livery", "Matte Rally"])
W, H, LBL = 384, 240, 26
font = lambda s: ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", s)
done = [k for k in order if all(os.path.exists(os.path.join(HERE, "out", "previews", "looks", "%s_%d.png" % (k, n))) for n in range(1, 6))]
sheets = [done[i:i + 6] for i in range(0, len(done), 6)]
out_dir = os.path.join(HERE, "..", "docs")
for si, keys in enumerate(sheets):
    im = Image.new("RGB", (W * 5, (H + LBL * 2) * len(keys)), (24, 26, 30))
    d = ImageDraw.Draw(im)
    for r, k in enumerate(keys):
        y0 = r * (H + LBL * 2)
        d.rectangle([0, y0, W * 5, y0 + LBL], fill=(46, 50, 58))
        d.text((10, y0 + 2), names[k].upper(), fill=(255, 210, 74), font=font(19))
        for n in range(5):
            p = os.path.join(HERE, "out", "previews", "looks", "%s_%d.png" % (k, n + 1))
            img = Image.open(p).convert("RGB")
            w0, h0 = img.size  # crop the empty floor around the vehicle a little
            img = img.crop((int(w0 * 0.06), int(h0 * 0.08), int(w0 * 0.94), int(h0 * 0.92))).resize((W, H))
            im.paste(img, (n * W, y0 + LBL))
            d.text((n * W + 8, y0 + LBL + H + 3), "%d  %s" % (n + 1, look_names(k)[n]), fill=(235, 238, 244), font=font(17))
    path = os.path.join(out_dir, "looks_%d.jpg" % (si + 1))
    im.save(path, quality=84)
    print(path, keys)
