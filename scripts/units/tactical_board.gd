class_name TacticalBoard
extends RefCounted

const GridMathScript := preload("res://scripts/units/grid_math.gd")
const GridPathfindingScript := preload("res://scripts/units/grid_pathfinding.gd")
const TacticalFactionScript := preload("res://scripts/units/tactical_faction.gd")

signal changed

var grid_width: int = 10
var grid_height: int = 8
var units: Array[TacticalUnitInstance] = []
## 玩家牌库弱引用（游侠击杀加临时攻卡）；对手 AI 无。
var player_deck: TacticalCardDeck = null
## Vector2i -> StringName（TerrainCatalog id）；缺省格为默认地块。
var _terrain: Dictionary = {}
var _catalog: TerrainCatalog = TerrainCatalog.load_default()
## 视觉：最近一次燃爆/爆燃 AoE 涉及的格子（含空格）；段开始燃烧结算后清除。
var _ignited_aoe_cells: Dictionary = {}


func setup(p_width: int, p_height: int) -> void:
	grid_width = p_width
	grid_height = p_height
	units.clear()
	_terrain.clear()
	_ignited_aoe_cells.clear()


func set_terrain_cells(cells: Dictionary) -> void:
	_terrain.clear()
	for key in cells:
		if key is Vector2i:
			_terrain[key] = _catalog.resolve_id(StringName(cells[key]))
	changed.emit()


func set_terrain(map_data: MapData) -> void:
	set_terrain_cells(map_data.terrain_dictionary() if map_data != null else {})


func terrain_at(cell: Vector2i) -> StringName:
	return _terrain.get(cell, _catalog.default_id)


## 全盘 Vector2i -> StringName，供 GridBoardView.set_terrain_cells。
func terrain_cells() -> Dictionary:
	var out: Dictionary = {}
	for gx in range(grid_width):
		for gy in range(grid_height):
			var cell := Vector2i(gx, gy)
			out[cell] = terrain_at(cell)
	return out


func terrain_display_name(cell: Vector2i) -> String:
	return _catalog.display_name_for(terrain_at(cell))


func is_passable(cell: Vector2i) -> bool:
	if not GridMathScript.in_bounds(cell, grid_width, grid_height):
		return false
	return _catalog.is_passable(terrain_at(cell))


func is_burn_immune_cell(cell: Vector2i) -> bool:
	return _catalog.burn_immune(terrain_at(cell))


## 攻击视线：中间格若有挡攻地块（树林）则 false。邻格恒 true。
func has_attack_los(from: Vector2i, to: Vector2i) -> bool:
	for mid in GridMathScript.cells_between(from, to):
		if _catalog.blocks_attack(terrain_at(mid)):
			return false
	return true


## 8 邻接、绕开不可通行格、禁止斜穿墙角的路径步数；单位不阻挡路径中间。不可达返回 -1。
func path_distance(from: Vector2i, to: Vector2i, max_cost: int = -1) -> int:
	return GridPathfindingScript.path_distance(from, to, is_passable, max_cost)


func path_distances_from(origin: Vector2i, max_cost: int = -1) -> Dictionary:
	return GridPathfindingScript.distances_from(origin, is_passable, max_cost)


## 最短路径格序（含起终点）；不可达返回空。
func shortest_path(from: Vector2i, to: Vector2i, max_cost: int = -1) -> Array[Vector2i]:
	return GridPathfindingScript.shortest_path(from, to, is_passable, max_cost)


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
			# 敌我均按段重置移力池（玩家点格移动；对手 AI 同池）。
			u.remaining_move_budget = u.def.action_move_budget()
	changed.emit()


