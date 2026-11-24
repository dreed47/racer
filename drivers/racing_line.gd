class_name RacingLine
extends RefCounted
## The line an AI driver follows round a track, and how fast it can go at each point.
## Built from the track's centreline: the line is pulled as smooth as the road width allows
## (cutting in to the inside of corners), then each point gets the fastest speed the tires
## can hold there, slowed in time for the corners ahead.
## Plain data, no nodes, so tests can build and read one.

## Distance between line points, in metres.
const STEP := 4.0
## Smoothing passes. More gives a smoother line but takes longer to build.
const PASSES := 400
## Pull towards the smooth line each pass. Above 1 gets there in fewer passes.
const RELAX := 1.6
## Fastest speed the line ever asks for, in m/s.
const TOP_SPEED := 70.0
const GRAVITY := 9.81

## Points along the line, in world space, starting at the start line.
var points := PackedVector3Array()
## How far each point sits right (+) or left (-) of the centreline, in metres.
var offsets := PackedFloat32Array()
## Target speed at each point, in m/s.
var speeds := PackedFloat32Array()
## Sideways and braking grip the speeds were worked out for, in m/s².
var corner_accel := 0.0
var brake_accel := 0.0

var _centre := PackedVector3Array()
var _right := PackedVector3Array()
var _cached_step := 0.0


## Builds the line for a track. edge_gap: how far the middle of the car stays from the road edge.
## corner_accel and brake_accel: sideways and braking grip to plan for, in m/s².
## With no track the line is empty; copy() uses that.
func _init(track: Track = null, edge_gap := 1.6, corner := 9.0, brake := 8.0) -> void:
	if track == null:
		return
	var length := track.lap_length()
	var n := maxi(8, roundi(length / STEP))
	var step := length / n
	var start := track.start_line_distance()
	_centre.resize(n)
	_right.resize(n)
	offsets.resize(n)
	for i in n:
		var d := start + i * step
		_centre[i] = track.point_at(d)
		var forward := track.direction_at(d)
		_right[i] = Vector3(-forward.z, 0.0, forward.x).normalized()
	_smooth(maxf(0.0, track.gate_half_width() - edge_gap))
	points.resize(n)
	for i in n:
		points[i] = _centre[i] + _right[i] * offsets[i]
	plan_speeds(corner, brake)


## A new line on the same points, with its own speeds. Much quicker than building one.
func copy() -> RacingLine:
	var other := RacingLine.new()
	other.points = points.duplicate()
	other.offsets = offsets.duplicate()
	other.speeds = speeds.duplicate()
	other.corner_accel = corner_accel
	other.brake_accel = brake_accel
	other._centre = _centre.duplicate()
	other._right = _right.duplicate()
	return other


func size() -> int:
	return points.size()


## Index of the line point nearest to a place. Looks near hint first, if given.
func nearest(where: Vector3, hint := -1) -> int:
	var n := size()
	var best := -1
	var best_d := INF
	if hint >= 0:
		for k in range(-6, 16):
			var i := posmod(hint + k, n)
			var d := points[i].distance_squared_to(where)
			if d < best_d:
				best_d = d
				best = i
		if best_d < 15.0 * 15.0:
			return best
	for i in n:
		var d := points[i].distance_squared_to(where)
		if d < best_d:
			best_d = d
			best = i
	return best


## Place on the line a distance ahead of point i, in metres. Blends between points.
func point_ahead(i: int, metres: float) -> Vector3:
	var f := metres / _step_length()
	var k := floori(f)
	return points[posmod(i + k, size())].lerp(points[posmod(i + k + 1, size())], f - k)


## Target speed a distance ahead of point i, in m/s.
func speed_ahead(i: int, metres: float) -> float:
	var f := metres / _step_length()
	var k := floori(f)
	return lerpf(speeds[posmod(i + k, size())], speeds[posmod(i + k + 1, size())], f - k)


## Driving direction at point i, flat.
func direction(i: int) -> Vector3:
	var d := points[(i + 1) % size()] - points[posmod(i - 1, size())]
	d.y = 0.0
	return d.normalized()


