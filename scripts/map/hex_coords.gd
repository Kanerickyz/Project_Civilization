class_name HexCoords
extends RefCounted
## 尖顶（pointy-top）轴坐标 q,r。有限盘：到中心立方距离 ≤ radius。


const NEIGHBOR_DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]


static func cube_distance(a: Vector2i, b: Vector2i) -> int:
	var aq := a.x
	var ar := a.y
	var as_ := -aq - ar
	var bq := b.x
	var br := b.y
	var bs := -bq - br
	return maxi(maxi(absi(aq - bq), absi(ar - br)), absi(as_ - bs))


static func in_radius(cell: Vector2i, radius: int) -> bool:
	return cube_distance(cell, Vector2i.ZERO) <= radius


static func cells_in_radius(radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		var r1 := maxi(-radius, -q - radius)
		var r2 := mini(radius, -q + radius)
		for r in range(r1, r2 + 1):
			out.append(Vector2i(q, r))
	return out


static func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in NEIGHBOR_DIRS:
		out.append(cell + d)
	return out


static func neighbors_in_radius(cell: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for n in neighbors(cell):
		if in_radius(n, radius):
			out.append(n)
	return out


## 尖顶六边中心像素（相对原点）。
static func axial_to_pixel(cell: Vector2i, hex_size: float) -> Vector2:
	var x := hex_size * (sqrt(3.0) * float(cell.x) + sqrt(3.0) / 2.0 * float(cell.y))
	var y := hex_size * (1.5 * float(cell.y))
	return Vector2(x, y)


static func pixel_to_axial(pixel: Vector2, hex_size: float) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * pixel.x - 1.0 / 3.0 * pixel.y) / hex_size
	var r := (2.0 / 3.0 * pixel.y) / hex_size
	return _axial_round(q, r)


static func _axial_round(fq: float, fr: float) -> Vector2i:
	var fx := fq
	var fz := fr
	var fy := -fx - fz
	var rx := roundi(fx)
	var ry := roundi(fy)
	var rz := roundi(fz)
	var x_diff := absf(rx - fx)
	var y_diff := absf(ry - fy)
	var z_diff := absf(rz - fz)
	if x_diff > y_diff and x_diff > z_diff:
		rx = -ry - rz
	elif y_diff > z_diff:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(rx, rz)


static func hex_corners(center: Vector2, hex_size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * float(i) - 30.0)
		pts.append(center + Vector2(hex_size * cos(angle), hex_size * sin(angle)))
	return pts