func reachable_move_cells(unit: TacticalUnitInstance) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if unit == null or not unit.is_alive() or unit.remaining_move_budget <= 0:
		return out
	# 瞬移：切比雪夫 ≤ 剩余移力（且 ≤ move_range），无视中间阻挡。
	if unit.def != null and unit.def.teleports:
		var cap := mini(unit.remaining_move_budget, unit.def.move_range)
		for gx in range(grid_width):
			for gy in range(grid_height):
				var cell := Vector2i(gx, gy)
				if cell == unit.cell:
					continue
				if not is_passable(cell):
					continue
				if unit_at(cell) != null:
					continue
				var d := GridMathScript.chebyshev(unit.cell, cell)
				if d <= 0 or d > cap:
					continue
				out.append(cell)
		return out
	# 多段累计：每段落脚格须为空且路径步数 ≤ move_range，总步数 ≤ 剩余移力。
	var dist: Dictionary = {unit.cell: 0}
	var queue: Array[Vector2i] = [unit.cell]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var cur_d: int = dist[cur]
		var hop := path_distances_from(cur, unit.def.move_range)
		for gx in range(grid_width):
			for gy in range(grid_height):
				var cell := Vector2i(gx, gy)
				if cell == cur:
					continue
				if not hop.has(cell):
					continue
				if unit_at(cell) != null:
					continue
				var step: int = hop[cell]
				var nd := cur_d + step
				if nd > unit.remaining_move_budget:
					continue
				if dist.has(cell) and dist[cell] <= nd:
					continue
				dist[cell] = nd
				queue.append(cell)
				out.append(cell)
	return out


## 选中查看用：临时按移力预算算可达格，不改写单位剩余移力。step_cap>0 时再封顶。
func preview_reachable_move_cells(
	unit: TacticalUnitInstance, step_cap: int = -1
) -> Array[Vector2i]:
	if unit == null or not unit.is_alive():
		return []
	var budget := unit.def.action_move_budget()
	if step_cap > 0:
		budget = mini(budget, step_cap)
	if budget <= 0:
		return []
	var saved := unit.remaining_move_budget
	unit.remaining_move_budget = budget
	var out := reachable_move_cells(unit)
	unit.remaining_move_budget = saved
	return out


func attack_range_cells(unit: TacticalUnitInstance) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if unit == null or not unit.is_alive():
		return out
	for gx in range(grid_width):
		for gy in range(grid_height):
			var cell := Vector2i(gx, gy)
			var dist := GridMathScript.chebyshev(unit.cell, cell)
			if not unit.def.is_chebyshev_in_attack_band(dist):
				continue
			if not has_attack_los(unit.cell, cell):
				continue
			out.append(cell)
	return out


## 鼓手「鼓舞」：周围 radius 格内其他友方各 +1 狂暴（不含自身）。
func apply_inspire_frenzy(drummer: TacticalUnitInstance, radius: int = 1) -> Dictionary:
	var result := {"ok": false, "buffed": 0, "log": ""}
	if drummer == null or not drummer.is_alive() or drummer.def == null:
		result["log"] = "无效鼓舞"
		return result
	if drummer.def.id != "wardrum":
		result["log"] = "鼓舞只能由鼓手触发"
		return result
	var allies := allies_in_radius(drummer.cell, drummer.faction, radius, drummer.cell)
	var buffed := 0
	for ally in allies:
		if ally == drummer:
			continue
		if ally.add_frenzy_stacks(1) > 0:
			buffed += 1
	result["buffed"] = buffed
	result["ok"] = true
	if buffed == 0:
		result["log"] = "%s 鼓舞：周围无友方可叠狂暴" % drummer.def.display_name
	else:
		result["log"] = "%s 鼓舞：%d 名周围友方 +1 狂暴" % [drummer.def.display_name, buffed]
	changed.emit()
	return result


func apply_damage(target: TacticalUnitInstance, amount: int, source: TacticalUnitInstance = null) -> Dictionary:
	var result := {
		"ok": false,
		"log": "",
		"killed": false,
		"armor_absorbed": 0,
		"hp_damage": 0,
		"broke_stealth": false,
	}
	if target == null or not target.is_alive() or amount <= 0:
		result["log"] = "无效伤害"
		return result
	# 受伤取消隐身（含仅打在护甲上）。
	if target.break_stealth():
		result["broke_stealth"] = true
	var armor_absorbed := 0
	var hp_damage := 0
	# 有护甲时整段伤害打在护甲上：护甲归零后溢出不穿血。
	if target.armor > 0:
		if amount > target.armor:
			armor_absorbed = target.armor
			target.armor = 0
		else:
			armor_absorbed = amount
			target.armor -= amount
	else:
		hp_damage = amount
		target.hp -= amount
	result["armor_absorbed"] = armor_absorbed
	result["hp_damage"] = hp_damage
	var hurt_logs: Array[String] = []
	if armor_absorbed > 0:
		hurt_logs.append("护甲吸收 %d" % armor_absorbed)
	# 「受伤」被动仅在实际扣血时触发。
	if hp_damage > 0:
		hurt_logs.append_array(TacticalAbilitySystem.process_unit_hurt(self, target, hp_damage))
	if not target.is_alive():
		result["killed"] = true
		# 先死亡触发（爆燃等），再记击杀者被动；死亡单位仍可读 cell。
		var death_logs := TacticalAbilitySystem.process_unit_death(self, target)
		hurt_logs.append_array(death_logs)
		if source != null and source != target:
			var kill_logs := TacticalAbilitySystem.process_unit_kill(self, source, target)
			hurt_logs.append_array(kill_logs)
	result["ok"] = true
	result["log"] = " · ".join(hurt_logs) if hurt_logs.size() > 0 else ""
	changed.emit()
	return result


