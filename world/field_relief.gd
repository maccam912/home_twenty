extends RefCounted

const Route = preload("res://world/route.gd")
const BLEND_DISTANCE := 128.0
const CELL := 256.0
static var _pads: Dictionary = {}


# Long, low glacial ridges with smaller swells crossing the grain. Ease the
# fields down to the surveyed grade at road cuts and around farm foundations.
static func height_at(x: float, z: float) -> float:
	if _pads.is_empty():
		_index_grade()
	var point := Vector2(x, z)
	var distance := BLEND_DISTANCE
	for pad: Rect2 in _pads.get(Vector2i(floori(x / CELL), floori(z / CELL)), []):
		distance = minf(distance, point.distance_to(point.clamp(pad.position, pad.end)))
		if distance == 0.0:
			return 0.0
	var ridge := sin(.0052 * x + .0037 * z + 1.5 * sin(.0023 * z))
	var swells := sin(.0086 * z - .0038 * x + .9) + .6 * sin(.0094 * x + .0018 * z)
	return (7.0 + 8.3 * ridge + 3.2 * swells) * smoothstep(0.0, BLEND_DISTANCE, distance)


static func _index_grade() -> void:
	for road: Dictionary in Route.ROADS:
		var line := Rect2(road.a, Vector2.ZERO).expand(road.b)
		_add_pad(line.grow(18.0))
	for site: Dictionary in Route.SITES.values():
		var drive := Rect2(site.mouth, Vector2.ZERO).expand(site.yard)
		_add_pad(drive.grow(16.0))
		_add_pad(Rect2(site.yard, Vector2.ZERO).grow(51.0))
	for mark: Dictionary in Route.LANDMARKS:
		_add_pad(Rect2(mark.position, Vector2.ZERO).grow(25.0))
	# Outbuildings and field frames outside the contract yards.
	_add_pad(Rect2(-133, Route.HOME_Z - 45, 134, 75))
	_add_pad(Rect2(122, Route.BECK_Z - 50, 70, 65))
	_add_pad(Rect2(32, Route.COOP_Z - 64, 84, 38))
	_add_pad(Rect2(-273, -1170, 43, 41))
	_add_pad(Rect2(284, -701, 56, 36))


static func _add_pad(pad: Rect2) -> void:
	var reach := pad.grow(BLEND_DISTANCE)
	var first := Vector2i((reach.position / CELL).floor())
	var last := Vector2i((reach.end / CELL).floor())
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, z)
			if not _pads.has(cell):
				_pads[cell] = []
			_pads[cell].append(pad)
