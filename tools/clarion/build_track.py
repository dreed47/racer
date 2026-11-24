#!/usr/bin/env python3
"""Build the Clarion loop track data from OpenStreetMap roads and USGS 3DEP heights.

The loop: from US 322 and 5th Avenue (PA 68) in Clarion, PA, south on PA 68, west on I-80,
off at the first exit, north on PA 66, then back east on US 322 to the start.

Every public street that meets the loop gets a short closed-off stub (side_streets in the
data), ending at a barrier, so the junctions look real but the route can't be left.

Writes track/clarion/clarion.json (road, side streets, bridges, buildings, trees, terrain layout) and
track/clarion/terrain.bin (terrain heights as little-endian float32, row by row from north
to south). The game reads only these two files, so it needs no network.

Downloads go into a cache folder and are reused on the next run:
    python3 tools/clarion/build_track.py CACHE_DIR
Needs numpy and Pillow.

Buildings come from tools/clarion/fetch_buildings.py when its files are in the cache (true
outlines, lidar heights and roofs, business signs); without them, OSM outlines and guessed
heights are used.

Map data (c) OpenStreetMap contributors, ODbL. Building outlines: Overture Maps Foundation
(ODbL and CDLA Permissive 2.0, including Microsoft building footprints). Heights and roofs:
USGS 3D Elevation Program ground and lidar, public domain.
"""

import heapq
import json
import math
import os
import re
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
BUILDING_RANGE = 250.0  # Keep buildings within this distance of the road.
ROAD_CLEAR = 9.0  # No building or tree comes closer than this to the centreline.
STUB_BUILDING_CLEAR = 6.5  # Buildings may come this close to a side street's centreline...
MOUTH_CLEAR = 16.0  # ...except this close to the loop, where its rounded corners are.
BUILDING_SINK = 0.5  # Walls start this far under the lowest ground at their corners.
BOX_FILL = 0.85  # A sloped roof needs an outline that fills this much of its box.
HOUSE_PITCH = 0.5  # Guessed roof slope (rise over run) for a house the lidar saw as flat.
TOWN_CENTRE = (41.2150, -79.3855)  # The courthouse on Main Street.
TOWN_RADIUS = 380.0  # Brick shop fronts within this distance of it.
SIGN_WALL_HEIGHT = 3.6  # Business sign centre above the ground.
SIGN_POLE_FROM = 22.0  # A sign wall further than this from the road gets a pole sign too.
STREET_SAMPLE = 2.0  # Spacing of the points that stand for a street off the loop.
TREE_COUNT = 3500
TREE_NEAR = 22.0
TREE_FAR = 260.0
TREE_BUILDING_CLEAR = 5.0  # Tree trunks at least this far from any wall.
SEED = 322
# Side streets: public roads that meet the loop, cut short and closed with a barrier.
STREET_CLASSES = "motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street"
STUB_HALF_WIDTH = 4.0
STUB_BARRIER = 36.0  # Barrier distance from the loop's centreline, along the street: 30 m past the edge.
STUB_MAX = 150.0  # A ramp leaving at a shallow angle runs on until its barrier is clear of the loop.
STUB_MAX_MOTORWAY = 450.0  # A motorway merging alongside the loop runs side by side much longer.
STUB_FORK = 30.0  # Two streets leaving from the same junction may overlap this far along.
STUB_FLARE = 6.0  # Radius of the rounded corner where a street meets the loop's edge.
SIGN_OFFSET = 1.5  # Name sign post this far outside the street's edge.
SIGN_CHAR_WIDTH = 0.3  # Name sign plate length per letter; matches RoadTrack.SIGN_CHAR_WIDTH.
SIGN_PLATE_PAD = 0.6  # Plate length past the words; matches RoadTrack.SIGN_PLATE_PAD.
SIGN_PLATE_HEIGHT = 0.7  # Name sign plate height; matches RoadTrack.SIGN_PLATE_HEIGHT.
CORNER_MAX = 12.0  # A rounded corner reaches at most this far along each edge.
CORNER_STEPS = 12
CORNER_DROP = 0.04  # Corner patch sits this far under the roads it joins.
STUB_CLEAR = 13.0  # Barrier centre at least this far from the loop's centreline: 3 m past its edge.
STUB_PAST = 2.0  # Street left behind the barrier, so the road doesn't stop right at it.
STUB_SHIFT = 20.0  # Over this distance the street bends from its map junction to the smoothed loop.
STUB_GRADE = 0.10  # Steepest slope a stub may have.
STUB_FLAT = 10.0  # Terrain this close to a stub's centreline sits just under it.
STUB_BLEND = 24.0
STUB_KEEP = ROAD_HALF_WIDTH + 12.0  # Stub carving never raises ground this close to the loop.


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
    streets = cached_overpass(cache, "streets.json",
            '[out:json][timeout:90];way["highway"~"^(%s)(_link)?$"](%s,%s,%s,%s);out geom tags;'
            % ((STREET_CLASSES,) + AREA_BOX))
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
    stubs = side_streets(streets, lat_lon, proj, points, heights, bridge, terrain, layout)
    terrain = carve_stubs(terrain, layout, stubs, Nearest(points))
    print("%d side streets closed off" % len(stubs))
    # Keep numbers small, with the lowest ground a little above y = 0 (falling below -20 resets).
    base = float(math.floor(terrain.min() / 10.0) * 10.0 - 10.0)
    all_roads = [points] + [s["centre"] for s in stubs]
    road_tree = Nearest(np.vstack(all_roads))
    stub_tree = Nearest(np.vstack([s["centre"] for s in stubs])) if stubs else None
    footprints = load_footprints(cache, buildings, proj)
    blocks = place_buildings(footprints, proj, Nearest(points), stub_tree, layout, terrain)
    signs = place_businesses(cache, blocks, proj, Nearest(points), streets, heights, terrain, layout)
    trees = place_trees(Nearest(points), road_tree, layout, terrain, blocks)
    print("terrain %d x %d, %d buildings (%d sloped roofs), %d business signs, %d trees" % (
            layout["width"], layout["depth"], len(blocks), sum(1 for b in blocks if b["roof"] != "flat"),
            len(signs), len(trees)))

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
        "side_streets": [stub_data(st, base) for st in stubs],
        "mouth_cuts": mouth_cuts(stubs, points, bridge),
        "terrain": layout,
        "buildings": [building_data(b, base) for b in blocks],
        "businesses": [business_data(b, base) for b in signs],
        "trees": [[round(float(v), 2) for v in (t[0], t[1] - base, t[2], t[3])] for t in trees],
        "credits": "Map data (c) OpenStreetMap contributors, ODbL. Buildings: Overture Maps Foundation, "
                "ODbL and CDLA Permissive 2.0. Heights and roofs: USGS 3DEP.",
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