## 对 origin 切比雪夫 ≤ radius 的存活单位施加燃烧（可排除 exclude）。返回受影响人数。
## 同时标记范围内全部格子为点燃（视觉；空格不叠玩法层数）。湖格与其上单位免疫。
func apply_burn_aoe(
	origin: Vector2i,
	stacks: int,
	radius: int = 1,
	exclude: TacticalUnitInstance = null
) -> int:
	if stacks <= 0:
		return 0
	var n := 0
	for u in living_units():
		if u == exclude:
			continue
		if GridMathScript.chebyshev(origin, u.cell) > radius:
			continue
		if is_burn_immune_cell(u.cell):
			continue
		u.add_burn_stacks(stacks)
		n += 1
	_mark_ignited_aoe(origin, radius)
	changed.emit()
	return n


## 供棋盘视图：AoE 点燃残留 ∪ 当前仍有燃烧层数的单位所在格。
func ignited_cells_for_view() -> Array[Vector2i]:
	var seen: Dictionary = {}
	var out: Array[Vector2i] = []
	for key in _ignited_aoe_cells.keys():
		if key is Vector2i and not seen.has(key):
			seen[key] = true
			out.append(key as Vector2i)
	for u in living_units():
		if u.burn_stacks <= 0:
			continue
		if is_burn_immune_cell(u.cell):
			continue
		if seen.has(u.cell):
			continue
		seen[u.cell] = true
		out.append(u.cell)
	return out


func _mark_ignited_aoe(origin: Vector2i, radius: int) -> void:
	var r := maxi(0, radius)
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var cell := origin + Vector2i(dx, dy)
			if not GridMathScript.in_bounds(cell, grid_width, grid_height):
				continue
			if GridMathScript.chebyshev(origin, cell) > r:
				continue
			if is_burn_immune_cell(cell):
				continue
			_ignited_aoe_cells[cell] = true


## 该方行动段开始：仅结算该方燃烧单位——先造成=层数伤害，再减 1 层。敌我各一次，不跨方重复。
## 返回事件列表（unit/cell/damage/killed/ok/log），供 UI 飘字；同 tick 内只扫开场 survivors，死亡新燃不重结。
func process_burn_ticks(faction: TacticalFaction.Id) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var victims: Array[TacticalUnitInstance] = []
	for u in living_units():
		if u.faction != faction:
			continue
		if u.burn_stacks > 0:
			victims.append(u)
	for u in victims:
		if not u.is_alive() or u.burn_stacks <= 0:
			continue
		# 湖上单位不结算燃烧伤害（进湖已清燃；此处兜底）。
		if is_burn_immune_cell(u.cell):
			u.burn_stacks = 0
			continue
		var stacks := u.burn_stacks
		var cell := u.cell
		var hurt := apply_damage(u, stacks, null)
		if hurt.get("ok", false):
			var killed: bool = bool(hurt.get("killed", false))
			events.append({
				"unit": u,
				"cell": cell,
				"damage": stacks,
				"killed": killed,
				"ok": true,
				"kind": "burn",
				"log": "%s 燃烧 %d：受到 %d 伤害%s"
				% [
					u.def.display_name,
					stacks,
					stacks,
					"（阵亡）" if killed else "",
				],
			})
		if u.is_alive():
			u.burn_stacks = maxi(0, u.burn_stacks - 1)
	# AoE 点燃视觉在结算后收束：仅保留仍燃烧单位脚下格（由 ignited_cells_for_view 拼）。
	var had_ignited := not _ignited_aoe_cells.is_empty()
	_ignited_aoe_cells.clear()
	if events.size() > 0 or had_ignited:
		changed.emit()
	return events


