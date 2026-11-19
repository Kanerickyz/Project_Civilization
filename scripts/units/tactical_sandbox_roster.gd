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

## 敌方六狼骑兵（autochess id `rider` / 剪纸 unit_rider；各 max_hp=10）。
const OPPONENT_UNIT_PATH := "res://resources/units/rider.tres"
const ENEMY_SPAWN_COUNT := 6


## Headless / runner：固定站位 + 立刻生成敌方（便于断言）。
static func build_demo_board(width: int, height: int) -> TacticalBoard:
	var board: TacticalBoard = TacticalBoardScript.new()
	board.setup(width, height)
	var player_defs: Array[TacticalUnitDef] = _load_defs(PLAYER_UNIT_PATHS)
	var rider_def := _load_one_def(OPPONENT_UNIT_PATH)
	var player_cells := _demo_side_cells(width, height, true, player_defs.size())
	for i in player_defs.size():
		var p_cell: Vector2i = player_cells[i]
		board.add_unit(
			TacticalUnitInstanceScript.new(player_defs[i], TacticalFactionScript.Id.PLAYER, p_cell)
		)
	if rider_def != null:
		var opp_cells := _demo_side_cells(width, height, false, ENEMY_SPAWN_COUNT)
		for i in opp_cells.size():
			board.add_unit(
				TacticalUnitInstanceScript.new(
					rider_def, TacticalFactionScript.Id.OPPONENT, opp_cells[i]
				)
			)
	return board


## 对战开局：随机 10×8/8×10 → 成簇地形 → 随机边缘 void → 左半友方 + 右半狼骑。
## 会就地改写 config.grid_width/height 与 camera_ortho_size，供视图复用。
static func build_board_for_config(config: BoardConfig, seed_value: int = -1) -> TacticalBoard:
	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var size: Vector2i = BoardEdgeShapeScript.pick_battle_size(rng)
	if config != null:
		config.grid_width = size.x
		config.grid_height = size.y
		config.camera_ortho_size = BoardEdgeShapeScript.ortho_size_for(size.x, size.y)
	var board: TacticalBoard = TacticalBoardScript.new()
	board.setup(size.x, size.y)
	var gen: Dictionary = ClusterTerrainGeneratorScript.generate(size.x, size.y, int(rng.randi()))
	var map: MapData = gen["map"] as MapData
	BoardEdgeShapeScript.apply_to_map(map, rng)
	board.set_terrain(map)
	_place_players_random(board, rng)
	_place_enemies_random(board, rng, ENEMY_SPAWN_COUNT)
	_relocate_units_off_impassable(board)
	return board


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


static func _place_enemies_random(
	board: TacticalBoard, rng: RandomNumberGenerator, count: int
) -> void:
	var rider_def := _load_one_def(OPPONENT_UNIT_PATH)
	if rider_def == null:
		return
	var used: Dictionary = {}
	for u in board.living_units():
		used[u.cell] = true
	for _i in range(count):
		var cell := _pick_random_passable_empty(board, used, rng, false)
		if cell.x < 0:
			break
		used[cell] = true
		board.add_unit(
			TacticalUnitInstanceScript.new(rider_def, TacticalFactionScript.Id.OPPONENT, cell)
		)


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
