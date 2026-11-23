"""Build the Ridge track in Blender, save the .blend and export the .glb for Godot.

    blender -b -P tools/blender/build_ridge.py

Writes track/ridge/source/ridge.blend and track/ridge/ridge.glb. Running it again replaces
both, so hand edits in the .blend are lost; after hand edits, use export_track.py instead.

Blender axes: Z up, the lap starts at the origin heading +Y. Right turns are positive.
Object names tell Godot what each surface is (see track/blender_track.gd):
road, kerb_*, grass, gravel, wall, stand, tree_*; deco_* has no collision.
Empties Gate0..Gate6 are the start line and checkpoints (local +Y points the driving way),
Spawn is where the car starts, and Centreline is an edge loop along the middle of the road.
"""

import math
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import export_track  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
OUT_DIR = os.path.join(ROOT, "track", "ridge")
BLEND_PATH = os.path.join(OUT_DIR, "source", "ridge.blend")
GLB_PATH = os.path.join(OUT_DIR, "ridge.glb")

# Pieces in driving order: (length, 0) is a straight, (radius, degrees) an arc.
# L1 and L2 are solved so the loop closes.
PIECES = [
    (400, 0),     # 0  main straight, start line near the beginning
    (35, 90),     # 1  T1
    (150, 0),     # 2
    (70, -40),    # 3  esses
    (70, 40),     # 4
    (200, 0),     # 5  climb to the crest
    (90, 70),     # 6  T4, over the crest and downhill
    (200, 0),     # 7  downhill straight
    (50, -90),    # 8  T5
    (100, 0),     # 9
    (25, 170),    # 10 hairpin
    (250, 0),     # 11 back straight
    (160, -30),   # 12 fast sweepers
    (160, 30),    # 13
    ("L1", 0),    # 14
    (40, 110),    # 15 T9, onto the main straight
    ("L2", 0),    # 16
]
# Height in metres at points along the lap, as (piece, fraction through the piece, height).
# Smoothed afterwards, so slopes ease in and out.
ELEVATION = [
    (0, 0.0, 0.0),
    (1, 1.0, 0.5),
    (5, 0.6, 8.0),
    (6, 0.1, 12.5),   # the crest, just into T4
    (7, 0.0, 8.0),
    (8, 0.0, 3.0),
    (10, 0.5, 0.0),
    (12, 1.0, -3.0),  # dip between the sweepers
    (15, 0.0, 0.0),
]
ELEVATION_SMOOTHING = 15.0  # metres
GRAVEL_CORNERS = [1, 6, 8, 10, 15]
# (piece, metres from the centreline, side: +1 right, -1 left)
WALLS = [(6, 30.0, -1), (12, 14.0, 1), (13, 14.0, -1)]

STEP = 2.0
ROAD_HALF = 5.0
KERB_OUT = 6.2
KERB_RISE = 0.05
SKIRT = 0.4  # Road and kerb edges drop this far, so no gaps show under them.
GRASS_DROP = 0.08  # Ground beside the road sits this far below it.
FLAT_BAND = 11.0  # Ground within this distance of the centreline follows the road height.
GRID = 4.0
MARGIN = 120.0
START = 60.0  # Start line, metres along the lap.
SPAWN_BACK = 30.0
CHECKPOINTS = 6

COLOURS = {
    "road": (0.24, 0.24, 0.26),
    "paint": (0.92, 0.92, 0.9),
    "dark": (0.08, 0.08, 0.08),
    "kerb_red": (0.78, 0.1, 0.08),
    "kerb_white": (0.92, 0.92, 0.9),
    "grass": (0.2, 0.34, 0.16),
    "gravel": (0.66, 0.6, 0.48),
    "wall": (0.72, 0.72, 0.7),
    "stand": (0.55, 0.56, 0.6),
    "roof": (0.2, 0.32, 0.55),
    "trunk": (0.36, 0.25, 0.15),
    "leaves": (0.16, 0.33, 0.14),
}


# ---------------------------------------------------------------- layout

def piece_length(r, d):
    return r * math.radians(abs(d)) if d else r


