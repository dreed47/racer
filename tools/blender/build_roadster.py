"""Build the roadster model in Blender, save the .blend and export the .glb for Godot.

    blender -b -P tools/blender/build_roadster.py

Writes car/roadster/source/roadster.blend and car/roadster/roadster.glb. Running it again
replaces both, so hand edits in the .blend are lost; after hand edits, export with
export_track.py instead (it works for any model):

    blender -b car/roadster/source/roadster.blend -P tools/blender/export_track.py -- car/roadster/roadster.glb

Blender axes: Z up, +Y forward, +X right. The origin is the car's centre of mass, which sits
0.445 m above the ground at rest. Sizes match car/roadster.tres.

Object names Godot looks for (see car/car_look.gd):
- wheel: one wheel (tyre, rim, disc) at the front left, spinning about X, outer face to -X.
  Godot copies it to all four corners.
- caliper: the brake caliper for that wheel. It turns with steering but does not spin.
- steering_wheel: origin at the hub; the rim lies in its local XZ plane.
- brake_lights: glow when braking.
Everything else is the body and only needs to look right.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import export_track  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
OUT_DIR = os.path.join(ROOT, "car", "roadster")
BLEND_PATH = os.path.join(OUT_DIR, "source", "roadster.blend")
GLB_PATH = os.path.join(OUT_DIR, "roadster.glb")

GROUND = -0.445  # Ground height below the centre of mass, at rest.
AXLE_Y = 1.135  # Half the wheelbase.
WHEEL_X = 0.705  # Half the track width.
WHEEL_R = 0.29
WHEEL_Z = GROUND + WHEEL_R
DRIVER_X = -0.33  # Left seat.

# Body shape along its length: (y, half width, bottom, top, bonnet dip), heights above ground.
# The dip lowers the middle of the top between the front wings.
STATIONS = [
    (1.95, 0.55, 0.30, 0.52, 0.00),
    (1.90, 0.70, 0.22, 0.58, 0.02),
    (1.75, 0.80, 0.18, 0.64, 0.05),
    (1.40, 0.84, 0.17, 0.72, 0.07),
    (1.135, 0.845, 0.17, 0.73, 0.07),
    (0.80, 0.83, 0.17, 0.72, 0.06),
    (0.40, 0.82, 0.17, 0.74, 0.04),
    (0.10, 0.82, 0.17, 0.80, 0.01),
    (-0.30, 0.82, 0.17, 0.82, 0.00),
    (-0.80, 0.83, 0.17, 0.84, 0.00),
    (-1.135, 0.85, 0.17, 0.85, 0.00),
    (-1.50, 0.83, 0.18, 0.84, 0.00),
    (-1.80, 0.78, 0.22, 0.80, 0.00),
    (-1.95, 0.70, 0.30, 0.74, 0.00),
    (-1.98, 0.55, 0.36, 0.68, 0.00),
]
RING = 24  # Points round each body section.
SQUARENESS = 4.0  # Superellipse power: 2 is an oval, higher is boxier.

# Colours in sRGB, with roughness and metallic.
MATERIALS = {
    "paint": ((0.78, 0.07, 0.06), 0.3, 0.0),
    "trim": ((0.04, 0.04, 0.045), 0.6, 0.0),
    "interior": ((0.09, 0.08, 0.08), 0.85, 0.0),
    "seat": ((0.25, 0.14, 0.09), 0.7, 0.0),
    "glass": ((0.55, 0.65, 0.7), 0.05, 0.0),
    "silver": ((0.78, 0.79, 0.8), 0.3, 1.0),
    "tyre": ((0.06, 0.06, 0.06), 0.9, 0.0),
    "disc": ((0.35, 0.35, 0.36), 0.5, 1.0),
    "caliper": ((0.75, 0.6, 0.1), 0.45, 0.0),
    "lens": ((0.9, 0.92, 0.95), 0.1, 0.0),
    "tail": ((0.55, 0.02, 0.02), 0.25, 0.0),
    "indicator": ((0.95, 0.5, 0.05), 0.25, 0.0),
    "helmet": ((0.92, 0.92, 0.9), 0.3, 0.0),
    "visor": ((0.05, 0.06, 0.08), 0.1, 0.0),
    "suit": ((0.12, 0.2, 0.42), 0.8, 0.0),
    "glove": ((0.08, 0.08, 0.08), 0.8, 0.0),
}


def material(name):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    colour, rough, metal = MATERIALS[name]
    m = bpy.data.materials.new(name)
    bsdf = m.node_tree.nodes["Principled BSDF"]
    linear = [c ** 2.2 for c in colour]
    bsdf.inputs["Base Color"].default_value = (*linear, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    m.diffuse_color = (*linear, 1.0)
    if name == "glass":
        bsdf.inputs["Alpha"].default_value = 0.3
        if hasattr(m, "surface_render_method"):
            m.surface_render_method = "BLENDED"
    return m


class Parts:
    """Collects vertices and faces for one mesh, with a material per face."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.mats = []

    def add(self, verts, faces, mat):
        i = len(self.verts)
        self.verts += [tuple(map(float, v)) for v in verts]
        self.faces += [tuple(int(k) + i for k in f) for f in faces]
        self.mats += [mat] * len(faces)
        return self

    def build(self, name, smooth_angle=35.0, location=(0, 0, 0), rotation=(0, 0, 0)):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.verts, [], self.faces)
        names = list(dict.fromkeys(self.mats))
        for n in names:
            me.materials.append(material(n))
        me.polygons.foreach_set("material_index", [names.index(m) for m in self.mats])
        me.validate()
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)  # Every part's faces point outward.
        bm.to_mesh(me)
        bm.free()
        smooth(me, smooth_angle)
        ob = bpy.data.objects.new(name, me)
        ob.location = location
        ob.rotation_euler = rotation
        bpy.context.scene.collection.objects.link(ob)
        return ob


