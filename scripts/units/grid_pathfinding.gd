class_name GridPathfinding
extends RefCounted
## 8 邻接最短路（每步代价 1）。不可通行格不进入；斜走一步时两个正交相邻格都须可通行（禁止斜穿墙角）。
## 无不可通行格时，路径距离等于切比雪夫距离。

const UNREACHABLE := -1

const _DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]


## 从 origin 出发的路径距离表（Vector2i -> int）。passable: func(Vector2i) -> bool，须对越界返回 false。
## max_cost < 0 表示不限。origin 自身距离为 0，即使其不可通行。
static func distances_from(origin: Vector2i, passable: Callable, max_cost: int = -1) -> Dictionary:
	var dist: Dictionary = {origin: 0}
	var queue: Array[Vector2i] = [origin]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var cur_d: int = dist[cur]
		if max_cost >= 0 and cur_d >= max_cost:
			continue
		for d in _DIRS:
			var nxt := cur + d
			if dist.has(nxt):
				continue
			if not can_step(cur, d, passable):
				continue
			dist[nxt] = cur_d + 1
			queue.append(nxt)
	return dist


static func can_step(from: Vector2i, dir: Vector2i, passable: Callable) -> bool:
	if not passable.call(from + dir):
		return false
	if dir.x != 0 and dir.y != 0:
		if not passable.call(from + Vector2i(dir.x, 0)):
			return false
		if not passable.call(from + Vector2i(0, dir.y)):
			return false
	return true


## 不可达或超出 max_cost 时返回 UNREACHABLE。
static func path_distance(a: Vector2i, b: Vector2i, passable: Callable, max_cost: int = -1) -> int:
	if a == b:
		return 0
	var dist := distances_from(a, passable, max_cost)
	return int(dist.get(b, UNREACHABLE))