## Middle of the road beside point i.
func centre(i: int) -> Vector3:
	return _centre[posmod(i, size())]


## Flat unit vector across the road at point i, pointing right.
func right(i: int) -> Vector3:
	return _right[posmod(i, size())]


## Distance from point i to how far round the lap it is, in metres from the start line.
func distance_at(i: int) -> float:
	return i * _step_length()


## Bends the line inside the road, so it turns as gently as it can.
## Each pass moves every point towards the place that makes the bend through it and its
## neighbours smoothest, then keeps it on the road.
func _smooth(limit: float) -> void:
	var n := _centre.size()
	var p := _centre.duplicate()
	for pass_number in PASSES:
		for i in n:
			var target := (-p[posmod(i - 2, n)] + 4.0 * p[posmod(i - 1, n)]
					+ 4.0 * p[(i + 1) % n] - p[(i + 2) % n]) / 6.0
			var want := (target - _centre[i]).dot(_right[i])
			var o := clampf(lerpf(offsets[i], want, RELAX), -limit, limit)
			offsets[i] = o
			p[i] = _centre[i] + _right[i] * o


## Sets each point's speed: the fastest the tires can hold through the bend there,
## then lowered so there's room to brake for every slower point ahead.
## top: fastest speed anywhere, in m/s.
func plan_speeds(corner: float, brake: float, top := TOP_SPEED) -> void:
	corner_accel = corner
	brake_accel = brake
	var n := size()
	var step := _step_length()
	var bend := PackedFloat32Array()
	var rise := PackedFloat32Array()
	bend.resize(n)
	rise.resize(n)
	for i in n:
		bend[i] = _bend(points[posmod(i - 1, n)], points[i], points[(i + 1) % n])
		# Up-curve of the road: positive in a dip (more grip), negative over a crest (less).
		rise[i] = (points[posmod(i - 1, n)].y - 2.0 * points[i].y + points[(i + 1) % n].y) / (step * step)
	speeds.resize(n)
	for i in n:
		var k := (bend[posmod(i - 1, n)] + bend[i] + bend[(i + 1) % n]) / 3.0
		var dip := (rise[posmod(i - 1, n)] + rise[i] + rise[(i + 1) % n]) / 3.0
		# Grip grows with load: g plus the push from a dip. Solve v² k = grip (g + v² dip) / g.
		var mu := corner_accel / GRAVITY
		var below := k - mu * dip
		var v := top if below <= 0.0 else sqrt(corner_accel / below)
		speeds[i] = minf(v, top)
	# Braking: walk backwards round the lap twice so the wrap at the start line is covered.
	for j in range(2 * n - 1, -1, -1):
		var i := j % n
		var next := speeds[(i + 1) % n]
		# Less braking grip is left while the tires are also turning.
		var turning := minf(1.0, next * next * bend[i] / corner_accel)
		var a := brake_accel * sqrt(maxf(0.15, 1.0 - turning * turning))
		# Gravity helps braking uphill and works against it downhill.
		var grade := (points[(i + 1) % n].y - points[i].y) / step
		a = maxf(0.3 * a, a + GRAVITY * grade)
		speeds[i] = minf(speeds[i], sqrt(next * next + 2.0 * a * step))


func _step_length() -> float:
	var n := size()
	var total := 0.0
	if n == 0:
		return STEP
	if _cached_step <= 0.0:
		for i in n:
			total += points[i].distance_to(points[(i + 1) % n])
		_cached_step = total / n
	return _cached_step


## How sharply three points bend, flat: 1 / radius, in 1/m.
static func _bend(a: Vector3, b: Vector3, c: Vector3) -> float:
	var p := Vector2(a.x, a.z)
	var q := Vector2(b.x, b.z)
	var r := Vector2(c.x, c.z)
	var area2 := absf((q - p).cross(r - p))
	var product := p.distance_to(q) * q.distance_to(r) * r.distance_to(p)
	return 0.0 if product < 0.0001 else 2.0 * area2 / product