# Side streets ---------------------------------------------------------------------------------


def side_streets(streets: dict, route_nodes, proj: Projection, points: np.ndarray, heights: np.ndarray,
        bridge: np.ndarray, terrain: np.ndarray, layout: dict):
    """A short stub for each street leaving the loop: centreline, heights, edges and barrier."""
    ways = streets["elements"]
    for w in ways:
        w["nodes"] = [(round(g["lat"], 7), round(g["lon"], 7)) for g in w["geometry"]]
    on_route = set(route_nodes)
    route_edges = {frozenset(e) for e in zip(route_nodes, route_nodes[1:] + route_nodes[:1])}
    at_node = {}
    for wi, w in enumerate(ways):
        for k, n in enumerate(w["nodes"]):
            at_node.setdefault(n, []).append((wi, k))
    loop = Nearest(points)
    reach = STUB_MAX_MOTORWAY + 15.0  # Map metres to follow, a little more than needed.

    def walk(node, wi, k, step):
        """Map points from a junction along one street, onto the next street at a dead end."""
        out = [node]
        followed = [wi]
        length = 0.0
        name = ways[wi]["tags"].get("name")
        while length < reach:
            k2 = k + step
            nodes = ways[wi]["nodes"]
            if not 0 <= k2 < len(nodes):
                # The way ends: carry on along another one from this node, the same street first.
                options = [(wj, kj, s) for wj, kj in at_node.get(nodes[k], ()) if wj != wi
                        for s in (1, -1) if 0 <= kj + s < len(ways[wj]["nodes"])
                        and frozenset((nodes[k], ways[wj]["nodes"][kj + s])) not in route_edges]
                if not options:
                    break
                options.sort(key=lambda o: ways[o[0]]["tags"].get("name") != name)
                wi, k, step = options[0]
                followed.append(wi)
                continue
            a, b = proj.to_local(*nodes[k]), proj.to_local(*nodes[k2])
            length += math.hypot(b[0] - a[0], b[1] - a[1])
            out.append(nodes[k2])
            if nodes[k2] in on_route:
                break  # Back on the loop: a short link between two parts of it.
            k = k2
        return out, followed

    stubs = []
    taken = set()
    for node in route_nodes:
        for wi, k in at_node.get(node, ()):
            for step in (1, -1):
                k2 = k + step
                nodes = ways[wi]["nodes"]
                if not 0 <= k2 < len(nodes) or frozenset((node, nodes[k2])) in route_edges:
                    continue
                if (node, nodes[k2]) in taken:
                    continue
                taken.add((node, nodes[k2]))
                limit = STUB_MAX_MOTORWAY if ways[wi]["tags"]["highway"] == "motorway" else STUB_MAX
                path, followed = walk(node, wi, k, step)
                stub = make_stub(path, proj, points, heights, bridge, loop, terrain, layout, stubs, limit)
                if stub:
                    stub["name"] = ways[wi]["tags"].get("name") or ways[wi]["tags"].get("ref") or ""
                    stub["kind"] = ways[wi]["tags"]["highway"]
                    stub["sign"] = sign_text([ways[f]["tags"] for f in followed])
                    stub["sign_post"] = sign_spot(*stub.pop("sign_args"), stub["sign"])
                    stubs.append(stub)
    return stubs


def sign_text(tags: list) -> str:
    """Words for the street's name sign, from the first way along it that has a name or number.

    A ramp is signed by the motorway it leads to, for example "I-80 ramp"."""
    def ref(value):
        first = value.split(";")[0].strip()
        return first.replace("I ", "I-", 1) if first.startswith("I ") else first

    if tags[0]["highway"].endswith("_link"):
        motorway = next((ref(t["ref"]) for t in tags if t["highway"] == "motorway" and t.get("ref")), "")
        return motorway + " ramp" if motorway else "Ramp"
    for t in tags:
        text = ref(t["ref"]) if t["highway"] == "motorway" and t.get("ref") else \
                t.get("name") or ref(t.get("ref") or "")
        if text:
            return text
    return ""


