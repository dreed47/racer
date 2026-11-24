#!/usr/bin/env python3
"""Build the Clarion loop track data from OpenStreetMap roads and USGS 3DEP heights.

The loop: from US 322 and 5th Avenue (PA 68) in Clarion, PA, south on PA 68, west on I-80,
off at the first exit, north on PA 66, then back east on US 322 to the start.

Writes track/clarion/clarion.json (road, bridges, buildings, trees, terrain layout) and
track/clarion/terrain.bin (terrain heights as little-endian float32, row by row from north
to south). The game reads only these two files, so it needs no network.

Downloads go into a cache folder and are reused on the next run:
    python3 tools/clarion/build_track.py CACHE_DIR
Needs numpy and Pillow.

Map data (c) OpenStreetMap contributors, ODbL. Heights: USGS 3D Elevation Program, public domain.
"""

import heapq
import json
import math
import os
import sys
import urllib.parse
import urllib.request

import numpy as np
from PIL import Image

USER_AGENT = "racer-hobby-game/0.1"
OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
DEM_URL = "https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/exportImage"

# Area round the loop, as south, west, north, east.
ROAD_BOX = (41.14, -79.52, 41.27, -79.33)
AREA_BOX = (41.180, -79.444, 41.248, -79.378)
DEM_SIZE = (660, 680)  # Pixels, west to east and north to south: about 0.0001 degrees each.

STEP = 2.0  # Metres between centreline points.
ROAD_HALF_WIDTH = 6.0
MIN_RADIUS = 14.0  # Tightest corner the road may have, in metres, so the inside edge never folds.
HEIGHT_SMOOTH = 40.0  # Metres over which road heights are averaged to remove bumps.
BRIDGE_MARGIN = 8.0  # How far past each bridge end the deck height comes from.
TERRAIN_CELL = 10.0  # Metres between terrain heights.
CARVE_FLAT = 21.0  # Terrain this close to the centreline sits just under the road.
CARVE_BLEND = 48.0  # Terrain blends back to the real ground by this distance.
CARVE_DROP = 0.3  # How far the flat terrain sits under the road.
BRIDGE_CLEARANCE = 2.0  # Terrain under a bridge stays at least this far under the deck.
BUILDING_RANGE = 160.0  # Keep buildings within this distance of the road.
ROAD_CLEAR = 9.0  # No building or tree comes closer than this to the centreline.
TREE_COUNT = 3500
TREE_NEAR = 22.0
TREE_FAR = 260.0
SEED = 322


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: build_track.py CACHE_DIR")
    cache = sys.argv[1]
    os.makedirs(cache, exist_ok=True)
    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    out_dir = os.path.join(repo, "track", "clarion")
    os.makedirs(out_dir, exist_ok=True)

    roads = cached_overpass(cache, "roads.json",
            '[out:json][timeout:90];way["highway"~"^(motorway|trunk|primary|secondary|tertiary)(_link)?$"]'
            '(%s,%s,%s,%s);out geom tags;' % ROAD_BOX)
    buildings = cached_overpass(cache, "buildings.json",
            '[out:json][timeout:90];way["building"](%s,%s,%s,%s);out geom tags;' % AREA_BOX)
    dem = Dem(cached_dem(cache))

    lat_lon, bridge_flags = route(roads)
    origin = lat_lon[0]
    proj = Projection(origin)
    xz = np.array([proj.to_local(lat, lon) for lat, lon in lat_lon])
    print("route %.2f km, %d OSM points" % (polyline_length(xz, True) / 1000.0, len(xz)))

    points, bridge = resample(xz, np.array(bridge_flags), STEP)
    points = smooth_corners(points)
    points, bridge = resample(points, bridge, STEP)
    length = polyline_length(points, True)
    print("centreline %.2f km, %d points, tightest corner %.1f m" % (
            length / 1000.0, len(points), min_radius(points)))

    heights = np.array([dem.height(*proj.to_lat_lon(x, z)) for x, z in points])
    heights = level_bridges(heights, bridge)
    heights = smooth_loop(heights, int(HEIGHT_SMOOTH / STEP))
    grade = np.abs(np.diff(np.append(heights, heights[0]))) / STEP
    print("road heights %.1f to %.1f m, steepest grade %.1f %%" % (heights.min(), heights.max(),
            grade.max() * 100.0))
    terrain, layout = build_terrain(dem, proj, points, heights, bridge)
    # Keep numbers small, with the lowest ground a little above y = 0 (falling below -20 resets).
    base = float(math.floor(terrain.min() / 10.0) * 10.0 - 10.0)
    road_tree = Nearest(points)
    blocks = place_buildings(buildings, proj, road_tree, layout, terrain)
    trees = place_trees(road_tree, layout, terrain, blocks)
    print("terrain %d x %d, %d buildings, %d trees" % (layout["width"], layout["depth"], len(blocks), len(trees)))

    (terrain - base).astype("<f4").tofile(os.path.join(out_dir, "terrain.bin"))
    layout["file"] = "terrain.bin"
    data = {
        "name": "Clarion loop",
        "origin": [round(origin[0], 7), round(origin[1], 7)],
        "base_height": base,
        "step": STEP,
        "road_half_width": ROAD_HALF_WIDTH,
        "points": [round(float(v), 2) for p, h in zip(points, heights) for v in (p[0], h - base, p[1])],
        "bridges": bridge_ranges(bridge),
        "terrain": layout,
        "buildings": [[round(float(v), 2) for v in (b[0], b[1], b[2], b[3], b[4], b[5] - base, b[6])]
                for b in blocks],
        "trees": [[round(float(v), 2) for v in (t[0], t[1] - base, t[2], t[3])] for t in trees],
        "credits": "Map data (c) OpenStreetMap contributors, ODbL. Heights: USGS 3DEP.",
    }
    with open(os.path.join(out_dir, "clarion.json"), "w") as f:
        json.dump(data, f, separators=(",", ":"))
    print("wrote", out_dir)