def trace(pieces):
    """Samples about every STEP metres. Returns points (N,2), curvature (N), piece index (N),
    distance (N), and the end point and heading after the last piece."""
    x = y = h = 0.0
    pts, curv, owner, dist = [], [], [], []
    s = 0.0
    for k, (r, d) in enumerate(pieces):
        L = piece_length(r, d)
        n = max(1, math.ceil(L / STEP))
        turn = math.radians(d) / n
        chord = 2 * r * math.sin(abs(turn) / 2) if d else L / n
        for _ in range(n):
            pts.append((x, y))
            curv.append(math.copysign(1.0 / r, d) if d else 0.0)
            owner.append(k)
            dist.append(s)
            hm = h + turn / 2
            x += math.sin(hm) * chord
            y += math.cos(hm) * chord
            h += turn
            s += L / n
    return np.array(pts), np.array(curv), np.array(owner), np.array(dist), (x, y), h, s


def solve_pieces():
    def with_lengths(a, b):
        return [(a if r == "L1" else b if r == "L2" else r, d) for r, d in PIECES]

    def end(a, b):
        return np.array(trace(with_lengths(a, b))[4])

    e0, ea, eb = end(0, 0), end(1, 0), end(0, 1)
    a, b = np.linalg.solve(np.column_stack([ea - e0, eb - e0]), -e0)
    if a <= 0 or b <= 0:
        sys.exit("layout does not close with positive L1/L2 (%.1f, %.1f)" % (a, b))
    return with_lengths(a, b)


def smooth_periodic(values, sigma):
    n = len(values)
    k = np.fft.fftfreq(n)
    return np.real(np.fft.ifft(np.fft.fft(values) * np.exp(-2 * (math.pi * k * sigma) ** 2)))


def elevation(pieces, dist, total):
    starts = np.cumsum([0] + [piece_length(r, d) for r, d in pieces])
    keys = sorted((starts[p] + f * piece_length(*pieces[p]), z) for p, f, z in ELEVATION)
    ks = np.array([k[0] for k in keys])
    kz = np.array([k[1] for k in keys])
    fine = np.arange(0.0, total, 1.0)
    z = np.interp(fine, ks, kz, period=total)
    z = smooth_periodic(z, ELEVATION_SMOOTHING)
    return np.interp(dist, fine, z, period=total), starts


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- Blender helpers

def material(name):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    bsdf = m.node_tree.nodes["Principled BSDF"]
    linear = [c ** 2.2 for c in COLOURS[name]]
    bsdf.inputs["Base Color"].default_value = (*linear, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.9
    m.diffuse_color = (*linear, 1.0)
    return m


def add_mesh(name, verts, faces, mat=None, edges=()):
    verts = np.asarray(verts, dtype=float)
    if len(faces):
        # Drop vertices no face uses.
        flat = np.concatenate([np.asarray(f) for f in faces])
        used, inverse = np.unique(flat, return_inverse=True)
        verts = verts[used]
        sizes = [len(f) for f in faces]
        faces = np.split(inverse, np.cumsum(sizes)[:-1])
        faces = [tuple(int(i) for i in f) for f in faces]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts.tolist(), list(edges), faces)
    me.validate()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if mat:
        me.materials.append(material(mat))
    return ob


def add_empty(name, x, y, z, heading):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_type = "SINGLE_ARROW"
    ob.empty_display_size = 4.0
    ob.location = (x, y, z)
    # Arrow (local Z) up; local +Y points the driving way.
    ob.rotation_euler = (0.0, 0.0, -heading)
    bpy.context.scene.collection.objects.link(ob)
    return ob


class Builder:
    """Collects vertices and faces for one mesh."""

    def __init__(self):
        self.verts = []
        self.faces = []

    def quad(self, a, b, c, d):
        i = len(self.verts)
        self.verts += [a, b, c, d]
        self.faces.append((i, i + 1, i + 2, i + 3))

    def poly(self, points):
        i = len(self.verts)
        self.verts += list(points)
        self.faces.append(tuple(range(i, i + len(points))))

    def box(self, origin, u, v, z0, z1):
        """Box from origin along u and v (horizontal vectors), between heights z0 and z1."""
        o = np.array(origin[:2])
        u = np.array(u)
        v = np.array(v)
        c = [o, o + u, o + u + v, o + v]
        lo = [(p[0], p[1], z0) for p in c]
        hi = [(p[0], p[1], z1) for p in c]
        self.poly(hi)
        self.poly(lo[::-1])
        for k in range(4):
            j = (k + 1) % 4
            self.quad(lo[k], lo[j], hi[j], hi[k])

    def build(self, name, mat):
        if self.faces:
            add_mesh(name, self.verts, self.faces, mat)