def make_stub(path, proj, points, heights, bridge, loop: Nearest, terrain, layout, others, limit=STUB_MAX):
    """One stub along the map points from its junction, or None if it doesn't fit."""
    xz = np.array([proj.to_local(lat, lon) for lat, lon in path])
    start, gap = loop.query(xz[0][0], xz[0][1], 15.0)
    if start == -1:
        return None  # The smoothed loop moved too far from this junction.
    n = len(points)
    if any(bridge[(start + k) % n] for k in range(-25, 26)):
        return None  # No streets join a bridge.
    seg = np.linalg.norm(np.diff(xz, axis=0), axis=1)
    along = np.concatenate([[0.0], np.cumsum(seg)])
    # Bend the street from its map junction onto the smoothed loop centreline.
    shift = points[start] - xz[0]
    xz = xz + shift * np.clip(1.0 - along / STUB_SHIFT, 0.0, 1.0)[:, None]
    seg = np.linalg.norm(np.diff(xz, axis=0), axis=1)
    along = np.concatenate([[0.0], np.cumsum(seg)])
    total = min(along[-1], limit + STUB_PAST)
    d = np.arange(0.0, total + 0.01, STEP)
    centre = np.column_stack([np.interp(d, along, xz[:, 0]), np.interp(d, along, xz[:, 1])])

    # The barrier goes at the first point far enough along and clear of the loop, so it is
    # never on the loop or its edge. The street ends a little past it, also clear of the loop.
    b = next((i for i, (x, z) in enumerate(centre)
            if d[i] >= STUB_BARRIER and loop.query(x, z, STUB_CLEAR)[0] == -1), None)
    if b is None:
        return None  # The street ends (or the map ends) first.
    end = b + int(round(STUB_PAST / STEP))
    if end >= len(centre):
        return None
    centre, d = centre[:end + 1], d[:end + 1]
    if any(loop.query(x, z, ROAD_HALF_WIDTH + STUB_HALF_WIDTH + 1.0)[0] != -1 for x, z in centre[b:]):
        return None
    # Clear of the stubs already made, past the first few metres (further for a fork from the same junction).
    for o in others:
        near = Nearest(o["centre"])
        fork = o["start"] == start
        if any(near.query(x, z, 2.0 * STUB_HALF_WIDTH)[0] != -1
                for (x, z), s in zip(centre, d) if s > (STUB_FORK if fork else ROAD_HALF_WIDTH + 6.0)):
            return None
    if not all(inside_terrain(layout, x, z, 40.0) for x, z in centre):
        return None

    # Heights: the loop's own where the stub is on it, then the carved ground, kept gentle.
    nearest = [loop.query(x, z, 60.0) for x, z in centre]
    target = np.array([terrain_height(terrain, layout, x, z) + CARVE_DROP for x, z in centre])
    fixed = np.array([dist < ROAD_HALF_WIDTH + 1.0 for _, dist in nearest])
    for i, (j, _) in enumerate(nearest):
        if fixed[i]:
            target[i] = heights[j]
    h = target.copy()
    for i in range(1, len(h)):
        if not fixed[i]:
            rise = STUB_GRADE * (d[i] - d[i - 1])
            h[i] = min(max(target[i], h[i - 1] - rise), h[i - 1] + rise)
    for _ in range(3):
        smoothed = h.copy()
        smoothed[1:-1] = (h[:-2] + 2.0 * h[1:-1] + h[2:]) / 4.0
        smoothed[-1] = (h[-2] + h[-1]) / 2.0
        h = np.where(fixed, h, smoothed)

    # Edges, level across. Any corner on or near the loop sits just under the loop's surface, so no
    # stub triangle can rise through the loop's road.
    forward = np.gradient(centre, axis=0)
    forward /= np.maximum(np.linalg.norm(forward, axis=1), 1e-9)[:, None]
    right = np.column_stack([-forward[:, 1], forward[:, 0]])
    edges = []
    shoulder_from = len(centre)
    for i in range(len(centre)):
        section = []
        outside = True
        for side in (-1.0, 1.0):
            x, z = centre[i] + right[i] * side * STUB_HALF_WIDTH
            j, dist = loop.query(x, z, 60.0)
            y = min(h[i], heights[j] - 0.05) if dist < ROAD_HALF_WIDTH + 3.0 else h[i]
            outside = outside and dist > ROAD_HALF_WIDTH + 4.5
            section.append((x, y, z))
        # A wide section near the fork can span the loop's road. Keep the whole
        # section a little under the lowest loop point it crosses.
        if d[i] < STUB_FORK:
            (lx, ly, lz), (rx, ry, rz) = section
            cap = None
            for t in np.linspace(0.0, 1.0, 9):
                j, dist = loop.query(lx + (rx - lx) * t, lz + (rz - lz) * t, 60.0)
                if j >= 0 and dist < ROAD_HALF_WIDTH + 0.5:
                    cap = heights[j] - 0.12 if cap is None else min(cap, heights[j] - 0.12)
            if cap is not None:
                section = [(lx, min(ly, cap), lz), (rx, min(ry, cap), rz)]
        if outside and shoulder_from == len(centre):
            shoulder_from = i
        edges.append(section)

    # Barrier near the end, facing back to the loop.
    barrier = (centre[b][0], h[b], centre[b][1], -forward[b][0], -forward[b][1])
    corners = [c for c in (make_corner(edges, d, forward, right, side, points, heights, loop)
            for side in (0, 1)) if c is not None]
    clear_from = max([c["reach"] for c in corners], default=ROAD_HALF_WIDTH) + 1.0
    return {"start": start, "centre": centre, "heights": h, "edges": edges, "shoulder_from": shoulder_from,
            "barrier": barrier, "corners": corners,
            "sign_args": (centre, h, d, right, forward, loop, b, clear_from)}


