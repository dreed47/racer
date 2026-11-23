"""Export an open Blender track to a .glb that Godot can load.

Run after editing a track by hand:

    blender -b track/ridge/source/ridge.blend -P tools/blender/export_track.py -- track/ridge/ridge.glb

build_ridge.py calls export() too, so both use the same settings.
"""

import sys

import bpy


def export(path):
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,  # Blender Z up becomes Godot Y up; Blender +Y forward becomes Godot -Z.
        export_apply=True,
        use_mesh_edges=True,  # Keeps the Centreline edge loop.
        export_extras=False,
        export_draco_mesh_compression_enable=False,
    )


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(args) != 1:
        sys.exit("usage: blender -b <track.blend> -P export_track.py -- <out.glb>")
    export(args[0])
    print("exported", args[0])
