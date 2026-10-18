class_name TacticalUnitDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var max_hp: int = 1
@export var attack: int = 1
@export var move_range: int = 1
@export var attack_range: int = 1
@export var texture_blue: Texture2D
@export var texture_red: Texture2D
@export var triggered_ability: TacticalActiveAbility