def make_corner(edges, d, forward, right, side, points, heights, loop: Nearest):
    """Rounded paved corner between one edge of a stub and the loop's edge, so no grass shows there.

    side 0 is the stub's left edge (as built), 1 its right. The corner is a curve from a point A
    on the stub's edge to a point B on the loop's edge, with the sharp corner C, where the stub's
    edge leaves the loop's edge, as its control point. The patch fills between the curve and the
    two edges. Returns {"side", "outer", "inner", "reach"} or None, where reach is how far along the
    stub the corner ends."""
    n = len(points)
    edge = np.array([edges[i][side] for i in range(len(edges))])  # (x, y, z)
    sign = -1.0 if side == 0 else 1.0
    dists = [loop.query(x, z, 60.0) for x, _, z in edge]
    c = next((i for i, (j, dist) in enumerate(dists) if dist >= ROAD_HALF_WIDTH and d[i] > 0.0), None)
    if c is None or c == 0:
        return None
    # Exact crossing of the loop's edge between sections c - 1 and c.
    j0, d0 = dists[c - 1]
    j1, d1 = dists[c]
    if not math.isfinite(d0):
        return None
    t = (ROAD_HALF_WIDTH - d0) / max(d1 - d0, 1e-6)
    t = min(max(t, 0.0), 1.0)
    corner = edge[c - 1] + (edge[c] - edge[c - 1]) * t
    d_c = d[c - 1] + (d[c] - d[c - 1]) * t
    jc, _ = loop.query(corner[0], corner[2], 60.0)
    u = forward[c]
    tangent = points[(jc + 1) % n] - points[(jc - 1) % n]
    tangent /= max(np.linalg.norm(tangent), 1e-9)
    loop_right = np.array([-tangent[1], tangent[0]])
    loop_side = 1.0 if np.dot(corner[::2] - points[jc], loop_right) >= 0.0 else -1.0
    # Along the loop, away from the stub's middle.
    away = 1.0 if np.dot(tangent, right[c] * sign) >= 0.0 else -1.0
    v = tangent * away
    angle = math.acos(min(max(float(np.dot(u, v)), -1.0), 1.0))
    if angle > math.radians(170.0) or angle < math.radians(5.0):
        return None
    reach = min(STUB_FLARE / math.tan(angle / 2.0), CORNER_MAX)
    if reach < 0.5:
        return None

    def stub_edge(dist):
        return np.array([np.interp(dist, d, edge[:, k]) for k in range(3)])

    def loop_edge(along):
        """Point on the loop's edge, `along` metres from the corner, away from the stub."""
        f = along / STEP
        k = int(math.floor(f))
        a = (jc + int(away) * k) % n
        b = (jc + int(away) * (k + 1)) % n
        out = []
        for idx in (a, b):
            tan = points[(idx + 1) % n] - points[(idx - 1) % n]
            tan /= max(np.linalg.norm(tan), 1e-9)
            r = np.array([-tan[1], tan[0]])
            x, z = points[idx] + r * loop_side * ROAD_HALF_WIDTH
            out.append(np.array([x, heights[idx], z]))
        return out[0] + (out[1] - out[0]) * (f - k)

    a_point = stub_edge(d_c + reach)
    b_point = loop_edge(reach)
    c_point = np.array([corner[0], 0.0, corner[2]])
    outer, inner = [], []
    for s in np.linspace(0.0, 1.0, CORNER_STEPS + 1):
        p = (1 - s) ** 2 * a_point + 2 * (1 - s) * s * c_point + s * s * b_point
        p[1] = a_point[1] + (b_point[1] - a_point[1]) * s
        q = stub_edge(d_c + reach * (1.0 - 2.0 * s)) if s <= 0.5 else loop_edge(reach * (2.0 * s - 1.0))
        # Just under both roads, so the patch never shows through either.
        top = min(p[1], q[1]) - CORNER_DROP
        outer.append((float(p[0]), top, float(p[2])))
        inner.append((float(q[0]), top, float(q[2])))
    return {"side": side, "outer": outer, "inner": inner, "reach": d_c + reach}


def sign_spot(centre, h, d, right, forward, loop: Nearest, b, clear_from, text):
    """Where the street's name sign stands: just past the rounded corner, off the road.

    The plate runs along the street, so a driver on the loop sees it face on. The whole plate
    stays clear of the loop and its corner. Returns (x, y, z, forward x, forward z), or None if
    no spot is clear of the loop."""
    half = (SIGN_CHAR_WIDTH * len(text) + SIGN_PLATE_PAD) / 2.0
    # A ramp leaves the loop at a shallow angle, so its rounded corner can run almost to the
    # barrier. Then the sign may stand beside the corner, on the side far from the loop.
    for start, margin in ((clear_from, 2.0), (ROAD_HALF_WIDTH + 1.0, 8.0)):
        for i in range(len(centre)):
            if d[i] < start + half or i >= b:
                continue
            for side in (1.0, -1.0):
                x, z = centre[i] + right[i] * side * (STUB_HALF_WIDTH + SIGN_OFFSET)
                ends = [(x + forward[i][0] * k * half, z + forward[i][1] * k * half) for k in (-1.0, 0.0, 1.0)]
                if all(loop.query(ex, ez, ROAD_HALF_WIDTH + margin)[0] == -1 for ex, ez in ends):
                    return (x, h[i], z, forward[i][0], forward[i][1])
    return None


def mouth_cuts(stubs, points: np.ndarray, bridge: np.ndarray) -> dict:
    """Loop segments, per side, whose grass shoulder a stub's mouth or rounded corners cover.

    Segment i runs from point i to point i + 1. The road there leaves out its shoulder so the
    street joins it without a strip of grass between them. The edge line stays."""
    forward = np.roll(points, -1, axis=0) - np.roll(points, 1, axis=0)
    forward /= np.maximum(np.linalg.norm(forward, axis=1), 1e-9)[:, None]
    right = np.column_stack([-forward[:, 1], forward[:, 0]])
    cuts = {"left": set(), "right": set()}
    for stub in stubs:
        polygons = [np.array([s[0][::2] for s in stub["edges"]] + [s[1][::2] for s in reversed(stub["edges"])])]
        for c in stub["corners"]:
            polygons.append(np.array([p[::2] for p in c["outer"]] + [p[::2] for p in reversed(c["inner"])]))
        for polygon in polygons:
            mark_cuts(polygon, points, right, bridge, cuts)
    return {k: sorted(v) for k, v in cuts.items()}


