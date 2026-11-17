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
]

## 敌方六狼骑兵（autochess id `rider` / 剪纸 unit_rider；各 max_hp=10）。
const OPPONENT_UNIT_PATH := "res://resources/units/rider.tres"

const PLAYER_CELLS: Array[Vector2i] = [
	Vector2i(1, 2),
	Vector2i(1, 4),
	Vector2i(1, 6),
	Vector2i(2, 4),
	Vector2i(2, 6),
]

const OPPONENT_CELLS: Array[Vector2i] = [
	Vector2i(6, 2),
	Vector2i(6, 4),
	Vector2i(6, 6),
	Vector2i(5, 2),
	Vector2i(5, 4),
	Vector2i(5, 6),
]


static func build_demo_board(width: int, height: int) -> TacticalBoard:
	var board: TacticalBoard = TacticalBoardScript.new()
	board.setup(width, height)
	var player_defs: Array[TacticalUnitDef] = _load_defs(PLAYER_UNIT_PATHS)
	var rider_def := _load_one_def(OPPONENT_UNIT_PATH)
	for i in player_defs.size():
		var p_cell: Vector2i = PLAYER_CELLS[i]
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


## 对战开局：按 config 尺寸布阵，内部 seed 成簇铺湖/林（不保护部署区）。
static func build_board_for_config(config: BoardConfig, seed_value: int = -1) -> TacticalBoard:
	var board := build_demo_board(config.grid_width, config.grid_height)
	var gen: Dictionary = ClusterTerrainGeneratorScript.generate(
		config.grid_width, config.grid_height, seed_value
	)
	var map: MapData = gen["map"] as MapData
	board.set_terrain(map)
	_relocate_units_off_impassable(board)
	return board


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
	for gx in range(board.grid_width):
		for gy in range(board.grid_height):
			var cell := Vector2i(gx, gy)
			if not board.is_passable(cell):
				continue
			var occ := board.unit_at(cell)
			if occ != null and occ != unit:
				continue
			if prefer_left and cell.x >= int(board.grid_width / 2):
				continue
			if not prefer_left and cell.x < int(board.grid_width / 2):
				continue
			var d := GridMathScript.chebyshev(unit.cell, cell)
			if d < best_d:
				best_d = d
				best = cell
	if best.x >= 0:
		return best
	# 同侧无空位时放开半盘限制。
	for gx in range(board.grid_width):
		for gy in range(board.grid_height):
			var cell2 := Vector2i(gx, gy)
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
