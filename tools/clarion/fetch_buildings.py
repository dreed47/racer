#!/usr/bin/env python3
"""Fetch building outlines, roof heights and business places for the Clarion loop.

Run once before build_track.py, with the same cache folder:

    uv run --no-project --with duckdb --with laspy --with lazrs --with numpy --with pillow \
        python tools/clarion/fetch_buildings.py CACHE_DIR

It writes three files into CACHE_DIR, and skips any that are already there:

- overture_buildings.json: building outlines from Overture Maps (OpenStreetMap plus
  Microsoft and Google footprints), with any height and floor count the map has.
- businesses.json: the place of each business in tools/clarion/businesses.json, from
  Overture Maps places.
- building_roofs.json: wall and roof heights for each outline, measured from USGS 3DEP
  lidar (the 2019 Western PA survey, read from the AWS open data copy). Only the lidar
  tiles over buildings are downloaded, into CACHE_DIR/lidar (about 500 MB). The points on
  each roof are kept in roof_points.npz; delete building_roofs.json to fit the roofs again.

build_track.py reads these files if they are there and falls back to plain blocks if not.
"""

import concurrent.futures
import json
import math
import os
import sys
import urllib.request

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_track import AREA_BOX, USER_AGENT, min_area_box  # noqa: E402

OVERTURE = "s3://overturemaps-us-west-2/release/2026-11-18.0"
EPT = "https://s3-us-west-2.amazonaws.com/usgs-lidar-public/PA_WesternPA_2_2019"
EPT_DEPTH = 11  # Deepest lidar level read: about one point per 0.8 m, plenty for a roof.
EARTH = 6378137.0
GROUND_RING = 6.0  # Ground height comes from lidar ground points this far round the outline.
MIN_ROOF_POINTS = 6
PITCH_MIN = 0.15  # Rise per metre across the roof above which it counts as pitched.
GABLE_FIT = 0.6  # A gable must leave the points this much closer than a flat top does.
MIN_ROOF_RISE = 1.5  # Points less than this above the ground are walls, cars or bushes.
LIDAR_CLASS_UNSORTED = 1  # This survey does not mark buildings; roofs are in with trees here.
LIDAR_CLASS_GROUND = 2
LIDAR_CLASS_BUILDING = 6


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: fetch_buildings.py CACHE_DIR")
    cache = sys.argv[1]
    os.makedirs(cache, exist_ok=True)
    here = os.path.dirname(os.path.abspath(__file__))

    outlines_path = os.path.join(cache, "overture_buildings.json")
    if not os.path.exists(outlines_path):
        write_json(outlines_path, overture_buildings())
    outlines = json.load(open(outlines_path))
    print("%d building outlines" % len(outlines))

    places_path = os.path.join(cache, "businesses.json")
    if not os.path.exists(places_path):
        wanted = json.load(open(os.path.join(here, "businesses.json")))
        write_json(places_path, find_businesses(wanted))
    for b in json.load(open(places_path)):
        print("  %-32s %s" % (b["sign"], "found: %s" % b["address"] if b.get("lat") else "NOT FOUND"))

    roofs_path = os.path.join(cache, "building_roofs.json")
    points_path = os.path.join(cache, "roof_points.npz")
    if not os.path.exists(points_path):
        measure_roofs(outlines, os.path.join(cache, "lidar"), points_path)
    if not os.path.exists(roofs_path):
        write_json(roofs_path, fit_roofs(outlines, points_path))
    roofs = json.load(open(roofs_path))
    count = {k: sum(1 for r in roofs.values() if r["roof"] == k) for k in ("flat", "gable", "hip")}
    print("%d roofs measured from lidar: %d flat, %d gable, %d hip" % ((len(roofs),) + tuple(count.values())))


def write_json(path: str, data) -> None:
    with open(path + ".part", "w") as f:
        json.dump(data, f, separators=(",", ":"))
    os.replace(path + ".part", path)


# Overture Maps --------------------------------------------------------------------------------


