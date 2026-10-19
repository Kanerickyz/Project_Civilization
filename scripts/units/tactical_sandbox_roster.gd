class_name TacticalSandboxRoster
extends RefCounted

const TacticalBoardScript := preload("res://scripts/units/tactical_board.gd")
const TacticalUnitInstanceScript := preload("res://scripts/units/tactical_unit_instance.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")
const MapDataScript := preload("res://scripts/map/map_data.gd")

const UNIT_PATHS: Array[String] = [
	"res://resources/units/knight.tres",
	"res://resources/units/archer.tres",
	"res://resources/units/mini_pekka.tres",
	"res://resources/units/wardrum.tres",
]

const PLAYER_CELLS: Array[Vector2i] = [
	Vector2i(1, 2),
	Vector2i(1, 4),
	Vector2i(1, 6),
	Vector2i(2, 4),
]

const OPPONENT_CELLS: Array[Vector2i] = [
	Vector2i(8, 2),
	Vector2i(8, 4),
	Vector2i(8, 6),
	Vector2i(7, 4),
]


static func build_demo_board(width: int, height: int) -> TacticalBoard:
	var board: TacticalBoard = TacticalBoardScript.new()
	board.setup(width, height)
	var defs: Array[TacticalUnitDef] = _load_defs()
	for i in defs.size():
		var p_cell: Vector2i = PLAYER_CELLS[i]
		var o_cell: Vector2i = OPPONENT_CELLS[i]
		board.add_unit(TacticalUnitInstanceScript.new(defs[i], TacticalFactionScript.Id.PLAYER, p_cell))
		board.add_unit(TacticalUnitInstanceScript.new(defs[i], TacticalFactionScript.Id.OPPONENT, o_cell))
	return board


## 对战开局：按 config 尺寸布阵，并装入 terrain_map_path 指向的地块布局。
static func build_board_for_config(config: BoardConfig) -> TacticalBoard:
	var board := build_demo_board(config.grid_width, config.grid_height)
	board.set_terrain(load_battle_map(config))
	return board


## 读 config.terrain_map_path；路径为空、缺失、解析失败或尺寸不符时返回全默认地块。
static func load_battle_map(config: BoardConfig) -> MapData:
	var fallback := MapDataScript.create_filled(config.grid_width, config.grid_height)
	var path := config.terrain_map_path
	if path.is_empty():
		return fallback
	if not FileAccess.file_exists(path):
		push_warning("TacticalSandboxRoster: terrain map missing %s, using default terrain" % path)
		return fallback
	var loaded := MapDataScript.load_json_from_path(path)
	if loaded == null:
		push_warning("TacticalSandboxRoster: terrain map unreadable %s, using default terrain" % path)
		return fallback
	if loaded.width != config.grid_width or loaded.height != config.grid_height:
		push_warning(
			"TacticalSandboxRoster: terrain map %dx%d != board %dx%d, using default terrain"
			% [loaded.width, loaded.height, config.grid_width, config.grid_height]
		)
		return fallback
	return loaded


static func _load_defs() -> Array[TacticalUnitDef]:
	var out: Array[TacticalUnitDef] = []
	for path in UNIT_PATHS:
		var loaded := load(path)
		if loaded is TacticalUnitDef:
			out.append(loaded as TacticalUnitDef)
		else:
			push_warning("TacticalSandboxRoster: missing %s" % path)
	return out
