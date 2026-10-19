class_name MapTerrainType
extends RefCounted
## 地图编辑器地形：仅可走 / 不可走（对战逻辑尚未接入）。


enum Id {
	WALKABLE = 0,
	BLOCKED = 1,
}


const _LABELS: PackedStringArray = ["可走", "不可走"]

const _COLORS: Array[Color] = [
	Color("3d4a58"),
	Color("1e1e24"),
]


static func all_ids() -> Array[int]:
	return [Id.WALKABLE, Id.BLOCKED]


static func label_for(terrain_id: int) -> String:
	var norm := normalize_id(terrain_id)
	if norm >= 0 and norm < _LABELS.size():
		return _LABELS[norm]
	return "未知"


static func color_for(terrain_id: int) -> Color:
	var norm := normalize_id(terrain_id)
	if norm >= 0 and norm < _COLORS.size():
		return _COLORS[norm]
	return Color("444444")


static func is_valid(terrain_id: int) -> bool:
	return normalize_id(terrain_id) == Id.WALKABLE or normalize_id(terrain_id) == Id.BLOCKED


## 旧版 JSON 曾用 2 表示不可走；1 曾为「障碍」，统一视为不可走。
static func normalize_id(terrain_id: int) -> int:
	if terrain_id == Id.WALKABLE:
		return Id.WALKABLE
	return Id.BLOCKED


static func toggle(terrain_id: int) -> int:
	if normalize_id(terrain_id) == Id.WALKABLE:
		return Id.BLOCKED
	return Id.WALKABLE