# ---------------------------------------------------------------- build

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    pieces = solve_pieces()
    P, curv, owner, dist, end, end_heading, total = trace(pieces)
    n = len(P)
    print("lap %.0f m, %d samples, closes within %.3f m" % (total, n, math.hypot(*end)))
    H, starts = elevation(pieces, dist, total)
    fwd = np.roll(P, -1, axis=0) - np.roll(P, 1, axis=0)
    fwd /= np.linalg.norm(fwd, axis=1, keepdims=True)
    R = np.column_stack([fwd[:, 1], -fwd[:, 0]])  # right of the driving direction

    def at(s):
        """Position, height and heading at a distance along the lap."""
        s = s % total
        x = np.interp(s, dist, P[:, 0], period=total)
        y = np.interp(s, dist, P[:, 1], period=total)
        z = np.interp(s, dist, H, period=total)
        i = int(np.searchsorted(dist, s, side="right") - 1) % n
        return x, y, z, math.atan2(fwd[i, 0], fwd[i, 1])

    def pt(i, offset, dz=0.0):
        i %= n
        return (P[i, 0] + R[i, 0] * offset, P[i, 1] + R[i, 1] * offset, H[i] + dz)

    # Road, with a skirt down each side.
    road = Builder()
    for i in range(n):
        j = i + 1
        road.quad(pt(i, -ROAD_HALF), pt(i, ROAD_HALF), pt(j, ROAD_HALF), pt(j, -ROAD_HALF))
        road.quad(pt(i, ROAD_HALF), pt(i, ROAD_HALF, -SKIRT), pt(j, ROAD_HALF, -SKIRT), pt(j, ROAD_HALF))
        road.quad(pt(i, -ROAD_HALF, -SKIRT), pt(i, -ROAD_HALF), pt(j, -ROAD_HALF), pt(j, -ROAD_HALF, -SKIRT))
    road.build("road", "road")

    # Edge lines.
    lines = Builder()
    for i in range(n):
        j = i + 1
        for a, b in ((-ROAD_HALF, -ROAD_HALF + 0.25), (ROAD_HALF - 0.25, ROAD_HALF)):
            lines.quad(pt(i, a, 0.01), pt(i, b, 0.01), pt(j, b, 0.01), pt(j, a, 0.01))
    lines.build("deco_lines", "paint")

    # Kerbs on corners, both sides, red and white stripes.
    bendy = np.abs(curv) > 1.0 / 300.0
    kerb_on = np.zeros(n, bool)
    for shift in range(-5, 6):
        kerb_on |= np.roll(bendy, shift)
    stripes = {"kerb_red": Builder(), "kerb_white": Builder()}
    for i in np.nonzero(kerb_on)[0]:
        j = i + 1
        b = stripes["kerb_red" if i % 2 else "kerb_white"]
        for side in (-1, 1):
            inner, outer = side * ROAD_HALF, side * KERB_OUT
            b.quad(pt(i, inner), pt(i, outer, KERB_RISE), pt(j, outer, KERB_RISE), pt(j, inner))
            b.quad(pt(i, outer, KERB_RISE), pt(i, outer, -SKIRT), pt(j, outer, -SKIRT), pt(j, outer, KERB_RISE))
    for name, b in stripes.items():
        b.build(name, name)

    # Checkered start line: two rows of 1 m squares.
    sx, sy, sz, sh = at(START)
    f = np.array([math.sin(sh), math.cos(sh)])
    r = np.array([f[1], -f[0]])
    squares = {"paint": Builder(), "dark": Builder()}
    for row in range(2):
        for k in range(int(2 * ROAD_HALF)):
            o = np.array([sx, sy]) + f * (row - 1) + r * (k - ROAD_HALF)
            c = [o, o + r, o + r + f, o + f]
            squares["paint" if (row + k) % 2 == 0 else "dark"].poly([(p[0], p[1], sz + 0.02) for p in c])
    squares["paint"].build("deco_start_white", "paint")
    squares["dark"].build("deco_start_black", "dark")

    # Ground: a grid that follows the road near it and rolls into gentle hills further out.
    lo = P.min(axis=0) - MARGIN
    hi = P.max(axis=0) + MARGIN
    gx = np.arange(lo[0], hi[0] + GRID, GRID)
    gy = np.arange(lo[1], hi[1] + GRID, GRID)
    nx, ny = len(gx), len(gy)
    X, Y = np.meshgrid(gx, gy)
    V = np.column_stack([X.ravel(), Y.ravel()])

    def nearest(points):
        idx = np.empty(len(points), int)
        d = np.empty(len(points))
        for a in range(0, len(points), 4000):
            chunk = points[a:a + 4000]
            d2 = ((chunk[:, None, :] - P[None, :, :]) ** 2).sum(-1)
            k = d2.argmin(axis=1)
            idx[a:a + 4000] = k
            d[a:a + 4000] = np.sqrt(d2[np.arange(len(chunk)), k])
        offset = ((points - P[idx]) * R[idx]).sum(-1)
        return idx, d, offset

    idx, d, _ = nearest(V)
    sub = P[::5]
    sub_h = H[::5]
    field = np.empty(len(V))
    for a in range(0, len(V), 4000):
        chunk = V[a:a + 4000]
        w = np.exp(-((chunk[:, None, :] - sub[None, :, :]) ** 2).sum(-1) / (70.0 ** 2)) + 1e-12
        field[a:a + 4000] = (w * sub_h).sum(-1) / w.sum(-1)
    hills = (2.5 * np.sin(V[:, 0] / 85 + 0.7) * np.cos(V[:, 1] / 120 + 0.3)
             + 1.2 * np.sin((V[:, 0] - V[:, 1]) / 55)) * smoothstep(20, 140, d)
    flat = H[idx] - GRASS_DROP
    blend = smoothstep(FLAT_BAND, 50, d)
    Z = (flat * (1 - blend) + (field + hills) * blend).reshape(ny, nx)
    pinned = (d < FLAT_BAND).reshape(ny, nx)
    for _ in range(60):  # Smooth out kinks where the nearest piece of road changes.
        p = np.pad(Z, 1, mode="edge")
        avg = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / 4
        Z = np.where(pinned, Z, 0.5 * Z + 0.5 * avg)

    def ground(x, y):
        fx = np.clip((x - lo[0]) / GRID, 0, nx - 1.001)
        fy = np.clip((y - lo[1]) / GRID, 0, ny - 1.001)
        i, j = int(fx), int(fy)
        tx, ty = fx - i, fy - j
        return ((Z[j, i] * (1 - tx) + Z[j, i + 1] * tx) * (1 - ty)
                + (Z[j + 1, i] * (1 - tx) + Z[j + 1, i + 1] * tx) * ty)

    # Gravel traps: ground on the outside of chosen corners.
    gravel_side = np.zeros(n)
    for k in GRAVEL_CORNERS:
        r_, deg = pieces[k]
        side = -1.0 if deg > 0 else 1.0  # outside of the turn
        s0, s1 = starts[k] - 10.0, starts[k + 1] + 40.0
        on = ((dist - s0) % total) <= (s1 - s0)
        gravel_side[on] = side
    centres = np.column_stack([(X[:-1, :-1] + GRID / 2).ravel(), (Y[:-1, :-1] + GRID / 2).ravel()])
    cidx, _, coff = nearest(centres)
    outside = coff * gravel_side[cidx]
    is_gravel = (gravel_side[cidx] != 0) & (outside > KERB_OUT) & (outside < 28.0)
    verts3 = np.column_stack([V, Z.ravel()])
    grass_faces, gravel_faces = [], []
    for q, g in enumerate(is_gravel):
        j, i = divmod(q, nx - 1)
        a = j * nx + i
        tris = [(a, a + 1, a + nx + 1), (a, a + nx + 1, a + nx)]
        (gravel_faces if g else grass_faces).extend(tris)
    add_mesh("grass", verts3, grass_faces, "grass")
    add_mesh("gravel", verts3, gravel_faces, "gravel")

    # Low walls on the outside of the fast corners.
    walls = Builder()
    for k, offset, side in WALLS:
        s0, s1 = starts[k] - 20.0, starts[k + 1] + 20.0
        ids = [i for i in range(n) if ((dist[i] - s0) % total) <= (s1 - s0)]
        for i, j in zip(ids, ids[1:]):
            def wall_pt(m, extra, top):
                x = P[m, 0] + R[m, 0] * side * (offset + extra)
                y = P[m, 1] + R[m, 1] * side * (offset + extra)
                return (x, y, ground(x, y) + (0.9 if top else -0.6))
            walls.quad(wall_pt(i, 0, False), wall_pt(j, 0, False), wall_pt(j, 0, True), wall_pt(i, 0, True))
            walls.quad(wall_pt(i, 0, True), wall_pt(j, 0, True), wall_pt(j, 0.5, True), wall_pt(i, 0.5, True))
            walls.quad(wall_pt(j, 0.5, False), wall_pt(i, 0.5, False), wall_pt(i, 0.5, True), wall_pt(j, 0.5, True))
        for m in (ids[0], ids[-1]):
            walls.quad(wall_pt(m, 0, False), wall_pt(m, 0.5, False), wall_pt(m, 0.5, True), wall_pt(m, 0, True))
    walls.build("wall", "wall")

    # Grandstand on the right of the main straight, facing the start line.
    stand, roof = Builder(), Builder()
    gs = np.array([sx, sy]) + f * -20.0
    length = f * 80.0
    base = min(ground(*(gs + r * 18.0)), ground(*(gs + length + r * 28.0))) - 1.0
    for k in range(6):
        o = gs + r * (18.0 + 1.6 * k)
        stand.box(o, length, r * 1.6, base, sz + 0.8 * (k + 1))
    stand.box(gs + r * 27.6, length, r * 0.6, base, sz + 6.5)
    for t in (0.0, 0.33, 0.66, 1.0):
        stand.box(gs + length * t - f * 0.15 + r * 17.6, f * 0.3, r * 0.3, base, sz + 7.5)
    roof.box(gs - f * 1.0 + r * 17.0, length + f * 2.0, r * 11.5, sz + 7.5, sz + 7.8)
    stand.build("stand", "stand")
    roof.build("stand_roof", "roof")

    # Trees, kept back from the road and the stand.
    rng = np.random.default_rng(7)
    cand = np.column_stack([rng.uniform(lo[0] + 10, hi[0] - 10, 900), rng.uniform(lo[1] + 10, hi[1] - 10, 900)])
    _, cd, _ = nearest(cand)
    rel = cand - gs
    in_stand = (np.abs(rel @ r - 23) < 15) & ((rel @ f) > -10) & ((rel @ f) < 90)
    keep = cand[(cd > 28.0) & ~in_stand][:180]
    trunks, leaves = Builder(), Builder()
    for x, y in keep:
        z = ground(x, y)
        size = rng.uniform(0.8, 1.4)
        ring = [(math.cos(a), math.sin(a)) for a in np.linspace(0, 2 * math.pi, 7)[:-1] + rng.uniform(0, 1)]
        tr = 0.25 * size
        for a, b in zip(ring, ring[1:] + ring[:1]):
            trunks.quad((x + a[0] * tr, y + a[1] * tr, z - 0.3), (x + b[0] * tr, y + b[1] * tr, z - 0.3),
                        (x + b[0] * tr, y + b[1] * tr, z + 1.6 * size), (x + a[0] * tr, y + a[1] * tr, z + 1.6 * size))
        lr = 1.8 * size
        top = (x, y, z + 6.0 * size)
        bottom = z + 1.4 * size
        for a, b in zip(ring, ring[1:] + ring[:1]):
            leaves.poly([(x + a[0] * lr, y + a[1] * lr, bottom), (x + b[0] * lr, y + b[1] * lr, bottom), top])
        leaves.poly([(x + a[0] * lr, y + a[1] * lr, bottom) for a in ring[::-1]])
    trunks.build("tree_trunks", "trunk")
    leaves.build("deco_leaves", "leaves")

    # Start line, checkpoints, spawn and centreline.
    for g in range(CHECKPOINTS + 1):
        x, y, z, h = at(START + g * total / (CHECKPOINTS + 1))
        add_empty("Gate%d" % g, x, y, z, h)
    x, y, z, h = at(START - SPAWN_BACK)
    add_empty("Spawn", x, y, z + 0.8, h)
    centre = np.column_stack([P, H])
    add_mesh("Centreline", centre, [], None, [(i, (i + 1) % n) for i in range(n)])

    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    with open(os.path.join(os.path.dirname(BLEND_PATH), ".gdignore"), "w"):
        pass  # Keeps Godot from importing the .blend itself.
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    export_track.export(GLB_PATH)
    print("saved", BLEND_PATH)
    print("exported", GLB_PATH)


main()