# Downloads ------------------------------------------------------------------------------------


def cached_overpass(cache: str, name: str, query: str) -> dict:
    path = os.path.join(cache, name)
    if not os.path.exists(path):
        body = urllib.parse.urlencode({"data": query}).encode()
        last_error = None
        for url in OVERPASS:
            try:
                request = urllib.request.Request(url, body, {"User-Agent": USER_AGENT})
                with urllib.request.urlopen(request, timeout=120) as response:
                    payload = response.read()
                json.loads(payload)
                with open(path, "wb") as f:
                    f.write(payload)
                break
            except Exception as error:  # Try the next server.
                last_error = error
        else:
            sys.exit("could not download %s: %s" % (name, last_error))
    with open(path) as f:
        return json.load(f)


def cached_dem(cache: str) -> str:
    path = os.path.join(cache, "dem.tif")
    if not os.path.exists(path):
        s, w, n, e = AREA_BOX
        query = urllib.parse.urlencode({
            "bbox": "%s,%s,%s,%s" % (w, s, e, n), "bboxSR": 4326, "imageSR": 4326,
            "size": "%d,%d" % DEM_SIZE, "format": "tiff", "pixelType": "F32", "noData": -9999,
            "interpolation": "RSP_BilinearInterpolation", "compression": "None", "f": "image"})
        request = urllib.request.Request(DEM_URL + "?" + query, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=120) as response:
            payload = response.read()
        with open(path, "wb") as f:
            f.write(payload)
    return path


class Dem:
    """Ground heights on a lat/lon grid, read from the 3DEP TIFF."""

    def __init__(self, path: str) -> None:
        self.grid = np.array(Image.open(path), dtype=np.float64)
        if self.grid.shape != (DEM_SIZE[1], DEM_SIZE[0]) or (self.grid < -1000).any():
            sys.exit("height map has the wrong size or holes")
        s, w, n, e = AREA_BOX
        self.west, self.north = w, n
        self.dlon = (e - w) / DEM_SIZE[0]
        self.dlat = (n - s) / DEM_SIZE[1]

    def height(self, lat: float, lon: float) -> float:
        return float(self.heights(np.array([lat]), np.array([lon]))[0])

    def heights(self, lat: np.ndarray, lon: np.ndarray) -> np.ndarray:
        col = (lon - self.west) / self.dlon - 0.5
        row = (self.north - lat) / self.dlat - 0.5
        rows, cols = self.grid.shape
        col = np.clip(col, 0, cols - 1.001)
        row = np.clip(row, 0, rows - 1.001)
        c0 = col.astype(int)
        r0 = row.astype(int)
        fc = col - c0
        fr = row - r0
        g = self.grid
        top = g[r0, c0] * (1 - fc) + g[r0, c0 + 1] * fc
        bottom = g[r0 + 1, c0] * (1 - fc) + g[r0 + 1, c0 + 1] * fc
        return top * (1 - fr) + bottom * fr


