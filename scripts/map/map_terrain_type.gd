class_name MapTerrainType
extends RefCounted
## 地块类型的静态门面：转发到默认 TerrainCatalog（resources/terrain/terrain_catalog.tres）。


static func catalog() -> TerrainCatalog:
	return TerrainCatalog.load_default()


static func all_ids() -> Array[StringName]:
	return catalog().ids()


static func default_id() -> StringName:
	return catalog().default_id


static func label_for(terrain_id: StringName) -> String:
	return catalog().display_name_for(catalog().resolve_id(terrain_id))


static func color_for(terrain_id: StringName) -> Color:
	var def := catalog().get_def(catalog().resolve_id(terrain_id))
	return def.editor_color if def != null else Color("444444")


static func is_valid(terrain_id: StringName) -> bool:
	return catalog().has_id(terrain_id)


static func is_passable(terrain_id: StringName) -> bool:
	return catalog().is_passable(terrain_id)


## 按表顺序轮换到下一种地块。
static func next_id(terrain_id: StringName) -> StringName:
	return catalog().next_id(terrain_id)


static func from_legacy_code(code: int) -> StringName:
	return catalog().from_legacy_code(code)


## 编辑器提示用：「空草地 → 直城墙 → …」。
static func cycle_hint() -> String:
	var names: PackedStringArray = []
	for tid in all_ids():
		names.append(label_for(tid))
	names.append("…")
	return " → ".join(names)