def smooth(me, angle):
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(angle))


# ---------------------------------------------------------------- shapes
# Each returns (verts, faces).

def grid_faces(rows, cols, wrap_cols=True):
    """Quads joining rows of points, each row holding cols points."""
    faces = []
    span = cols if wrap_cols else cols - 1
    for r in range(rows - 1):
        for c in range(span):
            c2 = (c + 1) % cols
            faces.append((r * cols + c, r * cols + c2, (r + 1) * cols + c2, (r + 1) * cols + c))
    return faces


def loft(sections, cap_start=True, cap_end=True):
    """Joins closed rings of the same size into a tube, with flat end caps."""
    rows = len(sections)
    cols = len(sections[0])
    verts = [p for s in sections for p in s]
    faces = grid_faces(rows, cols)
    if cap_start:
        faces.append(tuple(range(cols))[::-1])
    if cap_end:
        faces.append(tuple(range((rows - 1) * cols, rows * cols)))
    return verts, faces


def lathe(profile, segments, axis_centre=(0, 0, 0)):
    """Spins (x, radius) points round the X axis. Faces point outward when x rises along the profile."""
    cx, cy, cz = axis_centre
    verts = []
    for x, r in profile:
        for k in range(segments):
            a = 2 * math.pi * k / segments
            verts.append((cx + x, cy + r * math.cos(a), cz + r * math.sin(a)))
    faces = grid_faces(len(profile), segments)
    return verts, [f[::-1] for f in faces]


def ellipsoid(centre, radii, rings=8, segments=12):
    cx, cy, cz = centre
    rx, ry, rz = radii
    verts = [(cx, cy, cz - rz)]
    for i in range(1, rings):
        t = math.pi * i / rings - math.pi / 2
        for k in range(segments):
            a = 2 * math.pi * k / segments
            verts.append((cx + rx * math.cos(t) * math.cos(a), cy + ry * math.cos(t) * math.sin(a), cz + rz * math.sin(t)))
    verts.append((cx, cy, cz + rz))
    top = len(verts) - 1
    faces = [(0, 1 + (k + 1) % segments, 1 + k) for k in range(segments)]
    faces += [tuple(1 + i for i in f) for f in grid_faces(rings - 1, segments)]
    last = 1 + (rings - 2) * segments
    faces += [(last + k, last + (k + 1) % segments, top) for k in range(segments)]
    return verts, faces


def box(lo, hi):
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    verts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
             (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return verts, faces


def tube(path, radius, segments=8):
    """A round tube along a list of points, with closed ends."""
    path = np.asarray(path, dtype=float)
    sections = []
    for i, p in enumerate(path):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, len(path) - 1)]
        d = (b - a) / np.linalg.norm(b - a)
        side = np.cross(d, (0, 0, 1)) if abs(d[2]) < 0.9 else np.cross(d, (1, 0, 0))
        side /= np.linalg.norm(side)
        up = np.cross(side, d)
        sections.append([p + radius * (math.cos(t) * side + math.sin(t) * up)
                         for t in np.linspace(0, 2 * math.pi, segments, endpoint=False)])
    return loft(sections)