def overture():
    import duckdb

    con = duckdb.connect()
    con.sql("INSTALL httpfs; LOAD httpfs; INSTALL spatial; LOAD spatial; SET s3_region='us-west-2';")
    return con


def box_filter() -> str:
    s, w, n, e = AREA_BOX
    return "bbox.xmin > %f AND bbox.xmax < %f AND bbox.ymin > %f AND bbox.ymax < %f" % (w, e, s, n)


def overture_buildings() -> list:
    """Each outline's outer ring as [lon, lat] pairs, with the map's own facts about it."""
    rows = overture().sql("""
        SELECT id, names.primary, class, subtype, height, num_floors, roof_shape,
               ST_AsText(geometry), sources[1].dataset
        FROM read_parquet('%s/theme=buildings/type=building/*', hive_partitioning=1)
        WHERE %s""" % (OVERTURE, box_filter())).fetchall()
    out = []
    for r in rows:
        ring = outer_ring(r[7])
        if ring is None:
            continue
        out.append({"id": r[0], "name": r[1], "class": r[2], "subtype": r[3], "height": r[4],
                "floors": r[5], "roof_shape": r[6], "source": r[8], "ring": ring})
    return out


def outer_ring(wkt: str):
    """Outer ring of a POLYGON, or of the biggest part of a MULTIPOLYGON."""
    if wkt.startswith("POLYGON"):
        parts = [wkt[len("POLYGON"):]]
    elif wkt.startswith("MULTIPOLYGON"):
        parts = wkt[len("MULTIPOLYGON"):].strip()[1:-1].split(")), ((")
    else:
        return None
    best = None
    for part in parts:
        first = part.strip().strip("()").split("), (")[0]
        ring = [[round(float(a), 7), round(float(b), 7)] for a, b in (p.split() for p in first.split(","))]
        area = abs(ring_area(np.array(ring)))
        if best is None or area > best[0]:
            best = (area, ring)
    return best[1]


def ring_area(ring: np.ndarray) -> float:
    x, y = ring[:, 0], ring[:, 1]
    return 0.5 * float(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1)))


def find_businesses(wanted: list) -> list:
    """Overture's place for each wanted business: the best match on its search name."""
    con = overture()
    rows = con.sql("""
        SELECT names.primary, basic_category, addresses[1].freeform, ST_Y(geometry), ST_X(geometry), confidence
        FROM read_parquet('%s/theme=places/type=place/*', hive_partitioning=1)
        WHERE %s""" % (OVERTURE, box_filter())).fetchall()
    out = []
    for w in wanted:
        key = w["match"].lower()
        hits = sorted((r for r in rows if r[0] and key in r[0].lower()), key=lambda r: -(r[5] or 0.0))
        entry = {"sign": w["sign"]}
        if hits:
            r = hits[0]
            entry.update({"name": r[0], "category": r[1], "address": (r[2] or "").strip(),
                    "lat": r[3], "lon": r[4]})
        out.append(entry)
    return out


# Lidar ----------------------------------------------------------------------------------------


def web_mercator(lon: np.ndarray, lat: np.ndarray):
    x = np.radians(lon) * EARTH
    y = np.log(np.tan(np.pi / 4.0 + np.radians(lat) / 2.0)) * EARTH
    return x, y


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as reply:
        return reply.read()


def lidar_nodes(boxes: np.ndarray) -> list:
    """EPT nodes, to EPT_DEPTH, whose square overlaps any building box (x0, y0, x1, y1)."""
    info = json.loads(fetch(EPT + "/ept.json"))
    cube = info["bounds"]
    size = cube[3] - cube[0]
    keep = []
    pending = ["0-0-0-0"]
    while pending:
        hierarchy = json.loads(fetch("%s/ept-hierarchy/%s.json" % (EPT, pending.pop())))
        for key, count in hierarchy.items():
            d, x, y, _ = (int(v) for v in key.split("-"))
            if d > EPT_DEPTH:
                continue
            w = size / 2 ** d
            x0, y0 = cube[0] + x * w, cube[1] + y * w
            hit = np.any((boxes[:, 0] < x0 + w) & (boxes[:, 2] > x0) & (boxes[:, 1] < y0 + w) & (boxes[:, 3] > y0))
            if not hit:
                continue
            if count == -1:
                pending.append(key)  # Its part of the tree is in a file of its own.
            elif count > 0:
                keep.append(key)
    return keep