func _apply_terrain_enter_effects(unit: TacticalUnitInstance) -> void:
	if unit == null or not unit.is_alive():
		return
	if _catalog.clears_burn_on_enter(terrain_at(unit.cell)):
		if unit.burn_stacks > 0:
			unit.burn_stacks = 0


func try_move(unit: TacticalUnitInstance, dest: Vector2i) -> bool:
	if unit.remaining_move_budget <= 0:
		return false
	if not is_passable(dest):
		return false
	if unit_at(dest) != null:
		return false
	var step := 0
	if unit.def != null and unit.def.teleports:
		var cap := mini(unit.def.move_range, unit.remaining_move_budget)
		step = GridMathScript.chebyshev(unit.cell, dest)
		if step <= 0 or step > cap:
			return false
	else:
		step = path_distance(unit.cell, dest, mini(unit.def.move_range, unit.remaining_move_budget))
		if step <= 0:
			return false
	unit.cell = dest
	unit.remaining_move_budget -= step
	if unit.remaining_move_budget <= 0:
		unit.moved_this_side_turn = true
	_apply_terrain_enter_effects(unit)
	TacticalAbilitySystem.process_unit_move_end(self, unit)
	changed.emit()
	return true


## 强制位移（击退等）：不耗移力、不触发移动结束被动；落点须可通行且为空。
func force_displace(unit: TacticalUnitInstance, dest: Vector2i) -> bool:
	if unit == null or not unit.is_alive():
		return false
	if dest == unit.cell:
		return true
	if not is_passable(dest):
		return false
	if unit_at(dest) != null:
		return false
	unit.cell = dest
	_apply_terrain_enter_effects(unit)
	changed.emit()
	return true


## 开战前部署：己方左半列可通行格；可与己方换位；不耗移力、不触发移动结束被动。
func is_player_deploy_cell(cell: Vector2i) -> bool:
	if not GridMathScript.in_bounds(cell, grid_width, grid_height):
		return false
	if cell.x >= int(grid_width / 2):
		return false
	return is_passable(cell)


## 列出当前棋盘全部合法己方部署格（供 overlay）。
func player_deploy_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for gx in range(int(grid_width / 2)):
		for gy in range(grid_height):
			var cell := Vector2i(gx, gy)
			if is_passable(cell):
				out.append(cell)
	return out


func can_deploy_place(unit: TacticalUnitInstance, dest: Vector2i) -> bool:
	if unit == null or not unit.is_alive():
		return false
	if unit.faction != TacticalFactionScript.Id.PLAYER:
		return false
	if not is_player_deploy_cell(dest):
		return false
	var occupant := unit_at(dest)
	if occupant == null or occupant == unit:
		return true
	return occupant.faction == TacticalFactionScript.Id.PLAYER


func try_deploy_place(unit: TacticalUnitInstance, dest: Vector2i) -> bool:
	if not can_deploy_place(unit, dest):
		return false
	if unit.cell == dest:
		return true
	var occupant := unit_at(dest)
	if occupant == null:
		unit.cell = dest
		_apply_terrain_enter_effects(unit)
	else:
		var from := unit.cell
		unit.cell = dest
		occupant.cell = from
		_apply_terrain_enter_effects(unit)
		_apply_terrain_enter_effects(occupant)
	changed.emit()
	return true


## 令目标隐身（刺客主动）；加隐身状态本身不先破隐。
func apply_grant_stealth(caster: TacticalUnitInstance, target: TacticalUnitInstance) -> Dictionary:
	var result := {"ok": false, "log": ""}
	if caster == null or not caster.is_alive() or caster.def == null or caster.def.id != "assassin":
		result["log"] = "隐身只能由刺客触发"
		return result
	if target == null or not target.is_alive():
		result["log"] = "需要存活目标"
		return result
	target.grant_stealth()
	result["ok"] = true
	result["log"] = "%s 令 %s 隐身" % [caster.def.display_name, target.def.display_name]
	changed.emit()
	return result


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
