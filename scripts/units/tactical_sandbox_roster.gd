class_name TacticalSandboxRoster
extends RefCounted

const TacticalBoardScript := preload("res://scripts/units/tactical_board.gd")
const TacticalUnitInstanceScript := preload("res://scripts/units/tactical_unit_instance.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")

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


static func _load_defs() -> Array[TacticalUnitDef]:
	var out: Array[TacticalUnitDef] = []
	for path in UNIT_PATHS:
		var loaded := load(path)
		if loaded is TacticalUnitDef:
			out.append(loaded as TacticalUnitDef)
		else:
			push_warning("TacticalSandboxRoster: missing %s" % path)
	return out
