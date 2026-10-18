class_name TacticalBoard
extends RefCounted

const GridMathScript := preload("res://scripts/units/grid_math.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")

signal changed

var grid_width: int = 10
var grid_height: int = 8
var units: Array[TacticalUnitInstance] = []


func setup(p_width: int, p_height: int) -> void:
	grid_width = p_width
	grid_height = p_height
	units.clear()


func add_unit(instance: TacticalUnitInstance) -> void:
	units.append(instance)
	changed.emit()


func unit_at(cell: Vector2i) -> TacticalUnitInstance:
	for u in units:
		if u.is_alive() and u.cell == cell:
			return u
	return null


func living_units() -> Array[TacticalUnitInstance]:
	var out: Array[TacticalUnitInstance] = []
	for u in units:
		if u.is_alive():
			out.append(u)
	return out


func reset_side_turn_flags(active_faction: TacticalFaction.Id) -> void:
	for u in units:
		if u.faction == active_faction:
			u.skill_used_this_side_turn = false
			u.moved_this_side_turn = false
	changed.emit()


func try_move(unit: TacticalUnitInstance, dest: Vector2i) -> bool:
	if unit.moved_this_side_turn:
		return false
	if not GridMathScript.in_bounds(dest, grid_width, grid_height):
		return false
	if unit_at(dest) != null:
		return false
	if GridMathScript.chebyshev(unit.cell, dest) > unit.def.move_range:
		return false
	unit.cell = dest
	unit.moved_this_side_turn = true
	changed.emit()
	return true


func allies_in_radius(origin: Vector2i, faction: TacticalFaction.Id, radius: int, exclude_cell: Vector2i) -> Array[TacticalUnitInstance]:
	var out: Array[TacticalUnitInstance] = []
	for u in living_units():
		if u.faction != faction:
			continue
		if u.cell == exclude_cell:
			continue
		if GridMathScript.chebyshev(origin, u.cell) <= radius:
			out.append(u)
	return out
