class_name TacticalSandboxRoster
extends RefCounted

const TacticalBoardScript := preload("res://scripts/units/tactical_board.gd")
const TacticalUnitInstanceScript := preload("res://scripts/units/tactical_unit_instance.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const ClusterTerrainGeneratorScript := preload("res://scripts/map/cluster_terrain_generator.gd")
const BoardEdgeShapeScript := preload("res://scripts/map/board_edge_shape.gd")
const GridMathScript := preload("res://scripts/units/grid_math.gd")

const PLAYER_UNIT_PATHS: Array[String] = [
	"res://resources/units/knight.tres",
	"res://resources/units/archer.tres",
	"res://resources/units/mini_pekka.tres",
	"res://resources/units/wardrum.tres",
	"res://resources/units/boomling.tres",
	"res://resources/units/healer.tres",
]

## 敌人配置池：关卡从中随机抽一套。Headless/demo 固定配置 A。
const ENEMY_CONFIG_POOL_PATHS: Array[String] = [
	"res://resources/enemies/enemy_config_a.tres",
	"res://resources/enemies/enemy_config_b.tres",
]
const DEMO_ENEMY_CONFIG_PATH := "res://resources/enemies/enemy_config_a.tres"


## Headless / runner：固定站位 + 配置 A（六狼骑兵，便于断言）。
static func build_demo_board(width: int, height: int) -> TacticalBoard:
	var board: TacticalBoard = TacticalBoardScript.new()
	board.setup(width, height)
	var player_defs: Array[TacticalUnitDef] = _load_defs(PLAYER_UNIT_PATHS)
	var player_cells := _demo_side_cells(width, height, true, player_defs.size())
	for i in player_defs.size():
		var p_cell: Vector2i = player_cells[i]
		board.add_unit(
			TacticalUnitInstanceScript.new(player_defs[i], TacticalFactionScript.Id.PLAYER, p_cell)
		)
	var config := _load_enemy_config(DEMO_ENEMY_CONFIG_PATH)
	_place_enemies_from_config_demo(board, width, height, config)
	return board


## 对战开局：成簇地形 → 左半随机友方 + 右半从敌人配置池随机一套。
static func build_board_for_config(config: BoardConfig, seed_value: int = -1) -> TacticalBoard:
	var board: TacticalBoard = TacticalBoardScript.new()
	board.setup(config.grid_width, config.grid_height)
	var gen: Dictionary = ClusterTerrainGeneratorScript.generate(
		config.grid_width, config.grid_height, seed_value
	)
	var map: MapData = gen["map"] as MapData
	BoardEdgeShapeScript.apply_to_map(map)
	board.set_terrain(map)
	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_place_players_random(board, rng)
	var enemy_cfg := pick_enemy_config(rng)
	_place_enemies_from_config(board, rng, enemy_cfg)
	_relocate_units_off_impassable(board)
	return board


## 从配置池随机抽一套；池空时回退配置 A。
static func pick_enemy_config(rng: RandomNumberGenerator = null) -> TacticalEnemyConfig:
	var local_rng := rng
	if local_rng == null:
		local_rng = RandomNumberGenerator.new()
		local_rng.randomize()
	var pool: Array[TacticalEnemyConfig] = []
	for path in ENEMY_CONFIG_POOL_PATHS:
		var cfg := _load_enemy_config(path)
		if cfg != null:
			pool.append(cfg)
	if pool.is_empty():
		return _load_enemy_config(DEMO_ENEMY_CONFIG_PATH)
	return pool[local_rng.randi_range(0, pool.size() - 1)]


## 左半 / 右半演示站位：靠各自外缘列，中间留空，减少测试叠格/误邻。
static func _demo_side_cells(
	width: int, height: int, left_side: bool, count: int
) -> Array[Vector2i]:
	var mid := int(width / 2)
	var primary_x: int
	var secondary_x: int
	if left_side:
		primary_x = 1 if mid > 1 else 0
		secondary_x = 0
	else:
		primary_x = maxi(mid, width - 2)
		secondary_x = width - 1
	var cells: Array[Vector2i] = []
	var y := 1 if height > 2 else 0
	var use_primary := true
	var guard := 0
	while cells.size() < count and guard < width * height * 4:
		guard += 1
		var x := primary_x if use_primary else secondary_x
		var cell := Vector2i(x, y % maxi(1, height))
		var clash := false
		for existing in cells:
			if existing == cell:
				clash = true
				break
		if not clash:
			cells.append(cell)
		use_primary = not use_primary
		if use_primary:
			y += 1
			if y >= height:
				y = 0
	return cells


static func _place_players_random(board: TacticalBoard, rng: RandomNumberGenerator) -> void:
	var player_defs: Array[TacticalUnitDef] = _load_defs(PLAYER_UNIT_PATHS)
	var used: Dictionary = {}
	for def in player_defs:
		var cell := _pick_random_passable_empty(board, used, rng, true)
		if cell.x < 0:
			push_warning("TacticalSandboxRoster: no cell for %s" % def.id)
			continue
		used[cell] = true
		board.add_unit(
			TacticalUnitInstanceScript.new(def, TacticalFactionScript.Id.PLAYER, cell)
		)


static func _place_enemies_from_config(
	board: TacticalBoard, rng: RandomNumberGenerator, config: TacticalEnemyConfig
) -> void:
	if config == null:
		return
	var used: Dictionary = {}
	for u in board.living_units():
		used[u.cell] = true
	for entry in config.spawn_entries:
		if entry == null or entry.unit_def == null or entry.count <= 0:
			continue
		for _i in range(entry.count):
			var cell := _pick_random_passable_empty(board, used, rng, false)
			if cell.x < 0:
				break
			used[cell] = true
			board.add_unit(
				TacticalUnitInstanceScript.new(
					entry.unit_def, TacticalFactionScript.Id.OPPONENT, cell
				)
			)


static func _place_enemies_from_config_demo(
	board: TacticalBoard, width: int, height: int, config: TacticalEnemyConfig
) -> void:
	if config == null:
		return
	var total := 0
	for entry in config.spawn_entries:
		if entry != null and entry.count > 0:
			total += entry.count
	var cells := _demo_side_cells(width, height, false, total)
	var idx := 0
	for entry in config.spawn_entries:
		if entry == null or entry.unit_def == null or entry.count <= 0:
			continue
		for _i in range(entry.count):
			if idx >= cells.size():
				return
			board.add_unit(
				TacticalUnitInstanceScript.new(
					entry.unit_def, TacticalFactionScript.Id.OPPONENT, cells[idx]
				)
			)
			idx += 1


## prefer_left=true → 左半；false → 右半；同侧无格时放开半盘。
static func _pick_random_passable_empty(
	board: TacticalBoard,
	used: Dictionary,
	rng: RandomNumberGenerator,
	prefer_left: bool
) -> Vector2i:
	var mid := int(board.grid_width / 2)
	var candidates: Array[Vector2i] = []
	for gx in range(board.grid_width):
		for gy in range(board.grid_height):
			var cell := Vector2i(gx, gy)
			if prefer_left and cell.x >= mid:
				continue
			if not prefer_left and cell.x < mid:
				continue
			if not board.is_passable(cell):
				continue
			if used.has(cell):
				continue
			if board.unit_at(cell) != null:
				continue
			candidates.append(cell)
	if candidates.is_empty():
		for gx2 in range(board.grid_width):
			for gy2 in range(board.grid_height):
				var cell2 := Vector2i(gx2, gy2)
				if not board.is_passable(cell2):
					continue
				if used.has(cell2):
					continue
				if board.unit_at(cell2) != null:
					continue
				candidates.append(cell2)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## 若初始落点不可通行（林/墙），挪到同侧最近可通行空格。
static func _relocate_units_off_impassable(board: TacticalBoard) -> void:
	for u in board.units:
		if u == null or not u.is_alive():
			continue
		if board.is_passable(u.cell) and board.unit_at(u.cell) == u:
			continue
		var dest := _nearest_passable_empty(board, u)
		if dest.x >= 0:
			u.cell = dest


static func _nearest_passable_empty(board: TacticalBoard, unit: TacticalUnitInstance) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 999999
	var prefer_left := unit.faction == TacticalFactionScript.Id.PLAYER
	var mid := int(board.grid_width / 2)
	for gx in range(board.grid_width):
		for gy in range(board.grid_height):
			var cell := Vector2i(gx, gy)
			if not board.is_passable(cell):
				continue
			var occ := board.unit_at(cell)
			if occ != null and occ != unit:
				continue
			if prefer_left and cell.x >= mid:
				continue
			if not prefer_left and cell.x < mid:
				continue
			var d := GridMathScript.chebyshev(unit.cell, cell)
			if d < best_d:
				best_d = d
				best = cell
	if best.x >= 0:
		return best
	# 同侧无空位时放开半盘限制。
	for gx2 in range(board.grid_width):
		for gy2 in range(board.grid_height):
			var cell2 := Vector2i(gx2, gy2)
			if not board.is_passable(cell2):
				continue
			var occ2 := board.unit_at(cell2)
			if occ2 != null and occ2 != unit:
				continue
			var d2 := GridMathScript.chebyshev(unit.cell, cell2)
			if d2 < best_d:
				best_d = d2
				best = cell2
	return best


static func _load_defs(paths: Array[String]) -> Array[TacticalUnitDef]:
	var out: Array[TacticalUnitDef] = []
	for path in paths:
		var loaded := _load_one_def(path)
		if loaded != null:
			out.append(loaded)
	return out


static func _load_one_def(path: String) -> TacticalUnitDef:
	var loaded := load(path)
	if loaded is TacticalUnitDef:
		return loaded as TacticalUnitDef
	push_warning("TacticalSandboxRoster: missing %s" % path)
	return null


static func _load_enemy_config(path: String) -> TacticalEnemyConfig:
	var loaded := load(path)
	if loaded is TacticalEnemyConfig:
		return loaded as TacticalEnemyConfig
	push_warning("TacticalSandboxRoster: missing enemy config %s" % path)
	return null
