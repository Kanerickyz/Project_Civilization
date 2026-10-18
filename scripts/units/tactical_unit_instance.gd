class_name TacticalUnitInstance
extends RefCounted

var def: TacticalUnitDef
var faction: TacticalFaction.Id = TacticalFaction.Id.PLAYER
var cell: Vector2i = Vector2i.ZERO
var hp: int = 1
var atk_bonus: int = 0
var moved_this_side_turn: bool = false
var remaining_move_budget: int = 0
var attacked_this_side_turn: bool = false
var deploy_trigger_fired: bool = false


func _init(p_def: TacticalUnitDef, p_faction: TacticalFaction.Id, p_cell: Vector2i) -> void:
	def = p_def
	faction = p_faction
	cell = p_cell
	hp = p_def.max_hp
	remaining_move_budget = p_def.action_move_budget()


func effective_attack() -> int:
	return def.attack + atk_bonus


func is_alive() -> bool:
	return hp > 0
