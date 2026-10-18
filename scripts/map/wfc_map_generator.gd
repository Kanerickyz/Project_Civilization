class_name WfcMapGenerator
extends RefCounted
## 精简 WFC：整图预生成；海岸环 / 中心陆 / 邻接偏置提升可读性。


const Terrain := preload("res://scripts/map/terrain_type.gd")
const Hex := preload("res://scripts/map/hex_coords.gd")


var _allowed: Array # Array[Array[bool]] COUNT x COUNT
var _weights: PackedFloat32Array


func _init() -> void:
	_build_adjacency()
	_weights = PackedFloat32Array()
	_weights.resize(Terrain.COUNT)
	_weights[Terrain.Id.OCEAN] = 2.8
	_weights[Terrain.Id.BEACH] = 1.4
	_weights[Terrain.Id.GRASSLAND] = 4.2
	_weights[Terrain.Id.FOREST] = 2.6
	_weights[Terrain.Id.HILLS] = 1.7
	_weights[Terrain.Id.MOUNTAIN] = 0.85
	_weights[Terrain.Id.DESERT] = 1.4
	_weights[Terrain.Id.MARSH] = 0.95
	_weights[Terrain.Id.SNOW] = 0.8


## 返回 Dictionary Vector2i -> TerrainType.Id；失败返回空 Dictionary。
func generate(radius: int, rng: RandomNumberGenerator, max_retries: int) -> Dictionary:
	var cells := Hex.cells_in_radius(radius)
	var start_cells: Array[Vector2i] = []
	for c in Hex.cells_in_radius(mini(1, radius)):
		start_cells.append(c)
	for attempt in max_retries:
		var seed_offset := rng.randi()
		var result := _run_once(cells, start_cells, radius, rng, seed_offset)
		if result.is_empty():
			continue
		if _passes_readability(result, start_cells, radius):
			return result
	push_error("WfcMapGenerator: failed after %d retries (radius=%d)" % [max_retries, radius])
	return {}


func _run_once(
	cells: Array[Vector2i],
	start_cells: Array[Vector2i],
	radius: int,
	rng: RandomNumberGenerator,
	_seed_offset: int
) -> Dictionary:
	var domains: Dictionary = {} # Vector2i -> PackedByteArray of allowed ids
	for cell in cells:
		domains[cell] = _domain_for_distance(Hex.cube_distance(cell, Vector2i.ZERO), radius)
	for cell in start_cells:
		domains[cell] = _start_land_domain()
	# 先把中心簇陆地约束向外传播，降低后期矛盾。
	for cell in start_cells:
		if not _propagate(cell, domains, {}, radius):
			return {}

	var collapsed: Dictionary = {} # Vector2i -> int
	while collapsed.size() < cells.size():
		var pick: Variant = _select_min_entropy(domains, collapsed, rng)
		if pick == null:
			return {}
		var cell: Vector2i = pick as Vector2i
		var domain: PackedByteArray = domains[cell] as PackedByteArray
		if domain.is_empty():
			return {}
		var choice: int = _weighted_pick(domain, cell, radius, rng)
		if choice < 0:
			return {}
		collapsed[cell] = choice
		domains[cell] = PackedByteArray([choice])
		if not _propagate(cell, domains, collapsed, radius):
			return {}
	return collapsed


## 最外圈偏海洋、次外偏海滩，内陆全域；提升海岸可读性。
func _domain_for_distance(dist: int, radius: int) -> PackedByteArray:
	if dist >= radius:
		return PackedByteArray([Terrain.Id.OCEAN, Terrain.Id.BEACH])
	if dist == radius - 1:
		return PackedByteArray([
			Terrain.Id.OCEAN,
			Terrain.Id.BEACH,
			Terrain.Id.GRASSLAND,
			Terrain.Id.DESERT,
			Terrain.Id.MARSH,
			Terrain.Id.FOREST,
		])
	return _full_domain()


