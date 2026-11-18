class_name TacticalSandboxRoster
extends RefCounted

const TacticalBoardScript := preload("res://scripts/units/tactical_board.gd")
const TacticalUnitInstanceScript := preload("res://scripts/units/tactical_unit_instance.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const ClusterTerrainGeneratorScript := preload("res://scripts/map/cluster_terrain_generator.gd")
const GridMathScript := preload("res://scripts/units/grid_math.gd")

const PLAYER_UNIT_PATHS: Array[String] = [
	"res://resources/units/knight.tres",
	"res://resources/units/archer.tres",
	"res://resources/units/mini_pekka.tres",
	"res://resources/units/wardrum.tres",
	"res://resources/units/boomling.tres",
	"res://resources/units/assassin.tres",
	"res://resources/units/devman.tres",
]

## 敌方六狼骑兵（autochess id `rider` / 剪纸 unit_rider；各 max_hp=10）。
const OPPONENT_UNIT_PATH := "res://resources/units/rider.tres"
const ENEMY_SPAWN_COUNT := 6

## 测试用固定站位（全图可部署后仍保留确定性落点）。
const PLAYER_CELLS: Array[Vector2i] = [
	Vector2i(1, 2),
	Vector2i(1, 4),
	Vector2i(1, 6),
	Vector2i(2, 4),
	Vector2i(2, 6),
	Vector2i(2, 2),
	Vector2i(3, 3),
]

const OPPONENT_CELLS: Array[Vector2i] = [
	Vector2i(6, 2),
	Vector2i(6, 4),
	Vector2i(6, 6),
	Vector2i(5, 2),
	Vector2i(5, 4),
	Vector2i(5, 6),
]


## Headless / runner：固定站位 + 立刻生成敌方（便于断言）。
static func build_demo_board(width: int, height: int) -> TacticalBoard:
	var board: TacticalBoard = TacticalBoardScript.new()
	board.setup(width, height)
	var player_defs: Array[TacticalUnitDef] = _load_defs(PLAYER_UNIT_PATHS)
	var rider_def := _load_one_def(OPPONENT_UNIT_PATH)
	for i in player_defs.size():
		var p_cell: Vector2i = PLAYER_CELLS[i % PLAYER_CELLS.size()]
		# 避免固定表撞格：超出表长时向右错开。
		if i >= PLAYER_CELLS.size():
			p_cell = Vector2i(p_cell.x + 1, p_cell.y)
		board.add_unit(
			TacticalUnitInstanceScript.new(player_defs[i], TacticalFactionScript.Id.PLAYER, p_cell)
		)
	if rider_def != null:
		for i in OPPONENT_CELLS.size():
			board.add_unit(
				TacticalUnitInstanceScript.new(
					rider_def, TacticalFactionScript.Id.OPPONENT, OPPONENT_CELLS[i]
				)
			)
	return board


## 对战开局：成簇地形 → 随机友方站位 → 敌潜在点；敌方单位开战时再生成。
static func build_board_for_config(config: BoardConfig, seed_value: int = -1) -> TacticalBoard:
	var board: TacticalBoard = TacticalBoardScript.new()
	board.setup(config.grid_width, config.grid_height)
	var gen: Dictionary = ClusterTerrainGeneratorScript.generate(
		config.grid_width, config.grid_height, seed_value
	)
	var map: MapData = gen["map"] as MapData
	board.set_terrain(map)
	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_place_players_random(board, rng)
	_roll_enemy_spawn_cells(board, rng, ENEMY_SPAWN_COUNT)
	return board


## 开战：按潜在点生成狼骑兵。
static func spawn_pending_enemies(board: TacticalBoard, seed_value: int = -1) -> int:
	if board == null:
		return 0
	var rider_def := _load_one_def(OPPONENT_UNIT_PATH)
	if rider_def == null:
		return 0
	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value ^ 0xA11CE
	else:
		rng.randomize()
	return board.spawn_enemies_from_potential(rider_def, rng)


static func _place_players_random(board: TacticalBoard, rng: RandomNumberGenerator) -> void:
	var player_defs: Array[TacticalUnitDef] = _load_defs(PLAYER_UNIT_PATHS)
	var used: Dictionary = {}
	for def in player_defs:
		var cell := _pick_random_passable_empty(board, used, rng)
		if cell.x < 0:
			push_warning("TacticalSandboxRoster: no cell for %s" % def.id)
			continue
		used[cell] = true
		board.add_unit(
			TacticalUnitInstanceScript.new(def, TacticalFactionScript.Id.PLAYER, cell)
		)


static func _roll_enemy_spawn_cells(
	board: TacticalBoard, rng: RandomNumberGenerator, count: int
) -> void:
	board.enemy_spawn_cells.clear()
	var used: Dictionary = {}
	for u in board.living_units():
		used[u.cell] = true
	for _i in range(count):
		var cell := _pick_random_passable_empty(board, used, rng)
		if cell.x < 0:
			break
		used[cell] = true
		board.enemy_spawn_cells.append(cell)


static func _pick_random_passable_empty(
	board: TacticalBoard, used: Dictionary, rng: RandomNumberGenerator
) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for gx in range(board.grid_width):
		for gy in range(board.grid_height):
			var cell := Vector2i(gx, gy)
			if not board.is_passable(cell):
				continue
			if used.has(cell):
				continue
			if board.unit_at(cell) != null:
				continue
			candidates.append(cell)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## 若初始落点不可通行（林/墙），挪到最近可通行空格（全图）。
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
	for gx in range(board.grid_width):
		for gy in range(board.grid_height):
			var cell := Vector2i(gx, gy)
			if not board.is_passable(cell):
				continue
			var occ := board.unit_at(cell)
			if occ != null and occ != unit:
				continue
			var d := GridMathScript.chebyshev(unit.cell, cell)
			if d < best_d:
				best_d = d
				best = cell
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
