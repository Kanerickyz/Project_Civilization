extends SceneTree
## 地块对移动/寻路的约束：城墙不可通行、绕路、禁止斜穿墙角、无墙时与旧链式切比雪夫语义一致、沙盘开局地图。

const TacticalBoardScript := preload("res://scripts/units/tactical_board.gd")
const TacticalSandboxRosterScript := preload("res://scripts/units/tactical_sandbox_roster.gd")
const TacticalUnitInstanceScript := preload("res://scripts/units/tactical_unit_instance.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const TacticalEnemyAiScript := preload("res://scripts/units/tactical_enemy_ai.gd")
const GridMathScript := preload("res://scripts/units/grid_math.gd")
const MapDataScript := preload("res://scripts/map/map_data.gd")

const WALL := &"wall_straight"
const SANDBOX_MAP_PATH := "res://resources/map/sandbox_battle_map.json"
const BOARD_CONFIG_PATH := "res://resources/map/board_config.tres"
const SANDBOX_WALLS: Array[Vector2i] = [
	Vector2i(1, 3), Vector2i(2, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(7, 3),
]


func _initialize() -> void:
	var tests: Array[Callable] = [
		_test_wall_not_reachable,
		_test_vertical_wall_detour,
		_test_full_wall_blocks_jump,
		_test_try_move_into_wall_and_bounds,
		_test_no_corner_cutting,
		_test_no_wall_matches_legacy,
		_test_sandbox_map_loads,
		_test_sandbox_board_walls,
		_test_map_size_mismatch_falls_back,
		_test_ai_respects_walls,
	]
	for t in tests:
		if not t.call():
			quit(1)
			return
	print("TERRAIN_MOVEMENT_OK")
	quit(0)


func _def(path: String) -> TacticalUnitDef:
	return load(path) as TacticalUnitDef


func _board_with(unit_path: String, cell: Vector2i, walls: Array[Vector2i]) -> TacticalBoard:
	var board: TacticalBoard = TacticalBoardScript.new()
	board.setup(10, 8)
	var cells: Dictionary = {}
	for w in walls:
		cells[w] = WALL
	board.set_terrain_cells(cells)
	board.add_unit(TacticalUnitInstanceScript.new(_def(unit_path), TacticalFactionScript.Id.PLAYER, cell))
	return board


func _column(x: int, y_from: int, y_to: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(y_from, y_to + 1):
		out.append(Vector2i(x, y))
	return out


func _test_wall_not_reachable() -> bool:
	var walls: Array[Vector2i] = [Vector2i(3, 2), Vector2i(2, 3)]
	var board := _board_with("res://resources/units/archer.tres", Vector2i(2, 2), walls)
	var archer := board.units[0]
	var moves := board.reachable_move_cells(archer)
	for w in walls:
		if w in moves:
			push_error("TerrainMove: wall %s must not be reachable" % w)
			return false
		if board.is_passable(w):
			push_error("TerrainMove: wall %s should be impassable" % w)
			return false
	if moves.is_empty():
		push_error("TerrainMove: archer should still have moves around walls")
		return false
	return true


func _test_vertical_wall_detour() -> bool:
	var walls := _column(3, 0, 5)
	var board := _board_with("res://resources/units/archer.tres", Vector2i(2, 2), walls)
	var archer := board.units[0]
	var target := Vector2i(4, 2)
	var cheb := GridMathScript.chebyshev(archer.cell, target)
	var path := board.path_distance(archer.cell, target)
	if path <= cheb:
		push_error("TerrainMove: wall should force detour (path %d, chebyshev %d)" % [path, cheb])
		return false
	if path != 10:
		push_error("TerrainMove: expected detour length 10 around x=3 wall, got %d" % path)
		return false
	if target in board.reachable_move_cells(archer):
		push_error("TerrainMove: detour beyond budget %d should be unreachable" % archer.remaining_move_budget)
		return false
	if board.try_move(archer, target):
		push_error("TerrainMove: try_move across wall within chebyshev range must fail")
		return false
	archer.remaining_move_budget = path
	if not (target in board.reachable_move_cells(archer)):
		push_error("TerrainMove: detour should be reachable with budget %d" % path)
		return false
	return true


func _test_full_wall_blocks_jump() -> bool:
	var board := _board_with("res://resources/units/archer.tres", Vector2i(2, 2), _column(3, 0, 7))
	var archer := board.units[0]
	archer.remaining_move_budget = 99
	if board.path_distance(archer.cell, Vector2i(4, 2)) != -1:
		push_error("TerrainMove: sealed wall should make far side unreachable")
		return false
	for c in board.reachable_move_cells(archer):
		if c.x >= 3:
			push_error("TerrainMove: reachable %s crosses sealed wall" % c)
			return false
	if board.try_move(archer, Vector2i(4, 2)) or board.try_move(archer, Vector2i(4, 3)):
		push_error("TerrainMove: jumping over wall must fail")
		return false
	if archer.cell != Vector2i(2, 2) or archer.remaining_move_budget != 99:
		push_error("TerrainMove: failed move must not change unit state")
		return false
	return true


func _test_try_move_into_wall_and_bounds() -> bool:
	var board := _board_with("res://resources/units/archer.tres", Vector2i(0, 0), [Vector2i(1, 0)])
	var archer := board.units[0]
	if board.try_move(archer, Vector2i(1, 0)):
		push_error("TerrainMove: moving into wall must fail")
		return false
	if board.try_move(archer, Vector2i(-1, 0)) or board.try_move(archer, Vector2i(0, -1)):
		push_error("TerrainMove: moving out of bounds must fail")
		return false
	if board.is_passable(Vector2i(-1, 0)) or board.is_passable(Vector2i(10, 0)):
		push_error("TerrainMove: out of bounds must be impassable")
		return false
	# (0,0)→(2,0)：墙在 (1,0)，禁斜穿墙角后须绕 4 步，超出单步 2。
	if board.path_distance(archer.cell, Vector2i(2, 0)) != 4 or board.try_move(archer, Vector2i(2, 0)):
		push_error("TerrainMove: single wall detour should cost 4 and exceed move_range")
		return false
	if not board.try_move(archer, Vector2i(1, 1)):
		push_error("TerrainMove: should route around wall corner to (1,1)")
		return false
	if archer.remaining_move_budget != archer.def.action_move_budget() - 2:
		push_error("TerrainMove: move should spend path distance")
		return false
	return true


func _test_no_corner_cutting() -> bool:
	# (2,2)->(3,3) 斜走须经过 (3,2) 与 (2,3)；(3,2) 是墙，只能绕 2 步。
	var walls: Array[Vector2i] = [Vector2i(3, 2)]
	var knight_board := _board_with("res://resources/units/knight.tres", Vector2i(2, 2), walls)
	var knight := knight_board.units[0]
	if knight_board.path_distance(knight.cell, Vector2i(3, 3)) != 2:
		push_error("TerrainMove: diagonal past wall corner should cost 2")
		return false
	if Vector2i(3, 3) in knight_board.reachable_move_cells(knight):
		push_error("TerrainMove: knight (range 1) must not cut wall corner")
		return false
	if knight_board.try_move(knight, Vector2i(3, 3)):
		push_error("TerrainMove: try_move cutting wall corner must fail")
		return false
	if knight_board.path_distance(knight.cell, Vector2i(3, 1)) != 2:
		push_error("TerrainMove: other diagonal touching wall (3,2) should also be blocked")
		return false
	if not knight_board.try_move(knight, Vector2i(1, 1)):
		push_error("TerrainMove: diagonal away from wall should still be allowed")
		return false
	var archer_board := _board_with("res://resources/units/archer.tres", Vector2i(2, 2), walls)
	var archer := archer_board.units[0]
	if not archer_board.try_move(archer, Vector2i(3, 3)):
		push_error("TerrainMove: archer (range 2) should go around corner")
		return false
	if archer.remaining_move_budget != archer.def.action_move_budget() - 2:
		push_error("TerrainMove: corner detour should cost 2")
		return false
	# 两面墙夹角：(0,0) 只剩斜向 (1,1)，且被墙角封住。
	var boxed := _board_with("res://resources/units/archer.tres", Vector2i(0, 0), [Vector2i(1, 0), Vector2i(0, 1)])
	if not boxed.reachable_move_cells(boxed.units[0]).is_empty():
		push_error("TerrainMove: unit boxed by wall corner should have no moves")
		return false
	return true


## 改动前的链式切比雪夫 BFS（含遍历顺序），用于无墙对照。
func _legacy_reachable(board: TacticalBoard, unit: TacticalUnitInstance) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if unit == null or not unit.is_alive() or unit.remaining_move_budget <= 0:
		return out
	var dist: Dictionary = {unit.cell: 0}
	var queue: Array[Vector2i] = [unit.cell]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var cur_d: int = dist[cur]
		for gx in range(board.grid_width):
			for gy in range(board.grid_height):
				var cell := Vector2i(gx, gy)
				if cell == cur:
					continue
				if board.unit_at(cell) != null:
					continue
				var step := GridMathScript.chebyshev(cur, cell)
				if step > unit.def.move_range:
					continue
				var nd := cur_d + step
				if nd > unit.remaining_move_budget:
					continue
				if dist.has(cell) and dist[cell] <= nd:
					continue
				dist[cell] = nd
				queue.append(cell)
				out.append(cell)
	return out


func _test_no_wall_matches_legacy() -> bool:
	var board := TacticalSandboxRosterScript.build_demo_board(10, 8)
	for budget_override in [-1, 1, 2, 3, 6]:
		for u in board.living_units():
			if budget_override >= 0:
				u.remaining_move_budget = budget_override
			var got := board.reachable_move_cells(u)
			var want := _legacy_reachable(board, u)
			if got != want:
				push_error("TerrainMove: no-wall reachable differs from legacy for %s budget %d" % [u.def.id, u.remaining_move_budget])
				return false
	var archer: TacticalUnitInstance = null
	for u in board.living_units():
		if u.faction == TacticalFactionScript.Id.PLAYER and u.def.id == "archer":
			archer = u
	archer.remaining_move_budget = archer.def.action_move_budget()
	var start := archer.cell
	var dest := start + Vector2i(2, 2)
	if not board.try_move(archer, dest) or archer.remaining_move_budget != archer.def.action_move_budget() - 2:
		push_error("TerrainMove: no-wall try_move should cost chebyshev")
		return false
	return true


func _test_sandbox_map_loads() -> bool:
	var map := MapDataScript.load_json_from_path(SANDBOX_MAP_PATH)
	if map == null or map.width != 8 or map.height != 8:
		push_error("TerrainMove: sandbox map should load as 8x8")
		return false
	for y in range(map.height):
		for x in range(map.width):
			var c := Vector2i(x, y)
			var want_wall := c in SANDBOX_WALLS
			if (map.get_cell_vec(c) == WALL) != want_wall or map.is_passable(c) == want_wall:
				push_error("TerrainMove: sandbox map cell %s wall=%s mismatch" % [c, want_wall])
				return false
	return true


func _test_sandbox_board_walls() -> bool:
	var cfg := load(BOARD_CONFIG_PATH) as BoardConfig
	if cfg == null or cfg.terrain_map_path != SANDBOX_MAP_PATH:
		push_error("TerrainMove: board_config should point at sandbox map")
		return false
	var board := TacticalSandboxRosterScript.build_board_for_config(cfg)
	for w in SANDBOX_WALLS:
		if board.is_passable(w):
			push_error("TerrainMove: sandbox board wall %s should be impassable" % w)
			return false
	for u in board.living_units():
		if not board.is_passable(u.cell):
			push_error("TerrainMove: unit %s starts on wall %s" % [u.def.id, u.cell])
			return false
		for c in board.reachable_move_cells(u):
			if c in SANDBOX_WALLS:
				push_error("TerrainMove: %s can reach wall %s" % [u.def.id, c])
				return false
	var dict := board.terrain_cells()
	if dict.size() != 64 or dict[Vector2i(1, 3)] != WALL or dict[Vector2i(0, 0)] != &"grass":
		push_error("TerrainMove: board terrain_cells mismatch")
		return false
	return true


func _test_map_size_mismatch_falls_back() -> bool:
	var cfg := BoardConfig.new()
	cfg.grid_width = 6
	cfg.grid_height = 5
	cfg.terrain_map_path = SANDBOX_MAP_PATH
	var map := TacticalSandboxRosterScript.load_battle_map(cfg)
	if map.width != 6 or map.height != 5:
		push_error("TerrainMove: size mismatch should fall back to config size")
		return false
	for c in map.terrain_dictionary():
		if not map.is_passable(c):
			push_error("TerrainMove: fallback map should be all passable")
			return false
	cfg.terrain_map_path = "res://resources/map/__missing_map__.json"
	if TacticalSandboxRosterScript.load_battle_map(cfg).width != 6:
		push_error("TerrainMove: missing map should fall back")
		return false
	return true


func _test_ai_respects_walls() -> bool:
	var cfg := load(BOARD_CONFIG_PATH) as BoardConfig
	var board := TacticalSandboxRosterScript.build_board_for_config(cfg)
	for _round in range(4):
		board.reset_side_turn_flags(TacticalFactionScript.Id.OPPONENT)
		TacticalEnemyAiScript.run_opponent_turn(board)
		for u in board.living_units():
			if not board.is_passable(u.cell):
				push_error("TerrainMove: AI moved %s onto wall %s" % [u.def.id, u.cell])
				return false
	return true