class Projection:
    """Flat local metres round the start: +x east, -z north, as Godot sees it."""

    def __init__(self, origin) -> None:
        self.lat0, self.lon0 = origin
        self.east = 111320.0 * math.cos(math.radians(self.lat0))
        self.north = 110574.0

    def to_local(self, lat, lon):
        return ((lon - self.lon0) * self.east, -(lat - self.lat0) * self.north)

    def to_lat_lon(self, x, z):
        return (self.lat0 - z / self.north, self.lon0 + x / self.east)


# Route ----------------------------------------------------------------------------------------


def route(roads: dict):
    """The loop as (lat, lon) points from the start, with a bridge flag for each segment."""
    ways = roads["elements"]
    for w in ways:
        w["nodes"] = [(round(g["lat"], 7), round(g["lon"], 7)) for g in w["geometry"]]

    def refs(w):
        return w["tags"].get("ref") or ""

    def graph(allow):
        g = {}
        for w in ways:
            if not allow(w):
                continue
            one_way = w["tags"].get("oneway") in ("yes", "1") or w["tags"].get("highway") == "motorway"
            on_bridge = w["tags"].get("bridge") == "yes"
            for a, b in zip(w["nodes"], w["nodes"][1:]):
                g.setdefault(a, []).append((b, on_bridge))
                if not one_way:
                    g.setdefault(b, []).append((a, on_bridge))
        return g

    def nodes_of(pred):
        return {n for w in ways if pred(w) for n in w["nodes"]}

    n322 = nodes_of(lambda w: "US 322" in refs(w))
    n68 = nodes_of(lambda w: "PA 68" in refs(w))
    n66 = nodes_of(lambda w: "PA 66" in refs(w) and w["tags"]["highway"] in ("primary", "secondary"))
    starts = n322 & n68
    junctions = n322 & n66
    if len(starts) != 1 or not junctions:
        sys.exit("could not find the loop's junctions in the map data")
    start = next(iter(starts))
    leg1 = shortest(graph(lambda w: "US 322" not in refs(w)), start, junctions)
    leg2 = shortest(graph(lambda w: "US 322" in refs(w)), leg1[-1][0], {start})
    path = leg1 + leg2[1:]
    points = [n for n, _ in path[:-1]]  # The last point is the start again.
    flags = [on_bridge for _, on_bridge in path[1:]]  # Segment i runs from point i to i + 1.
    return points, flags


def shortest(g: dict, source, targets: set):
    def km(a, b):
        x = (b[1] - a[1]) * math.cos(math.radians(a[0])) * 111.32
        y = (b[0] - a[0]) * 110.57
        return math.hypot(x, y)

    best = {source: 0.0}
    previous = {}
    queue = [(0.0, source)]
    while queue:
        cost, node = heapq.heappop(queue)
        if node in targets:
            path = [(node, previous[node][1] if node in previous else False)]
            while node in previous:
                node = previous[node][0]
                path.append((node, previous[node][1] if node in previous else False))
            return path[::-1]
        if cost > best.get(node, 1e18):
            continue
        for nxt, on_bridge in g.get(node, []):
            c = cost + km(node, nxt)
            if c < best.get(nxt, 1e18):
                best[nxt] = c
                previous[nxt] = (node, on_bridge)
                heapq.heappush(queue, (c, nxt))
    sys.exit("no route found")


# Centreline -----------------------------------------------------------------------------------


def polyline_length(p: np.ndarray, closed: bool) -> float:
    q = np.vstack([p, p[:1]]) if closed else p
    return float(np.linalg.norm(np.diff(q, axis=0), axis=1).sum())