func _passes_readability(result: Dictionary, start_cells: Array[Vector2i], radius: int) -> bool:
	for cell in start_cells:
		if not Terrain.is_start_land(int(result[cell])):
			return false
	# 中心簇陆地须彼此联通（本切片仅检查开局簇）。
	if not _cluster_connected_land(result, start_cells):
		return false
	# 外圈以海为主：至少一半为海洋。
	var rim := 0
	var ocean_rim := 0
	for cell in result.keys():
		var c: Vector2i = cell as Vector2i
		if Hex.cube_distance(c, Vector2i.ZERO) != radius:
			continue
		rim += 1
		if int(result[c]) == Terrain.Id.OCEAN:
			ocean_rim += 1
	if rim > 0 and float(ocean_rim) / float(rim) < 0.5:
		return false
	return true


func _cluster_connected_land(result: Dictionary, start_cells: Array[Vector2i]) -> bool:
	if start_cells.is_empty():
		return true
	var need: Dictionary = {}
	for c in start_cells:
		need[c] = true
	var queue: Array[Vector2i] = [start_cells[0]]
	var seen: Dictionary = {start_cells[0]: true}
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front() as Vector2i
		for n in Hex.neighbors(cell):
			if not need.has(n) or seen.has(n):
				continue
			if not Terrain.is_start_land(int(result[n])):
				continue
			seen[n] = true
			queue.append(n)
	return seen.size() == need.size()


func _propagate(start: Vector2i, domains: Dictionary, collapsed: Dictionary, radius: int) -> bool:
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front() as Vector2i
		var cell_domain: PackedByteArray = domains[cell] as PackedByteArray
		for n in Hex.neighbors_in_radius(cell, radius):
			if collapsed.has(n):
				continue
			var before: PackedByteArray = domains[n] as PackedByteArray
			var after: PackedByteArray = _filter_by_neighbor(before, cell_domain)
			if after.size() == before.size() and _same_bytes(after, before):
				continue
			if after.is_empty():
				return false
			domains[n] = after
			queue.append(n)
	return true


