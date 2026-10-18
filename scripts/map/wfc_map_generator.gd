class_name WfcMapGenerator
extends RefCounted
## 精简 WFC：整图预生成；邻接按常见海—滩—陆与文明式大类约束。


const Terrain := preload("res://scripts/map/terrain_type.gd")
const Hex := preload("res://scripts/map/hex_coords.gd")


var _allowed: Array # Array[Array[bool]] COUNT x COUNT
var _weights: PackedFloat32Array


func _init() -> void:
	_build_adjacency()
	_weights = PackedFloat32Array()
	_weights.resize(Terrain.COUNT)
	_weights[Terrain.Id.OCEAN] = 3.0
	_weights[Terrain.Id.BEACH] = 1.2
	_weights[Terrain.Id.GRASSLAND] = 4.0
	_weights[Terrain.Id.FOREST] = 2.5
	_weights[Terrain.Id.HILLS] = 1.8
	_weights[Terrain.Id.MOUNTAIN] = 1.0
	_weights[Terrain.Id.DESERT] = 1.5
	_weights[Terrain.Id.MARSH] = 1.0
	_weights[Terrain.Id.SNOW] = 0.9


## 返回 Dictionary Vector2i -> TerrainType.Id；失败返回空 Dictionary。
func generate(radius: int, rng: RandomNumberGenerator, max_retries: int) -> Dictionary:
	var cells := Hex.cells_in_radius(radius)
	var start_cells: Array[Vector2i] = []
	for c in Hex.cells_in_radius(mini(1, radius)):
		start_cells.append(c)
	for attempt in max_retries:
		var seed_offset := rng.randi()
		var result := _run_once(cells, start_cells, radius, rng, seed_offset)
		if not result.is_empty():
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
		domains[cell] = _full_domain()
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
		var choice: int = _weighted_pick(domain, rng)
		if choice < 0:
			return {}
		collapsed[cell] = choice
		domains[cell] = PackedByteArray([choice])
		if not _propagate(cell, domains, collapsed, radius):
			return {}
	return collapsed


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


func _weighted_pick(domain: PackedByteArray, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for tid in domain:
		total += _weights[tid]
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	var acc := 0.0
	for tid in domain:
		acc += _weights[tid]
		if roll <= acc:
			return tid
	return domain[domain.size() - 1]


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

	# 对称邻接：常见过渡 + 文明式大类（非全集）。
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
	])


func _link(a: int, b: int) -> void:
	_allowed[a][b] = true
	_allowed[b][a] = true


func _link_group(pairs: Array) -> void:
	var i := 0
	while i + 1 < pairs.size():
		_link(int(pairs[i]), int(pairs[i + 1]))
		i += 2