def resample(p: np.ndarray, flags: np.ndarray, step: float):
    """Even points round the closed loop. A new point is on a bridge if its segment was."""
    q = np.vstack([p, p[:1]])
    seg = np.linalg.norm(np.diff(q, axis=0), axis=1)
    along = np.concatenate([[0.0], np.cumsum(seg)])
    total = along[-1]
    count = int(round(total / step))
    d = np.arange(count) * (total / count)
    i = np.clip(np.searchsorted(along, d, side="right") - 1, 0, len(seg) - 1)
    t = (d - along[i]) / np.maximum(seg[i], 1e-9)
    out = q[i] + (q[i + 1] - q[i]) * t[:, None]
    return out, flags[i]


def turn_radius(p: np.ndarray, span: int) -> np.ndarray:
    a = np.roll(p, span, axis=0)
    c = np.roll(p, -span, axis=0)
    ab = np.linalg.norm(p - a, axis=1)
    bc = np.linalg.norm(c - p, axis=1)
    ca = np.linalg.norm(a - c, axis=1)
    cross = np.abs((p - a)[:, 0] * (c - a)[:, 1] - (p - a)[:, 1] * (c - a)[:, 0])
    return ab * bc * ca / np.maximum(2.0 * cross, 1e-9)


def min_radius(p: np.ndarray) -> float:
    return float(min(turn_radius(p, s).min() for s in (2, 4, 8)))


def smooth_corners(p: np.ndarray) -> np.ndarray:
    """Light smoothing everywhere, then round off any corner tighter than MIN_RADIUS."""
    for _ in range(3):
        p = (np.roll(p, 1, axis=0) + 2 * p + np.roll(p, -1, axis=0)) / 4.0
    for _ in range(4000):
        r = np.minimum(turn_radius(p, 2), np.minimum(turn_radius(p, 4), turn_radius(p, 8)))
        tight = r < MIN_RADIUS
        if not tight.any():
            break
        # Spread the fix a few points either side, so the corner rounds instead of kinking.
        near = tight.copy()
        for s in range(1, 6):
            near |= np.roll(tight, s) | np.roll(tight, -s)
        average = (np.roll(p, 1, axis=0) + np.roll(p, -1, axis=0)) / 2.0
        p = np.where(near[:, None], p + (average - p) * 0.5, p)
    return p


def level_bridges(h: np.ndarray, bridge: np.ndarray) -> np.ndarray:
    """Real bridge decks run straight between their ends; the height map shows the valley."""
    h = h.copy()
    margin = int(BRIDGE_MARGIN / STEP)
    n = len(h)
    for first, last in bridge_ranges(bridge):
        a = (first - margin) % n
        b = (last + margin) % n
        span = (b - a) % n
        for k in range(1, span):
            h[(a + k) % n] = h[a] + (h[b] - h[a]) * k / span
    return h


def bridge_ranges(bridge: np.ndarray):
    out = []
    n = len(bridge)
    start = None
    for i in range(n + 1):
        on = bool(bridge[i % n]) and i < n
        if on and start is None:
            start = i
        elif not on and start is not None:
            out.append([start, i - 1])
            start = None
    return out


def smooth_loop(h: np.ndarray, window: int) -> np.ndarray:
    kernel = np.ones(window) / window
    for _ in range(3):
        padded = np.concatenate([h[-window:], h, h[:window]])
        h = np.convolve(padded, kernel, mode="same")[window:-window]
    return h