def download_nodes(keys: list, folder: str) -> None:
    os.makedirs(folder, exist_ok=True)

    def one(key: str) -> None:
        path = os.path.join(folder, key + ".laz")
        if not os.path.exists(path):
            data = fetch("%s/ept-data/%s.laz" % (EPT, key))
            with open(path + ".part", "wb") as f:
                f.write(data)
            os.replace(path + ".part", path)

    with concurrent.futures.ThreadPoolExecutor(4) as pool:
        for i, _ in enumerate(pool.map(one, keys)):
            if i % 200 == 0:
                print("  lidar %d of %d" % (i, len(keys)), flush=True)


def inside(px: np.ndarray, py: np.ndarray, ring: np.ndarray) -> np.ndarray:
    """Which points lie inside a ring, by counting edge crossings."""
    result = np.zeros(px.shape, bool)
    x, y = ring[:, 0], ring[:, 1]
    for i in range(len(ring) - 1):
        x1, y1, x2, y2 = x[i], y[i], x[i + 1], y[i + 1]
        crosses = (y1 > py) != (y2 > py)
        with np.errstate(divide="ignore", invalid="ignore"):
            at = x1 + (py - y1) * (x2 - x1) / (y2 - y1)
        result ^= crosses & (px < at)
    return result


def measure_roofs(outlines: list, folder: str, points_path: str) -> None:
    import laspy

    rings, boxes = [], []
    for b in outlines:
        ring = np.array(b["ring"])
        x, y = web_mercator(ring[:, 0], ring[:, 1])
        rings.append(np.column_stack([x, y]))
        boxes.append((x.min(), y.min(), x.max(), y.max()))
    boxes = np.array(boxes)
    # Web Mercator stretches distances by 1 / cos(latitude); the ground ring is in real metres.
    stretch = 1.0 / math.cos(math.radians((AREA_BOX[0] + AREA_BOX[2]) / 2.0))
    margin = GROUND_RING * stretch
    keys = lidar_nodes(boxes + np.array([-margin, -margin, margin, margin]))
    print("  %d lidar tiles over buildings" % len(keys))
    download_nodes(keys, folder)

    # Sort every point into a coarse grid, then look up each outline's cells.
    cell = 50.0
    grid = {}
    for key in keys:
        las = laspy.read(os.path.join(folder, key + ".laz"))
        cls = np.asarray(las.classification)
        use = (cls == LIDAR_CLASS_GROUND) | (cls == LIDAR_CLASS_BUILDING) | (cls == LIDAR_CLASS_UNSORTED)
        pts = np.column_stack([np.asarray(las.x)[use], np.asarray(las.y)[use], np.asarray(las.z)[use],
                cls[use]])
        ci = np.floor(pts[:, 0] / cell).astype(np.int64)
        cj = np.floor(pts[:, 1] / cell).astype(np.int64)
        order = np.lexsort((cj, ci))
        pts, ci, cj = pts[order], ci[order], cj[order]
        starts = np.flatnonzero(np.r_[True, (np.diff(ci) != 0) | (np.diff(cj) != 0)])
        for s, e in zip(starts, np.r_[starts[1:], len(pts)]):
            grid.setdefault((int(ci[s]), int(cj[s])), []).append(pts[s:e])

    # Keep each outline's points, so the roof fit can change without reading the lidar again.
    found = {}
    for b, ring, box in zip(outlines, rings, boxes):
        chunks = [grid[(i, j)] for i in range(int(math.floor((box[0] - margin) / cell)),
                int(math.floor((box[2] + margin) / cell)) + 1)
                for j in range(int(math.floor((box[1] - margin) / cell)), int(math.floor((box[3] + margin) / cell)) + 1)
                if (i, j) in grid]
        if not chunks:
            continue
        pts = np.vstack([c for cs in chunks for c in cs])
        near = ((pts[:, 0] > box[0] - margin) & (pts[:, 0] < box[2] + margin)
                & (pts[:, 1] > box[1] - margin) & (pts[:, 1] < box[3] + margin))
        pts = pts[near]
        within = inside(pts[:, 0], pts[:, 1], ring)
        ground = pts[~within & (pts[:, 3] == LIDAR_CLASS_GROUND)]
        if len(ground) < 3:
            continue
        base = float(np.median(ground[:, 2]))
        roof = pts[within & (pts[:, 3] != LIDAR_CLASS_GROUND) & (pts[:, 2] > base + MIN_ROOF_RISE)]
        if len(roof) >= MIN_ROOF_POINTS:
            found[b["id"]] = np.column_stack([roof[:, :2], roof[:, 2] - base]).astype(np.float64)
    np.savez_compressed(points_path, **found)