func _filter_by_neighbor(domain: PackedByteArray, neighbor_domain: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	for tid in domain:
		var ok := false
		for nid in neighbor_domain:
			if _allowed[tid][nid]:
				ok = true
				break
		if ok:
			out.append(tid)
	return out


func _select_min_entropy(domains: Dictionary, collapsed: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var best: Array[Vector2i] = []
	var best_n := 999
	for cell in domains.keys():
		if collapsed.has(cell):
			continue
		var n: int = (domains[cell] as PackedByteArray).size()
		if n <= 0:
			return null
		if n < best_n:
			best_n = n
			best = [cell]
		elif n == best_n:
			best.append(cell)
	if best.is_empty():
		return null
	return best[rng.randi_range(0, best.size() - 1)]


func _weighted_pick(domain: PackedByteArray, cell: Vector2i, radius: int, rng: RandomNumberGenerator) -> int:
	var dist := Hex.cube_distance(cell, Vector2i.ZERO)
	var total := 0.0
	var weighted: Array[float] = []
	weighted.resize(domain.size())
	for i in domain.size():
		var tid: int = domain[i]
		var w := _weights[tid] * _distance_bias(tid, dist, radius)
		weighted[i] = w
		total += w
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	var acc := 0.0
	for i in domain.size():
		acc += weighted[i]
		if roll <= acc:
			return domain[i]
	return domain[domain.size() - 1]


func _distance_bias(tid: int, dist: int, radius: int) -> float:
	if dist >= radius:
		return 3.2 if tid == Terrain.Id.OCEAN else (1.0 if tid == Terrain.Id.BEACH else 0.05)
	if dist == radius - 1:
		match tid:
			Terrain.Id.BEACH:
				return 2.4
			Terrain.Id.OCEAN:
				return 1.6
			Terrain.Id.MOUNTAIN:
				return 0.15
			_:
				return 0.9
	if dist <= 2:
		match tid:
			Terrain.Id.GRASSLAND, Terrain.Id.FOREST, Terrain.Id.HILLS:
				return 1.35
			Terrain.Id.OCEAN, Terrain.Id.BEACH:
				return 0.2
			Terrain.Id.MOUNTAIN:
				return 0.55
			_:
				return 1.0
	if tid == Terrain.Id.MOUNTAIN and dist < radius - 2:
		return 1.15
	return 1.0


func _full_domain() -> PackedByteArray:
	var out := PackedByteArray()
	for i in Terrain.COUNT:
		out.append(i)
	return out


func _start_land_domain() -> PackedByteArray:
	var out := PackedByteArray()
	for i in Terrain.COUNT:
		if Terrain.is_start_land(i):
			out.append(i)
	return out


func _same_bytes(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


func _build_adjacency() -> void:
	_allowed = []
	for _i in Terrain.COUNT:
		var row: Array = []
		row.resize(Terrain.COUNT)
		row.fill(false)
		_allowed.append(row)

	# 对称邻接：海—滩—陆主链 + 文明式内陆过渡（非全集）。
	_link_group([
		Terrain.Id.OCEAN, Terrain.Id.OCEAN,
		Terrain.Id.OCEAN, Terrain.Id.BEACH,
	])
	_link_group([
		Terrain.Id.BEACH, Terrain.Id.BEACH,
		Terrain.Id.BEACH, Terrain.Id.GRASSLAND,
		Terrain.Id.BEACH, Terrain.Id.DESERT,
		Terrain.Id.BEACH, Terrain.Id.FOREST,
		Terrain.Id.BEACH, Terrain.Id.MARSH,
	])
	_link_group([
		Terrain.Id.GRASSLAND, Terrain.Id.GRASSLAND,
		Terrain.Id.GRASSLAND, Terrain.Id.FOREST,
		Terrain.Id.GRASSLAND, Terrain.Id.HILLS,
		Terrain.Id.GRASSLAND, Terrain.Id.DESERT,
		Terrain.Id.GRASSLAND, Terrain.Id.MARSH,
		Terrain.Id.GRASSLAND, Terrain.Id.SNOW,
	])
	_link_group([
		Terrain.Id.FOREST, Terrain.Id.FOREST,
		Terrain.Id.FOREST, Terrain.Id.HILLS,
		Terrain.Id.FOREST, Terrain.Id.MARSH,
		Terrain.Id.FOREST, Terrain.Id.SNOW,
	])
	_link_group([
		Terrain.Id.HILLS, Terrain.Id.HILLS,
		Terrain.Id.HILLS, Terrain.Id.MOUNTAIN,
		Terrain.Id.HILLS, Terrain.Id.DESERT,
		Terrain.Id.HILLS, Terrain.Id.SNOW,
	])
	_link_group([
		Terrain.Id.MOUNTAIN, Terrain.Id.MOUNTAIN,
		Terrain.Id.MOUNTAIN, Terrain.Id.SNOW,
	])
	_link_group([
		Terrain.Id.DESERT, Terrain.Id.DESERT,
		Terrain.Id.DESERT, Terrain.Id.HILLS,
	])
	_link_group([
		Terrain.Id.MARSH, Terrain.Id.MARSH,
		Terrain.Id.MARSH, Terrain.Id.FOREST,
	])
	_link_group([
		Terrain.Id.SNOW, Terrain.Id.SNOW,
		Terrain.Id.SNOW, Terrain.Id.HILLS,
	])


func _link(a: int, b: int) -> void:
	_allowed[a][b] = true
	_allowed[b][a] = true


func _link_group(pairs: Array) -> void:
	var i := 0
	while i + 1 < pairs.size():
		_link(int(pairs[i]), int(pairs[i + 1]))
		i += 2