class Nearest:
    """Nearest centreline point, through a coarse bucket grid."""

    def __init__(self, points: np.ndarray, bucket: float = 50.0) -> None:
        self.points = points
        self.bucket = bucket
        self.cells = {}
        for i, (x, z) in enumerate(points):
            self.cells.setdefault((int(x // bucket), int(z // bucket)), []).append(i)

    def query(self, x: float, z: float, reach: float):
        """Index and distance of the nearest point, or (-1, inf) if none is within reach."""
        best, best_d = -1, float("inf")
        cx, cz = int(x // self.bucket), int(z // self.bucket)
        r = int(math.ceil(reach / self.bucket))
        for i in range(cx - r, cx + r + 1):
            for k in range(cz - r, cz + r + 1):
                for j in self.cells.get((i, k), ()):
                    d = math.hypot(self.points[j][0] - x, self.points[j][1] - z)
                    if d < best_d:
                        best, best_d = j, d
        return (best, best_d) if best_d <= reach else (-1, float("inf"))


# Terrain and scenery --------------------------------------------------------------------------


def build_terrain(dem: Dem, proj: Projection, points: np.ndarray, heights: np.ndarray, bridge: np.ndarray):
    """Ground heights on a square grid in local metres, carved flat under the road."""
    s, w, n, e = AREA_BOX
    corners = [proj.to_local(lat, lon) for lat in (s, n) for lon in (w, e)]
    x0 = math.ceil(max(c[0] for c in corners if c[0] < 0) / TERRAIN_CELL) * TERRAIN_CELL
    x1 = math.floor(min(c[0] for c in corners if c[0] > 0) / TERRAIN_CELL) * TERRAIN_CELL
    z0 = math.ceil(max(c[1] for c in corners if c[1] < 0) / TERRAIN_CELL) * TERRAIN_CELL
    z1 = math.floor(min(c[1] for c in corners if c[1] > 0) / TERRAIN_CELL) * TERRAIN_CELL
    xs = np.arange(x0, x1 + 0.1, TERRAIN_CELL)
    zs = np.arange(z0, z1 + 0.1, TERRAIN_CELL)
    gx, gz = np.meshgrid(xs, zs)
    lat, lon = proj.to_lat_lon(gx, gz)
    ground = dem.heights(lat, lon)

    # Nearest road distance and height for every cell within the blend range.
    near = np.full(ground.shape, np.inf)
    road_h = np.zeros(ground.shape)
    on_bridge = np.zeros(ground.shape, dtype=bool)
    reach = int(math.ceil(CARVE_BLEND / TERRAIN_CELL)) + 1
    for (px, pz), ph, pb in zip(points, heights, bridge):
        ci = int(round((px - x0) / TERRAIN_CELL))
        ri = int(round((pz - z0) / TERRAIN_CELL))
        r_lo, r_hi = max(ri - reach, 0), min(ri + reach + 1, len(zs))
        c_lo, c_hi = max(ci - reach, 0), min(ci + reach + 1, len(xs))
        if r_lo >= r_hi or c_lo >= c_hi:
            continue
        d = np.hypot(gx[r_lo:r_hi, c_lo:c_hi] - px, gz[r_lo:r_hi, c_lo:c_hi] - pz)
        block = near[r_lo:r_hi, c_lo:c_hi]
        closer = d < block
        block[closer] = d[closer]
        road_h[r_lo:r_hi, c_lo:c_hi][closer] = ph
        on_bridge[r_lo:r_hi, c_lo:c_hi][closer] = pb

    t = np.clip((near - CARVE_FLAT) / (CARVE_BLEND - CARVE_FLAT), 0.0, 1.0)
    weight = 1.0 - t * t * (3.0 - 2.0 * t)  # Smooth step from 1 at the road to 0 far away.
    flat = road_h - CARVE_DROP
    carved = ground * (1.0 - weight) + flat * weight
    # Under a bridge the valley stays, but never closer to the deck than the clearance.
    under = on_bridge & (near < CARVE_BLEND)
    carved[under] = np.minimum(ground[under], road_h[under] - BRIDGE_CLEARANCE)
    layout = {"cell": TERRAIN_CELL, "x0": float(x0), "z0": float(z0), "width": len(xs), "depth": len(zs)}
    return carved, layout


def terrain_height(terrain: np.ndarray, layout: dict, x: float, z: float) -> float:
    c = (x - layout["x0"]) / layout["cell"]
    r = (z - layout["z0"]) / layout["cell"]
    c = min(max(c, 0.0), layout["width"] - 1.001)
    r = min(max(r, 0.0), layout["depth"] - 1.001)
    c0, r0 = int(c), int(r)
    fc, fr = c - c0, r - r0
    top = terrain[r0, c0] * (1 - fc) + terrain[r0, c0 + 1] * fc
    bottom = terrain[r0 + 1, c0] * (1 - fc) + terrain[r0 + 1, c0 + 1] * fc
    return float(top * (1 - fr) + bottom * fr)


def inside_terrain(layout: dict, x: float, z: float, margin: float) -> bool:
    x1 = layout["x0"] + (layout["width"] - 1) * layout["cell"]
    z1 = layout["z0"] + (layout["depth"] - 1) * layout["cell"]
    return layout["x0"] + margin < x < x1 - margin and layout["z0"] + margin < z < z1 - margin


def place_buildings(buildings: dict, proj: Projection, road: Nearest, layout: dict, terrain: np.ndarray):
    """Each footprint as its smallest enclosing box: centre x, z, yaw, length, width, base, height."""
    blocks = []
    for w in buildings["elements"]:
        if w.get("type") != "way" or len(w.get("geometry", ())) < 4:
            continue
        pts = np.array([proj.to_local(g["lat"], g["lon"]) for g in w["geometry"]])
        cx, cz, yaw, length, width = min_area_box(pts)
        if length < 3.0 or width < 3.0 or length > 150.0:
            continue
        if not inside_terrain(layout, cx, cz, 20.0):
            continue
        _, d = road.query(cx, cz, BUILDING_RANGE)
        if d - math.hypot(length, width) / 2.0 < ROAD_CLEAR:
            continue  # Too close to the road, or (inf) too far from it.
        tags = w["tags"]
        height = building_height(tags)
        # Sit on the lowest corner so no corner floats on a slope.
        c, s = math.cos(yaw), math.sin(yaw)
        base = min(terrain_height(terrain, layout, cx + c * u * length / 2 - s * v * width / 2,
                cz + s * u * length / 2 + c * v * width / 2) for u in (-1, 1) for v in (-1, 1))
        blocks.append((cx, cz, yaw, length, width, base - 0.5, height + 0.5))
    return blocks


def building_height(tags: dict) -> float:
    try:
        if "height" in tags:
            return max(3.0, float(tags["height"].split()[0]))
        if "building:levels" in tags:
            return 3.2 * max(1.0, float(tags["building:levels"]))
    except ValueError:
        pass
    kind = tags.get("building")
    return {"university": 14.0, "apartments": 12.0, "church": 12.0, "retail": 6.0, "warehouse": 8.0,
            "roof": 4.0, "garage": 3.0, "shed": 3.0}.get(kind, 7.0)


def min_area_box(pts: np.ndarray):
    hull = convex_hull(pts)
    best = None
    for i in range(len(hull)):
        edge = hull[(i + 1) % len(hull)] - hull[i]
        yaw = math.atan2(edge[1], edge[0])
        c, s = math.cos(yaw), math.sin(yaw)
        u = hull[:, 0] * c + hull[:, 1] * s
        v = -hull[:, 0] * s + hull[:, 1] * c
        area = (u.max() - u.min()) * (v.max() - v.min())
        if best is None or area < best[0]:
            mu, mv = (u.max() + u.min()) / 2, (v.max() + v.min()) / 2
            best = (area, mu * c - mv * s, mu * s + mv * c, yaw, u.max() - u.min(), v.max() - v.min())
    return best[1:]


def convex_hull(pts: np.ndarray) -> np.ndarray:
    p = sorted(set(map(tuple, np.round(pts, 3))))
    if len(p) < 3:
        return np.array(p)

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for q in p:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], q) <= 0:
            lower.pop()
        lower.append(q)
    for q in reversed(p):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], q) <= 0:
            upper.pop()
        upper.append(q)
    return np.array(lower[:-1] + upper[:-1])


