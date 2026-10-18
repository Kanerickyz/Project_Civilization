class_name HexMapModel
extends RefCounted
## 有限六边地图数据：地形表 + 分边战略雾。表现层只读本模型。


const Terrain := preload("res://scripts/map/terrain_type.gd")
const Hex := preload("res://scripts/map/hex_coords.gd")
const WfcMapGeneratorScript := preload("res://scripts/map/wfc_map_generator.gd")
const StrategicFogScript := preload("res://scripts/map/strategic_fog.gd")
const MapConfigScript := preload("res://scripts/map/map_config.gd")


signal changed

var config: MapConfig
var terrains: Dictionary = {} # Vector2i -> int (TerrainType.Id)
var fog: StrategicFog
var seed_used: int = 0
var generation_ok: bool = false


func _init(p_config: MapConfig = null) -> void:
	config = p_config if p_config != null else MapConfigScript.new()
	fog = StrategicFogScript.new()


func generate(map_seed: int = 0) -> bool:
	var rng := RandomNumberGenerator.new()
	if map_seed == 0:
		rng.randomize()
		seed_used = int(rng.seed)
	else:
		seed_used = map_seed
		rng.seed = map_seed
	var gen := WfcMapGeneratorScript.new()
	var result := gen.generate(config.map_radius, rng, config.wfc_max_retries)
	if result.is_empty():
		generation_ok = false
		terrains = _fallback_fill()
	else:
		generation_ok = true
		terrains = result
	fog.clear()
	var initial: Array[Vector2i] = []
	for cell in Hex.cells_in_radius(config.initial_reveal_radius):
		if Hex.in_radius(cell, config.map_radius):
			initial.append(cell)
	# 玩家开局揭开中心簇；对手雾分边另存，本切片对手不自动揭（可改）。
	fog.reveal_many(StrategicFog.Side.PLAYER, initial)
	changed.emit()
	return generation_ok


func terrain_at(cell: Vector2i) -> int:
	return int(terrains.get(cell, Terrain.Id.OCEAN))


func all_cells() -> Array[Vector2i]:
	return Hex.cells_in_radius(config.map_radius)


func try_player_reveal(cell: Vector2i) -> bool:
	if fog.try_reveal(StrategicFog.Side.PLAYER, cell, config.map_radius):
		changed.emit()
		return true
	return false


func player_revealed(cell: Vector2i) -> bool:
	return fog.is_revealed(StrategicFog.Side.PLAYER, cell)


func player_can_reveal(cell: Vector2i) -> bool:
	return fog.can_reveal(StrategicFog.Side.PLAYER, cell, config.map_radius)


## WFC 全失败时的可读回退：中心陆、外圈海（保证沙盘可玩）。
func _fallback_fill() -> Dictionary:
	var out: Dictionary = {}
	for cell in Hex.cells_in_radius(config.map_radius):
		var d := Hex.cube_distance(cell, Vector2i.ZERO)
		if d <= config.initial_reveal_radius:
			out[cell] = Terrain.Id.GRASSLAND
		elif d <= config.map_radius - 1:
			out[cell] = Terrain.Id.FOREST if d % 2 == 0 else Terrain.Id.HILLS
		else:
			out[cell] = Terrain.Id.OCEAN if d == config.map_radius else Terrain.Id.BEACH
	# 修正外圈：半径最外倾向海，次外滩。
	for cell in Hex.cells_in_radius(config.map_radius):
		var d := Hex.cube_distance(cell, Vector2i.ZERO)
		if d == config.map_radius:
			out[cell] = Terrain.Id.OCEAN
		elif d == config.map_radius - 1:
			out[cell] = Terrain.Id.BEACH
	return out
