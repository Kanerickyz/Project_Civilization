class_name GridMath
extends RefCounted


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func in_bounds(cell: Vector2i, width: int, height: int) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


## 格线中间格（不含起终点）。用于树林挡攻击等视线判定。
static func cells_between(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dx := to.x - from.x
	var dy := to.y - from.y
	var steps := maxi(absi(dx), absi(dy))
	if steps <= 1:
		return out
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var cx := int(round(float(from.x) + float(dx) * t))
		var cy := int(round(float(from.y) + float(dy) * t))
		var cell := Vector2i(cx, cy)
		if cell == from or cell == to:
			continue
		if out.is_empty() or out[out.size() - 1] != cell:
			out.append(cell)
	return out
