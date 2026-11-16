"""Packs every finished vehicle (out/<Vehicle>.blend) into ONE file, out/AllVehicles.glb, where each
vehicle is a parent node named after its game key. In Studio: File > Import 3D > AllVehicles.glb once,
then move the imported model into ReplicatedStorage and rename it VehicleMeshes."""
import json, os
import bpy
HERE = os.path.dirname(os.path.abspath(__file__))
order = json.load(open(os.path.join(HERE, "vehicles.json")))["order"]
bpy.ops.wm.read_factory_settings(use_empty=True)
for key in order:
    path = os.path.join(HERE, "out", key + ".blend")
    with bpy.data.libraries.load(path) as (src, dst):
        dst.objects = [n for n in src.objects if n.startswith(key + "_")]
    root = bpy.data.objects.new(key, None)
    bpy.context.scene.collection.objects.link(root)
    for ob in dst.objects:
        bpy.context.scene.collection.objects.link(ob)
        mw = ob.matrix_world.copy()
        ob.parent = root
        ob.matrix_world = mw
# point every texture at its real file (appending into an unsaved file can leave '//' paths dangling)
for img in bpy.data.images:
    name = os.path.basename(bpy.path.abspath(img.filepath)) if img.filepath else ""
    for key in order:
        cand = os.path.join(HERE, "out", "textures", key, name)
        if name and name.startswith(key + "_") and os.path.exists(cand):
            img.filepath = cand
            img.reload()
            break
missing = [i.name for i in bpy.data.images if i.filepath and not os.path.exists(bpy.path.abspath(i.filepath))]
print("missing textures:", missing)
out = os.path.join(HERE, "out", "AllVehicles.glb")
try:
    bpy.ops.export_scene.gltf(filepath=out, export_yup=True, export_image_format="JPEG", export_image_quality=85)
except TypeError:
    bpy.ops.export_scene.gltf(filepath=out, export_yup=True, export_image_format="JPEG", export_jpeg_quality=85)
print("wrote", out, os.path.getsize(out) // 1024, "KB")
