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
			u.moved_this_side_turn = false
			u.attacked_this_side_turn = false
			u.remaining_move_budget = u.def.action_move_budget()
	changed.emit()


func reachable_move_cells(unit: TacticalUnitInstance) -> Array[Vector2i]:
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
		for gx in range(grid_width):
			for gy in range(grid_height):
				var cell := Vector2i(gx, gy)
				if cell == cur:
					continue
				if unit_at(cell) != null:
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


func attack_range_cells(unit: TacticalUnitInstance) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if unit == null or not unit.is_alive():
		return out
	var r := unit.def.attack_range
	for gx in range(grid_width):
		for gy in range(grid_height):
			var cell := Vector2i(gx, gy)
			if GridMathScript.chebyshev(unit.cell, cell) > r:
				continue
			if cell == unit.cell:
				continue
			out.append(cell)
	return out


func apply_damage(target: TacticalUnitInstance, amount: int, source: TacticalUnitInstance = null) -> Dictionary:
	var result := {"ok": false, "log": "", "killed": false}
	if target == null or not target.is_alive() or amount <= 0:
		result["log"] = "无效伤害"
		return result
	target.hp -= amount
	var hurt_logs := TacticalAbilitySystem.process_unit_hurt(self, target, amount)
	if not target.is_alive():
		result["killed"] = true
		if source != null and source != target:
			var kill_logs := TacticalAbilitySystem.process_unit_kill(self, source, target)
			hurt_logs.append_array(kill_logs)
	result["ok"] = true
	result["log"] = " · ".join(hurt_logs) if hurt_logs.size() > 0 else ""
	changed.emit()
	return result


func try_move(unit: TacticalUnitInstance, dest: Vector2i) -> bool:
	if unit.remaining_move_budget <= 0:
		return false
	if not GridMathScript.in_bounds(dest, grid_width, grid_height):
		return false
	if unit_at(dest) != null:
		return false
	var step := GridMathScript.chebyshev(unit.cell, dest)
	if step > unit.def.move_range or step > unit.remaining_move_budget:
		return false
	unit.cell = dest
	unit.remaining_move_budget -= step
	if unit.remaining_move_budget <= 0:
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