def h(height):
    """Height above the ground to Blender Z."""
    return GROUND + height


# ---------------------------------------------------------------- body

def body_section(y, half, bottom, top, dip):
    centre = (bottom + top) / 2
    half_h = (top - bottom) / 2
    ring = []
    for k in range(RING):
        a = 2 * math.pi * k / RING
        c, s = math.cos(a), math.sin(a)
        x = half * math.copysign(abs(c) ** (2 / SQUARENESS), c)
        z = centre + half_h * math.copysign(abs(s) ** (2 / SQUARENESS), s)
        if s > 0 and dip:
            z -= dip * max(0.0, 1 - (x / (0.65 * half)) ** 2)
        ring.append((x, y, h(z)))
    return ring


def build_body():
    # Ring order runs right, top, left, bottom; the loft goes nose to tail.
    sections = [body_section(*s)[::-1] for s in STATIONS]
    verts, faces = loft(sections)
    body = Parts().add(verts, faces, "paint").build("body")
    sub = body.modifiers.new("smooth", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1

    cutters = []
    for y, r in ((AXLE_Y, 0.37), (-AXLE_Y, 0.35)):
        for side in (-1, 1):
            # Wheel arch: a short drum from inside the wing to past the outside.
            prof = [(0.55, 0.0), (0.55, r), (1.2, r), (1.2, 0.0)]
            v, f = lathe(prof, 32, (0, y, WHEEL_Z + 0.02))
            if side < 0:
                v = [(-x, yy, z) for x, yy, z in v]
                f = [ff[::-1] for ff in f]
            cutters.append(Parts().add(v, f, "interior").build("cut_arch"))
    # Cockpit tub.
    v, f = box((-0.64, -1.0, h(0.42)), (0.64, 0.05, h(1.3)))
    cutters.append(Parts().add(v, f, "interior").build("cut_cockpit"))

    for i, c in enumerate(cutters):
        b = body.modifiers.new("cut%d" % i, "BOOLEAN")
        b.operation = "DIFFERENCE"
        b.solver = "EXACT"
        b.object = c
        b.material_mode = "TRANSFER"
        c.hide_render = True
    apply_modifiers(body)
    for c in cutters:
        bpy.data.objects.remove(c)
    smooth(body.data, 35.0)
    return body


def apply_modifiers(ob):
    deps = bpy.context.evaluated_depsgraph_get()
    evaluated = ob.evaluated_get(deps)
    me = bpy.data.meshes.new_from_object(evaluated)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)
    me.name = ob.name


# ---------------------------------------------------------------- parts

def build_cockpit():
    p = Parts()
    # Floor and dash.
    p.add(*box((-0.64, -1.0, h(0.20)), (0.64, 0.05, h(0.22))), "interior")
    p.add(*box((-0.64, -0.08, h(0.55)), (0.64, 0.05, h(0.79))), "trim")
    # Transmission tunnel.
    p.add(*box((-0.12, -0.9, h(0.21)), (0.12, 0.05, h(0.42))), "interior")
    # Seats: cushion and a back leaning rearwards.
    for x in (DRIVER_X, -DRIVER_X):
        p.add(*box((x - 0.24, -0.85, h(0.22)), (x + 0.24, -0.35, h(0.34))), "seat")
        back = ellipsoid((x, -0.86, h(0.62)), (0.24, 0.07, 0.30), 6, 12)
        p.add(*back, "seat")
    p.build("cockpit")

    # Windscreen: glass in a black frame, leaning back.
    base_y, base_z = 0.04, h(0.80)
    top_y, top_z = -0.26, h(1.15)
    half_base, half_top = 0.68, 0.62
    glass = Parts()
    t = 0.006
    corners = [(-half_base, base_y, base_z), (half_base, base_y, base_z),
               (half_top, top_y, top_z), (-half_top, top_y, top_z)]
    inner = [(x, y - t, z) for x, y, z in corners]
    glass.add(corners + inner, [(0, 1, 2, 3), (7, 6, 5, 4)], "glass").build("windscreen", 10)
    frame_path = corners + [corners[0]]
    frame = Parts()
    for a, b in zip(frame_path, frame_path[1:]):
        frame.add(*tube([a, b], 0.018, 6), "trim")
    # Roll hoops behind the seats.
    for x in (DRIVER_X, -DRIVER_X):
        hoop = [(x + 0.2 * math.cos(a), -0.97, h(0.80) + 0.32 * math.sin(a))
                for a in np.linspace(0, math.pi, 9)]
        frame.add(*tube(hoop, 0.022, 8), "silver")
    # Mirrors on short stalks at the screen base.
    for side in (-1, 1):
        stalk = [(side * 0.66, 0.02, h(0.80)), (side * 0.80, 0.0, h(0.88))]
        frame.add(*tube(stalk, 0.012, 6), "trim")
        frame.add(*ellipsoid((side * 0.86, -0.01, h(0.90)), (0.07, 0.03, 0.045), 6, 10), "paint")
    frame.build("frame")