def mark_cuts(polygon: np.ndarray, points: np.ndarray, right: np.ndarray, bridge: np.ndarray, cuts: dict) -> None:
    """Adds the loop segments whose shoulder this polygon covers."""
    n = len(points)
    lo, hi = polygon.min(axis=0) - 1.0, polygon.max(axis=0) + 1.0
    for i in range(n):
        j = (i + 1) % n
        if bridge[i] or bridge[j]:
            continue
        mid = (points[i] + points[j]) / 2.0
        r = right[i] + right[j]
        r /= max(np.linalg.norm(r), 1e-9)
        for side, key in ((-1.0, "left"), (1.0, "right")):
            for offset in (0.5, 2.5):
                p = mid + r * side * (ROAD_HALF_WIDTH + offset)
                if (lo <= p).all() and (p <= hi).all() and inside_polygon(polygon, p):
                    cuts[key].add(i)


def inside_polygon(polygon: np.ndarray, p) -> bool:
    x, z = p
    xs, zs = polygon[:, 0], polygon[:, 1]
    xn, zn = np.roll(xs, -1), np.roll(zs, -1)
    crosses = (zs > z) != (zn > z)
    with np.errstate(divide="ignore", invalid="ignore"):
        at = xs + (z - zs) * (xn - xs) / (zn - zs)
    return bool(np.count_nonzero(crosses & (x < at)) % 2)


def carve_stubs(terrain: np.ndarray, layout: dict, stubs, loop: Nearest) -> np.ndarray:
    """Ground near each stub brought just under it, blending back to the ground around.

    Ground close to the loop is only ever lowered here: raised, it would poke up through the loop's road."""
    original = terrain
    terrain = terrain.copy()
    cell, x0, z0 = layout["cell"], layout["x0"], layout["z0"]
    reach = int(math.ceil(STUB_BLEND / cell)) + 1
    for stub in stubs:
        rows, cols = terrain.shape
        near = np.full(terrain.shape, np.inf)
        stub_h = np.zeros(terrain.shape)
        for (px, pz), ph in zip(stub["centre"], stub["heights"]):
            ci = int(round((px - x0) / cell))
            ri = int(round((pz - z0) / cell))
            r_lo, r_hi = max(ri - reach, 0), min(ri + reach + 1, rows)
            c_lo, c_hi = max(ci - reach, 0), min(ci + reach + 1, cols)
            gx = x0 + np.arange(c_lo, c_hi) * cell
            gz = z0 + np.arange(r_lo, r_hi) * cell
            dist = np.hypot(gx[None, :] - px, gz[:, None] - pz)
            block = near[r_lo:r_hi, c_lo:c_hi]
            closer = dist < block
            block[closer] = dist[closer]
            stub_h[r_lo:r_hi, c_lo:c_hi][closer] = ph
        t = np.clip((near - STUB_FLAT) / (STUB_BLEND - STUB_FLAT), 0.0, 1.0)
        weight = 1.0 - t * t * (3.0 - 2.0 * t)
        touched = weight > 0.0
        flat = stub_h - CARVE_DROP
        terrain[touched] = terrain[touched] * (1.0 - weight[touched]) + flat[touched] * weight[touched]
    rows, cols = terrain.shape
    for r, c in zip(*np.nonzero(terrain > original)):
        if loop.query(x0 + c * cell, z0 + r * cell, STUB_KEEP)[0] >= 0:
            terrain[r, c] = original[r, c]
    return terrain


def stub_data(stub: dict, base: float) -> dict:
    return {
        "name": stub["name"],
        "edges": [round(float(v), 2) for section in stub["edges"] for (x, y, z) in section
                for v in (x, y - base, z)],
        "shoulder_from": stub["shoulder_from"],
        "barrier": [round(float(v), 3) for v in (stub["barrier"][0], stub["barrier"][1] - base,
                stub["barrier"][2], stub["barrier"][3], stub["barrier"][4])],
        "half_width": STUB_HALF_WIDTH,
        "corners": [{"side": c["side"], "reach": round(float(c["reach"]), 2),
                "strip": [round(float(v), 2) for o, i in zip(c["outer"], c["inner"]) for p in (o, i)
                for v in (p[0], p[1] - base, p[2])]} for c in stub["corners"]],
        "sign": stub["sign"],
        "sign_post": [round(float(v), 3) for v in (stub["sign_post"][0], stub["sign_post"][1] - base,
                stub["sign_post"][2], stub["sign_post"][3], stub["sign_post"][4])] if stub["sign_post"] else [],
    }


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