def fit_roofs(outlines: list, points_path: str) -> dict:
    stretch = 1.0 / math.cos(math.radians((AREA_BOX[0] + AREA_BOX[2]) / 2.0))
    points = np.load(points_path)
    roofs = {}
    for b in outlines:
        if b["id"] not in points:
            continue
        ring = np.array(b["ring"])
        x, y = web_mercator(ring[:, 0], ring[:, 1])
        roofs[b["id"]] = fit_roof(points[b["id"]], np.column_stack([x, y]), stretch)
    return roofs


def fit_roof(roof: np.ndarray, ring: np.ndarray, stretch: float):
    """Flat, gable or hip roof from the points on it (x, y, height above the ground beside it).

    Trees over a roof show as points well above the rest, so each fit drops the points far
    from it and fits again. A gable's ridge runs along the outline's long or short side; a hip
    slopes in from all four. The shape that fits best wins, and a sloped one counts only if it
    fits much better than a flat top and is steep enough to see.
    """
    centre = ring.mean(axis=0)
    cx, cz, yaw, length, width = min_area_box((ring - centre) / stretch)
    pts = (roof[:, :2] - centre) / stretch
    z = roof[:, 2]
    c, s = math.cos(yaw), math.sin(yaw)
    u = np.abs((pts[:, 0] - cx) * c + (pts[:, 1] - cz) * s)
    v = np.abs(-(pts[:, 0] - cx) * s + (pts[:, 1] - cz) * c)

    level, flat_error = robust_fit(np.ones((len(z), 1)), z)
    # Each shape as the distance in from the edges that its slopes rise over.
    shapes = (("gable", "long", width / 2.0 - v), ("gable", "short", length / 2.0 - u),
            ("hip", "long", np.minimum(width / 2.0 - v, length / 2.0 - u)))
    best = None
    for roof, axis, inward in shapes:
        (eave, pitch), error = robust_fit(np.column_stack([np.ones_like(inward), np.clip(inward, 0.0, None)]), z)
        if best is None or error < best[0]:
            best = (error, roof, axis, eave, pitch)
    error, roof, axis, eave, pitch = best
    rise = pitch * (width / 2.0 if axis == "long" else length / 2.0)
    if PITCH_MIN < pitch < 1.5 and error < flat_error * GABLE_FIT and eave > 2.0:
        return {"roof": roof, "ridge_along": axis, "eave": round(eave, 2), "ridge": round(eave + rise, 2)}
    top = round(max(float(level[0]), 2.5), 2)
    return {"roof": "flat", "eave": top, "ridge": top}


def robust_fit(a: np.ndarray, z: np.ndarray):
    """Least squares that drops far-off points and fits again. Coefficients and mean error."""
    keep = np.ones(len(z), bool)
    for _ in range(3):
        coef, *_ = np.linalg.lstsq(a[keep], z[keep], rcond=None)
        miss = np.abs(z - a @ coef)
        cut = max(1.0, 2.5 * float(np.median(miss[keep])))
        new = miss < cut
        if new.sum() < MIN_ROOF_POINTS:
            break
        keep = new
    return [float(v) for v in coef], float(np.mean(np.abs(z - a @ coef)[keep]))

if __name__ == "__main__":
    main()