def build_lights_and_trim():
    lights = Parts()
    for side in (-1, 1):
        lights.add(*ellipsoid((side * 0.58, 1.74, h(0.615)), (0.11, 0.17, 0.065), 6, 14), "lens")
        lights.add(*ellipsoid((side * 0.72, 1.85, h(0.42)), (0.05, 0.05, 0.025), 4, 10), "indicator")
    lights.build("headlights", 60)

    brake = Parts()
    for side in (-1, 1):
        brake.add(*ellipsoid((side * 0.58, -1.955, h(0.66)), (0.1, 0.035, 0.05), 6, 14), "tail")
    brake.build("brake_lights", 60)

    trim = Parts()
    # Grille: an oval mouth in the nose.
    trim.add(*ellipsoid((0, 1.945, h(0.40)), (0.30, 0.03, 0.065), 6, 16), "trim")
    # Bumper strips front and back.
    trim.add(*tube([(-0.5, 1.93, h(0.30)), (0.5, 1.93, h(0.30))], 0.02, 6), "silver")
    trim.add(*tube([(-0.6, -1.985, h(0.44)), (0.6, -1.985, h(0.44))], 0.02, 6), "silver")
    # Twin exhausts under the tail.
    for x in (0.22, 0.32):
        trim.add(*lathe([(0, 0.0), (0, 0.035), (0.25, 0.035), (0.25, 0.028), (0.0, 0.028)], 12, (0, 0, 0)), "silver")
        v = trim.verts[-60:]
        # Turn the last exhaust from the X axis to point backwards, then move it into place.
        trim.verts[-60:] = [(x + yy, -1.84 - xx, h(0.24) + zz) for xx, yy, zz in v]
    # Fuel filler on the rear deck.
    trim.add(*lathe([(0, 0.0), (0, 0.05), (0.01, 0.05), (0.012, 0.0)], 14), "silver")
    trim.verts[-56:] = [(0.5 + zz, -1.55 + yy, h(0.85) + xx) for xx, yy, zz in trim.verts[-56:]]
    trim.build("trim", 40)


def build_driver():
    p = Parts()
    x = DRIVER_X
    # Torso leaning back against the seat.
    p.add(*ellipsoid((x, -0.72, h(0.70)), (0.19, 0.12, 0.27), 8, 12), "suit")
    # Helmet and visor.
    p.add(*ellipsoid((x, -0.70, h(1.08)), (0.13, 0.145, 0.14), 10, 16), "helmet")
    p.add(*ellipsoid((x, -0.60, h(1.08)), (0.105, 0.06, 0.05), 6, 12), "visor")
    # Neck.
    p.add(*tube([(x, -0.72, h(0.92)), (x, -0.71, h(0.98))], 0.05, 8), "suit")
    # Arms from the shoulders to quarter to three on the steering wheel.
    for side in (-1, 1):
        shoulder = (x + side * 0.17, -0.70, h(0.90))
        elbow = (x + side * 0.22, -0.42, h(0.80))
        hand = (x + side * 0.16, -0.17, h(0.90))
        p.add(*tube([shoulder, elbow, hand], 0.045, 8), "suit")
        p.add(*ellipsoid(hand, (0.04, 0.045, 0.04), 5, 8), "glove")
    p.build("driver")