def load_footprints(cache: str, osm: dict, proj: Projection):
    """Building outlines in local metres, with heights above the ground beside them and roofs.

    Uses the Overture outlines and lidar roofs from fetch_buildings.py when they are in the
    cache, and the OSM outlines with guessed heights when they are not.
    """
    path = os.path.join(cache, "overture_buildings.json")
    found = []
    if os.path.exists(path):
        with open(path) as f:
            outlines = json.load(f)
        roofs = {}
        roofs_path = os.path.join(cache, "building_roofs.json")
        if os.path.exists(roofs_path):
            with open(roofs_path) as f:
                roofs = json.load(f)
        for b in outlines:
            roof = roofs.get(b["id"])
            if roof is None:
                if b.get("height"):
                    height = float(b["height"])
                elif b.get("floors"):
                    height = 3.2 * float(b["floors"])
                else:
                    height = building_height({"building": b.get("class") or ""})
                roof = {"roof": "flat", "eave": height, "ridge": height}
            found.append({"ring": np.array([proj.to_local(lat, lon) for lon, lat in b["ring"]]),
                    "kind": b.get("class") or "", "subtype": b.get("subtype") or "", "roof": roof["roof"],
                    "ridge_along": roof.get("ridge_along", "long"), "eave": roof["eave"],
                    "ridge": roof["ridge"], "measured": b["id"] in roofs})
        print("%d building outlines from Overture, %d with lidar roofs" % (len(found), len(roofs)))
        return found
    for w in osm["elements"]:
        if w.get("type") != "way" or len(w.get("geometry", ())) < 4:
            continue
        height = building_height(w["tags"])
        found.append({"ring": np.array([proj.to_local(g["lat"], g["lon"]) for g in w["geometry"]]),
                "kind": w["tags"].get("building", ""), "subtype": "", "roof": "flat", "ridge_along": "long",
                "eave": height, "ridge": height, "measured": False})
    print("%d building outlines from OSM (no fetch_buildings.py files in the cache)" % len(found))
    return found


def place_buildings(footprints, proj: Projection, loop: Nearest, stubs, layout: dict, terrain: np.ndarray):
    """Buildings near the road and clear of it, each sitting on the ground, with a style and colours.

    A sloped roof sits on the outline's smallest enclosing box, so its walls become that box;
    an outline that fills too little of its box keeps its shape and gets a flat roof instead.
    """
    rng = np.random.default_rng(SEED)
    town = np.array(proj.to_local(*TOWN_CENTRE))
    blocks = []
    for f in footprints:
        ring = f["ring"]
        if len(ring) > 3 and np.allclose(ring[0], ring[-1]):
            ring = ring[:-1]
        area = ring_area(ring)
        if len(ring) < 3 or abs(area) < 12.0:
            continue
        if area < 0:
            ring = ring[::-1]  # Same winding for every outline.
            area = -area
        cx, cz, yaw, length, width = min_area_box(ring)
        if length > 200.0 or not inside_terrain(layout, cx, cz, 20.0):
            continue
        _, road_gap = loop.query(cx, cz, BUILDING_RANGE)
        if stubs is not None:
            road_gap = min(road_gap, stubs.query(cx, cz, BUILDING_RANGE)[1])
        if math.isinf(road_gap) or not clear_of_road(ring, loop, stubs):
            continue
        style = building_style(f, area, math.hypot(cx - town[0], cz - town[1]), road_gap)
        eave, ridge, roof = float(f["eave"]), float(f["ridge"]), f["roof"]
        fill = area / max(length * width, 1e-6)
        if roof == "flat" and style == "house" and fill >= BOX_FILL and area >= 40.0:
            # Most houses here have pitched roofs that the lidar was too sparse or too leafy to see.
            rise = min(3.0, HOUSE_PITCH * width / 2.0)
            eave = max(2.4, eave - rise / 2.0)
            ridge, roof = eave + rise, "gable"
        if roof != "flat" and fill < BOX_FILL:
            eave = ridge = (eave + ridge) / 2.0
            roof = "flat"
        eave = min(max(eave, 2.4), 60.0)
        ridge = max(ridge, eave)
        if roof != "flat":
            ring = box_corners(cx, cz, yaw, length, width)
        ground = [terrain_height(terrain, layout, x, z) for x, z in ring]
        low = min(ground)
        lift = float(np.mean(ground)) - low + BUILDING_SINK  # From the wall's foot up to the ground.
        wall, top = building_colours(style, roof, rng)
        blocks.append({"ring": ring, "base": low - BUILDING_SINK, "eave": eave + lift, "ridge": ridge + lift,
                "roof": roof, "ridge_along": f["ridge_along"], "box": (cx, cz, yaw, length, width),
                "style": style, "wall": wall, "top": top, "area": area})
    return blocks


def ring_area(ring: np.ndarray) -> float:
    """Signed area of an outline in the x, z plane."""
    x, z = ring[:, 0], ring[:, 1]
    return 0.5 * float(np.dot(x, np.roll(z, -1)) - np.dot(z, np.roll(x, -1)))


def clear_of_road(ring: np.ndarray, loop: Nearest, stubs) -> bool:
    """True if no point along the outline is within ROAD_CLEAR of the loop's centreline, or within
    STUB_BUILDING_CLEAR of a side street's (ROAD_CLEAR near the loop, where the corners flare)."""
    for a, b in zip(ring, np.roll(ring, -1, axis=0)):
        steps = max(1, int(math.ceil(np.linalg.norm(b - a) / 3.0)))
        for t in np.linspace(0.0, 1.0, steps, endpoint=False):
            x, z = a + (b - a) * t
            if loop.query(x, z, ROAD_CLEAR)[0] != -1:
                return False
            if stubs is None:
                continue
            reach = ROAD_CLEAR if loop.query(x, z, MOUTH_CLEAR)[0] != -1 else STUB_BUILDING_CLEAR
            if stubs.query(x, z, reach)[0] != -1:
                return False
    return True


def box_corners(cx, cz, yaw, length, width) -> np.ndarray:
    u = np.array([math.cos(yaw), math.sin(yaw)]) * length / 2.0
    v = np.array([-math.sin(yaw), math.cos(yaw)]) * width / 2.0
    c = np.array([cx, cz])
    return np.array([c - u - v, c + u - v, c + u + v, c - u + v])


