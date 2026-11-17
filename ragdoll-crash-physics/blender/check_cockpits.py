"""Cockpit sanity check: the steering control of every vehicle must not intersect anything.

    python3 check_cockpits.py [Vehicle ...]

Opens out/<Vehicle>.blend, builds world-space BVH trees and reports any triangles of the
<Vehicle>_Steer mesh (wheel, yoke, T-bar) that overlap another mesh: the dash, the instrument
cluster, the windscreen, the body. A wheel that cuts into the cluster or pokes through the glass
fails. Exits 1 if any vehicle fails.
"""
import json
import os
import sys

import bpy
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")


def world_tree(ob, dg):
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    mw = ob.matrix_world
    tree = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    ev.to_mesh_clear()
    return tree


def check(key):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT, key + ".blend"))
    dg = bpy.context.evaluated_depsgraph_get()
    steer = bpy.data.objects.get(key + "_Steer")
    if steer is None:
        return None
    tree = world_tree(steer, dg)
    hits = {}
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH" and ob != steer:
            n = len(tree.overlap(world_tree(ob, dg)))
            if n:
                hits[ob.name] = n
    return hits


def main():
    order = json.load(open(os.path.join(HERE, "vehicles.json")))["order"]
    keys = [a for a in sys.argv[1:] if a in order] or order
    bad = 0
    for key in keys:
        hits = check(key)
        if hits is None:
            print("COCKPIT", key, "no steering control mesh (sticks / levers / grips)", flush=True)
        elif hits:
            bad += 1
            print("COCKPIT", key, "FAIL steering control intersects", hits, flush=True)
        else:
            print("COCKPIT", key, "ok", flush=True)
    print("COCKPIT RESULT", "%d of %d vehicles clash" % (bad, len(keys)), flush=True)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