def build_steering_wheel():
    p = Parts()
    rim = [(0.17 * math.cos(a), 0.0, 0.17 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 25)]
    p.add(*tube(rim, 0.016, 8), "trim")
    for a in (0.0, math.pi, -math.pi / 2):
        p.add(*tube([(0, 0, 0), (0.16 * math.cos(a), 0, 0.16 * math.sin(a))], 0.012, 6), "silver")
    p.add(*lathe([(0, 0.0), (0, 0.04), (0.04, 0.04), (0.04, 0.0)], 12), "trim")
    p.verts[-48:] = [(yy, xx, zz) for xx, yy, zz in p.verts[-48:]]  # Hub along Y.
    p.add(*tube([(0, 0, 0), (0, 0.35, 0)], 0.022, 8), "trim")  # Column towards the dash.
    # Tilted so the top leans forward, column running forwards and down.
    p.build("steering_wheel", 40, (DRIVER_X, -0.16, h(0.88)), (math.radians(-20), 0, 0))


def build_wheel():
    """Front left wheel: outer face towards -X, centre at the wheel's place on the car."""
    w = Parts()
    half = 0.0975
    tyre = [(half, 0.19), (half, 0.255), (half - 0.008, 0.278), (half - 0.025, 0.29),
            (-half + 0.025, 0.29), (-half + 0.008, 0.278), (-half, 0.255), (-half, 0.19)]
    # Profile runs from inner (+X) to outer (-X); reversing keeps faces pointing out.
    w.add(*lathe(tyre[::-1], 36), "tyre")
    rim = [(half - 0.005, 0.175), (half - 0.005, 0.192), (-half + 0.005, 0.192), (-half + 0.005, 0.175),
           (-half + 0.02, 0.172), (half - 0.01, 0.172)]
    w.add(*lathe(rim[::-1], 36), "silver")
    # Five spokes and the hub on the outer face.
    face = -0.065
    for k in range(5):
        a = 2 * math.pi * k / 5
        d = np.array((0, math.cos(a), math.sin(a)))
        s = np.array((0, -math.sin(a), math.cos(a)))
        pts = []
        for r, width in ((0.04, 0.05), (0.176, 0.03)):
            for sign in (-1, 1):
                pts.append(r * d + sign * width / 2 * s)
        q = [(face - 0.012, *p[1:]) for p in pts] + [(face + 0.012, *p[1:]) for p in pts]
        # pts: inner-left, inner-right, outer-left, outer-right.
        faces = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
        w.add(q, faces, "silver")
    w.add(*lathe([(face - 0.02, 0.0), (face - 0.02, 0.03), (face - 0.005, 0.055), (face + 0.012, 0.055)], 14), "silver")
    # Brake disc, seen through the spokes.
    w.add(*lathe([(0.0, 0.06), (0.0, 0.135), (0.022, 0.135), (0.022, 0.06), (0.0, 0.06)], 28), "disc")
    w.build("wheel", 30, (-WHEEL_X, AXLE_Y, WHEEL_Z))

    c = Parts()
    c.add(*box((-0.012, -0.05, 0.095), (0.038, 0.05, 0.155)), "caliper")
    c.build("caliper", 30, (-WHEEL_X, AXLE_Y, WHEEL_Z))


def build_underside():
    p = Parts()
    # Dark floor pan, so the road does not show through gaps.
    p.add(*box((-0.6, -1.7, h(0.17)), (0.6, 1.7, h(0.19))), "trim")
    p.build("underside", 30)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_body()
    build_cockpit()
    build_lights_and_trim()
    build_driver()
    build_steering_wheel()
    build_wheel()
    build_underside()
    # Show the other three wheels in the .blend too, as linked copies; they are not exported.
    src = bpy.data.objects["wheel"]
    for x, y, rot in ((WHEEL_X, AXLE_Y, math.pi), (-WHEEL_X, -AXLE_Y, 0.0), (WHEEL_X, -AXLE_Y, math.pi)):
        copy = bpy.data.objects.new("preview_wheel", src.data)
        copy.location = (x, y, WHEEL_Z)
        copy.rotation_euler = (0, 0, rot)
        copy.hide_render = True
        bpy.context.scene.collection.objects.link(copy)

    tris = sum(len(p.vertices) - 2 for ob in bpy.data.objects if ob.type == "MESH"
               and not ob.name.startswith("preview") for p in ob.data.polygons)
    print("triangles: %d (one wheel counted)" % tris)

    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    with open(os.path.join(os.path.dirname(BLEND_PATH), ".gdignore"), "w"):
        pass  # Keeps Godot from importing the .blend itself.
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    # The preview wheels stay in the .blend but not in the export.
    for ob in [o for o in bpy.data.objects if o.name.startswith("preview_wheel")]:
        bpy.data.objects.remove(ob)
    export_track.export(GLB_PATH)
    print("saved", BLEND_PATH)
    print("exported", GLB_PATH)


main()