def building_style(f: dict, area: float, from_town: float, road_gap: float) -> str:
    """shop (brick, shop windows), civic (brick or stone), store (big and plain) or house."""
    if f["kind"] in ("university", "church", "school", "library", "civic", "hospital", "courthouse") \
            or f["subtype"] in ("education", "religious", "civic", "medical"):
        return "civic"
    if from_town < TOWN_RADIUS and road_gap < 45.0:
        return "shop"
    if area > 900.0 or (area > 300.0 and f["subtype"] in ("commercial", "industrial")):
        return "store"
    if area > 300.0 and f["subtype"] != "residential":
        return "store"
    return "house"


HOUSE_WALLS = [(0.90, 0.89, 0.85), (0.74, 0.75, 0.76), (0.88, 0.82, 0.66), (0.67, 0.74, 0.80),
        (0.89, 0.83, 0.57), (0.67, 0.72, 0.60), (0.80, 0.70, 0.56), (0.93, 0.93, 0.92)]
BRICK_WALLS = [(0.55, 0.25, 0.18), (0.62, 0.32, 0.22), (0.48, 0.22, 0.17), (0.70, 0.56, 0.42)]
CIVIC_WALLS = [(0.58, 0.30, 0.22), (0.66, 0.61, 0.52), (0.52, 0.27, 0.20)]
STORE_WALLS = [(0.68, 0.68, 0.66), (0.78, 0.74, 0.66), (0.58, 0.60, 0.62), (0.82, 0.80, 0.76)]
SLOPED_ROOFS = [(0.24, 0.24, 0.26), (0.34, 0.22, 0.18), (0.30, 0.32, 0.36), (0.40, 0.38, 0.35)]
FLAT_ROOFS = [(0.40, 0.40, 0.40), (0.47, 0.46, 0.44), (0.33, 0.33, 0.34)]


def building_colours(style: str, roof: str, rng):
    walls = {"house": HOUSE_WALLS, "shop": BRICK_WALLS, "civic": CIVIC_WALLS, "store": STORE_WALLS}[style]
    tops = FLAT_ROOFS if roof == "flat" else SLOPED_ROOFS
    return walls[rng.integers(len(walls))], tops[rng.integers(len(tops))]


def building_data(b: dict, base: float) -> dict:
    data = {"ring": [round(float(v), 2) for p in b["ring"] for v in p], "y": round(b["base"] - base, 2),
            "eave": round(b["eave"], 2), "style": b["style"],
            "wall": list(b["wall"]), "top": list(b["top"])}
    if b["roof"] != "flat":
        data["roof"] = b["roof"]
        data["ridge"] = round(b["ridge"], 2)
        data["box"] = [round(float(v), 3) for v in b["box"]]
        data["ridge_along"] = b["ridge_along"]
    return data


# Business signs -------------------------------------------------------------------------------


def place_businesses(cache: str, blocks, proj: Projection, loop: Nearest, streets: dict, heights: np.ndarray,
        terrain: np.ndarray, layout: dict):
    """A sign on the wall of each listed business that faces the loop, and a pole sign by the
    road when that wall is set well back.

    A business whose address is on a street that leaves the loop faces that street instead, with
    its pole sign at the street's edge in front of it, turned to be read from along the street.
    """
    path = os.path.join(cache, "businesses.json")
    if not os.path.exists(path):
        return []
    with open(path) as f:
        wanted = json.load(f)
    signs = []
    for biz in wanted:
        spot = np.array(proj.to_local(biz["lat"], biz["lon"]))
        block = building_at(blocks, spot)
        if block is None:
            print("no building near %s, so no sign" % biz["sign"])
            continue
        centre = block["ring"].mean(axis=0)
        street = address_street(streets, biz.get("address", ""), proj, loop, centre)
        middle, out, edge = facing_wall(block["ring"], street or loop)
        ground = terrain_height(terrain, layout, *middle)
        top = block["base"] + block["eave"]
        i, gap = loop.query(middle[0], middle[1], 1000.0)
        # Letters grow with the distance from the road, as long as the wall is wide enough.
        letters = len(biz["sign"]) * SIGN_CHAR_WIDTH
        scale = min(max(gap / 15.0, 1.0), 3.0, max((edge - 0.6 - SIGN_PLATE_PAD) / letters, 0.5))
        half = SIGN_PLATE_HEIGHT * scale / 2.0
        height = max(min(ground + SIGN_WALL_HEIGHT, top - half - 0.2), ground + half + 1.0)
        sign = {"text": biz["sign"], "scale": scale, "width": letters * scale + SIGN_PLATE_PAD,
                "wall": (middle + out * 0.12, height, out)}
        if street is not None:
            k, street_gap = street.query(middle[0], middle[1], 1000.0)
            road = street.points[k]
            toward = (middle - road) / max(street_gap, 1e-9)
            pole = road + toward * min(STUB_HALF_WIDTH + 2.0, street_gap / 2.0)
            ahead = street.ahead[k]
            sign["pole"] = (pole, terrain_height(terrain, layout, *pole), ahead)
        elif gap > SIGN_POLE_FROM:
            road = loop.points[i]
            ahead = loop.points[(i + 1) % len(loop.points)] - loop.points[i - 1]
            ahead /= max(np.linalg.norm(ahead), 1e-9)
            toward = (middle - road) / gap
            pole = road + toward * (ROAD_HALF_WIDTH + 4.5)
            sign["pole"] = (pole, max(terrain_height(terrain, layout, *pole), heights[i] - 1.0), ahead)
        signs.append(sign)
        print("sign %-30s %s" % (biz["sign"], "wall and pole" if "pole" in sign else "wall"))
    return signs


