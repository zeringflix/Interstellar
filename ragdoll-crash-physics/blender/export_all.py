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
out = os.path.join(HERE, "out", "AllVehicles.glb")
bpy.ops.export_scene.gltf(filepath=out, export_yup=True)
print("wrote", out, os.path.getsize(out) // 1024, "KB")