def place_trees(road: Nearest, layout: dict, terrain: np.ndarray, blocks):
    """Random trees in a band either side of the road, clear of the road and the buildings."""
    rng = np.random.default_rng(SEED)
    pts = road.points
    building_tree = Nearest(np.array([(b[0], b[1]) for b in blocks]) if blocks else np.zeros((0, 2)))
    trees = []
    tries = 0
    while len(trees) < TREE_COUNT and tries < TREE_COUNT * 20:
        tries += 1
        i = rng.integers(len(pts))
        side = rng.choice((-1.0, 1.0))
        offset = TREE_NEAR + (TREE_FAR - TREE_NEAR) * rng.random() ** 1.5
        nxt = pts[(i + 1) % len(pts)] - pts[i]
        right = np.array([-nxt[1], nxt[0]]) / max(np.linalg.norm(nxt), 1e-9)
        x, z = pts[i] + right * side * offset + rng.normal(0, 6, 2)
        if not inside_terrain(layout, x, z, 10.0):
            continue
        if road.query(x, z, TREE_NEAR)[0] != -1:
            continue
        if blocks and building_tree.query(x, z, 25.0)[0] != -1:
            continue
        scale = 0.7 + 0.6 * rng.random()
        trees.append((x, terrain_height(terrain, layout, x, z), z, scale))
    return trees


if __name__ == "__main__":
    main()