def street_key(name: str) -> str:
    """A street name in a form that matches across spellings: "S 5th Ave" and "South 5th Avenue"."""
    words = {"st": "street", "ave": "avenue", "av": "avenue", "rd": "road", "hwy": "highway",
             "dr": "drive", "ln": "lane", "ct": "court", "s": "south", "n": "north", "e": "east", "w": "west"}
    tokens = re.sub(r"[^a-z0-9 ]", " ", name.lower()).split()
    return " ".join(words.get(t, t) for t in tokens)


def address_street(streets: dict, address: str, proj: Projection, loop: Nearest, centre: np.ndarray):
    """Points along the street named in an address, where it runs near the business but off the
    loop, with the direction along it at each; None when the address is on the loop itself."""
    number = re.match(r"\s*\d+\s+(.*)", address)
    if not number:
        return None
    key = street_key(number.group(1))
    points, ahead = [], []
    for way in streets["elements"]:
        if street_key(way.get("tags", {}).get("name", "")) != key:
            continue
        line = np.array([proj.to_local(n["lat"], n["lon"]) for n in way["geometry"]])
        for a, b in zip(line[:-1], line[1:]):
            run = float(np.linalg.norm(b - a))
            if run < 1e-6:
                continue
            for t in np.linspace(0.0, 1.0, max(1, int(run / STREET_SAMPLE)), endpoint=False):
                p = a + (b - a) * t
                if np.linalg.norm(p - centre) > 150.0:
                    continue
                if loop.query(p[0], p[1], STUB_CLEAR)[0] != -1:
                    continue
                points.append(p)
                ahead.append((b - a) / run)
    if not points:
        return None
    street = Nearest(np.array(points))
    street.ahead = ahead
    # On the loop if the street's nearest point to the business is on it.
    if loop.query(centre[0], centre[1], 1000.0)[1] < street.query(centre[0], centre[1], 1000.0)[1]:
        return None
    return street


def building_at(blocks, spot: np.ndarray, reach: float = 60.0):
    """The building whose outline holds a place, or else the nearest one within reach."""
    best, best_gap = None, reach
    for b in blocks:
        ring = b["ring"]
        if np.abs(ring - spot).min(axis=0).max() > reach + 200.0:
            continue
        if inside_polygon(ring, spot):
            return b
        gap = min(segment_gap(spot, a, c) for a, c in zip(ring, np.roll(ring, -1, axis=0)))
        if gap < best_gap:
            best, best_gap = b, gap
    return best


def segment_gap(p: np.ndarray, a: np.ndarray, b: np.ndarray) -> float:
    ab = b - a
    t = min(max(float(np.dot(p - a, ab) / max(np.dot(ab, ab), 1e-9)), 0.0), 1.0)
    return float(np.linalg.norm(p - (a + ab * t)))


def facing_wall(ring: np.ndarray, loop: Nearest):
    """Middle, outward direction and length of the wall that looks most squarely at the loop."""
    best = None
    for a, b in zip(ring, np.roll(ring, -1, axis=0)):
        edge = b - a
        length = float(np.linalg.norm(edge))
        if length < 2.0:
            continue
        middle = (a + b) / 2.0
        out = np.array([edge[1], -edge[0]]) / length
        if inside_polygon(ring, middle + out * 0.3):
            out = -out
        i, gap = loop.query(middle[0], middle[1], 1000.0)
        if i < 0:
            continue
        look = float(np.dot(out, (loop.points[i] - middle) / max(gap, 1e-9)))
        score = look - 0.004 * gap - (0.5 if length < 6.0 else 0.0)
        if best is None or score > best[0]:
            best = (score, middle, out, length)
    return best[1:]


def business_data(sign: dict, base: float) -> dict:
    spot, y, out = sign["wall"]
    data = {"text": sign["text"], "width": round(float(sign["width"]), 2), "scale": round(float(sign["scale"]), 2),
            "wall": [round(float(v), 3) for v in (spot[0], y - base, spot[1], out[0], out[1])]}
    if "pole" in sign:
        spot, y, ahead = sign["pole"]
        data["pole"] = [round(float(v), 3) for v in (spot[0], y - base, spot[1], ahead[0], ahead[1])]
    return data


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


def place_trees(loop: Nearest, road: Nearest, layout: dict, terrain: np.ndarray, blocks):
    """Random trees in a band either side of the loop, clear of every road and the buildings."""
    rng = np.random.default_rng(SEED)
    pts = loop.points
    building_tree = Nearest(building_samples(blocks))
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
        if building_tree.query(x, z, TREE_BUILDING_CLEAR)[0] != -1:
            continue
        scale = 0.7 + 0.6 * rng.random()
        trees.append((x, terrain_height(terrain, layout, x, z), z, scale))
    return trees


def building_samples(blocks) -> np.ndarray:
    """Points along every building's walls and across its inside, for keeping trees out."""
    samples = [np.zeros((0, 2))]
    for b in blocks:
        ring = b["ring"]
        for a, c in zip(ring, np.roll(ring, -1, axis=0)):
            steps = max(1, int(math.ceil(np.linalg.norm(c - a) / 3.0)))
            samples.append(a + (c - a) * np.linspace(0.0, 1.0, steps, endpoint=False)[:, None])
        lo, hi = ring.min(axis=0), ring.max(axis=0)
        for x in np.arange(lo[0] + 2.0, hi[0], 4.0):
            for z in np.arange(lo[1] + 2.0, hi[1], 4.0):
                if inside_polygon(ring, (x, z)):
                    samples.append(np.array([[x, z]]))
    return np.vstack(samples)


if __name__ == "__main__":
    main()
