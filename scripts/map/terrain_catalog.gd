class_name TerrainCatalog
extends Resource
## 地块类型表。顺序即编辑器点格轮换顺序；正式条目见 resources/terrain/terrain_catalog.tres。


const DEFAULT_PATH := "res://resources/terrain/terrain_catalog.tres"

@export var types: Array[TerrainTypeDef] = []
## 未绘制格、越界外的默认地块。
@export var default_id: StringName = &"grass"

static var _default_cache: TerrainCatalog


static func load_default() -> TerrainCatalog:
	if _default_cache == null:
		var loaded := load(DEFAULT_PATH)
		if loaded is TerrainCatalog:
			_default_cache = loaded as TerrainCatalog
		else:
			push_error("TerrainCatalog: missing %s" % DEFAULT_PATH)
			_default_cache = TerrainCatalog.new()
	return _default_cache


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for t in types:
		if t != null:
			out.append(t.id)
	return out


func has_id(terrain_id: StringName) -> bool:
	return get_def(terrain_id) != null


func get_def(terrain_id: StringName) -> TerrainTypeDef:
	for t in types:
		if t != null and t.id == terrain_id:
			return t
	return null


func default_def() -> TerrainTypeDef:
	return get_def(default_id)


## 未知 id 视为默认地块。
func resolve_id(terrain_id: StringName) -> StringName:
	return terrain_id if has_id(terrain_id) else default_id


func is_passable(terrain_id: StringName) -> bool:
	var def := get_def(resolve_id(terrain_id))
	return def == null or def.passable


func display_name_for(terrain_id: StringName) -> String:
	var def := get_def(terrain_id)
	return def.display_name if def != null else "未知"


func next_id(terrain_id: StringName) -> StringName:
	var list := ids()
	if list.is_empty():
		return default_id
	var i := list.find(resolve_id(terrain_id))
	return list[(i + 1) % list.size()]


## tactical_map_v1：0 → 可走类型；其它非零 → 不可走类型（历史上 1/2 都表示障碍）。
func from_legacy_code(code: int) -> StringName:
	for t in types:
		if t != null and t.legacy_code == code:
			return t.id
	if code != 0:
		for t in types:
			if t != null and not t.passable and t.legacy_code >= 0:
				return t.id
	return default_id
