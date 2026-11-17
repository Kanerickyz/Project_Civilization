class_name ClusterTerrainGenerator
extends RefCounted
## 对战开局：按内部 seed 成簇铺湖/林。湖、林占比各独立 0%–15%。不做 WFC。


const LAKE_ID := &"lake"
const FOREST_ID := &"forest"
const MIN_RATIO := 0.0
const MAX_RATIO := 0.15
## 新开一簇的概率（相对继续邻接生长）。
const NEW_CLUSTER_CHANCE := 0.28


## 生成 MapData；seed 固定则结果可复现。返回 { map, seed, lake_ratio, forest_ratio }。
static func generate(width: int, height: int, seed_value: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	var used_seed := seed_value
	if used_seed < 0:
		used_seed = int(Time.get_ticks_usec()) ^ int(Time.get_unix_time_from_system())
	rng.seed = used_seed as int
	var map := MapData.create_filled(width, height)
	var total := maxi(1, width * height)
	var lake_ratio := rng.randf_range(MIN_RATIO, MAX_RATIO)
	var forest_ratio := rng.randf_range(MIN_RATIO, MAX_RATIO)
	var lake_target := int(round(float(total) * lake_ratio))
	var forest_target := int(round(float(total) * forest_ratio))
	_place_clusters(map, LAKE_ID, lake_target, rng)
	_place_clusters(map, FOREST_ID, forest_target, rng)
	return {
		"map": map,
		"seed": used_seed,
		"lake_ratio": lake_ratio,
		"forest_ratio": forest_ratio,
		"lake_count": _count_id(map, LAKE_ID),
		"forest_count": _count_id(map, FOREST_ID),
	}


static func generate_map(width: int, height: int, seed_value: int = -1) -> MapData:
	return generate(width, height, seed_value)["map"] as MapData


static func _place_clusters(
	map: MapData, terrain_id: StringName, target: int, rng: RandomNumberGenerator
) -> void:
	if target <= 0:
		return
	var placed := 0
	var painted: Array[Vector2i] = []
	while placed < target:
		var cell := Vector2i(-1, -1)
		var open_new := painted.is_empty() or rng.randf() < NEW_CLUSTER_CHANCE
		if not open_new:
			cell = _pick_growth_cell(map, painted, rng)
		if cell.x < 0:
			cell = _pick_random_grass(map, rng)
		if cell.x < 0:
			break
		map.set_cell_vec(cell, terrain_id)
		painted.append(cell)
		placed += 1


static func _pick_growth_cell(
	map: MapData, painted: Array[Vector2i], rng: RandomNumberGenerator
) -> Vector2i:
	if painted.is_empty():
		return Vector2i(-1, -1)
	# 多次尝试：随机已有格的 8 邻空草。
	for _i in range(maxi(8, painted.size() * 2)):
		var base: Vector2i = painted[rng.randi_range(0, painted.size() - 1)]
		var offsets: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
		]
		var start := rng.randi_range(0, offsets.size() - 1)
		for j in range(offsets.size()):
			var n: Vector2i = base + offsets[(start + j) % offsets.size()]
			if map.in_bounds(n.x, n.y) and map.get_cell_vec(n) == map.catalog().default_id:
				return n
	return Vector2i(-1, -1)


static func _pick_random_grass(map: MapData, rng: RandomNumberGenerator) -> Vector2i:
	var grass: Array[Vector2i] = []
	var def := map.catalog().default_id
	for y in range(map.height):
		for x in range(map.width):
			var c := Vector2i(x, y)
			if map.get_cell_vec(c) == def:
				grass.append(c)
	if grass.is_empty():
		return Vector2i(-1, -1)
	return grass[rng.randi_range(0, grass.size() - 1)]


static func _count_id(map: MapData, terrain_id: StringName) -> int:
	var n := 0
	for y in range(map.height):
		for x in range(map.width):
			if map.get_cell(x, y) == terrain_id:
				n += 1
	return n
