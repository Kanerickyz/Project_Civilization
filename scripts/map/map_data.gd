class_name MapData
extends RefCounted
## 可序列化的方格地图：每格存 TerrainCatalog 地块 id（编辑器产出，沙盘开局加载）。


const FORMAT_ID := "tactical_map_v2"
## 旧版整数格式，只读兼容：0 → 可走类型，其它非零 → 不可走类型。
const FORMAT_ID_V1 := "tactical_map_v1"
const DEFAULT_WIDTH := 8
const DEFAULT_HEIGHT := 8
const MAPS_USER_DIR := "user://maps/"
const _FALLBACK_BLOCKED_ID := &"wall_straight"


var width: int = DEFAULT_WIDTH
var height: int = DEFAULT_HEIGHT
var _cells: Array[StringName] = []


static func catalog() -> TerrainCatalog:
	return TerrainCatalog.load_default()


## 越界格视为此 id（表中第一个不可通行类型）。
static func out_of_bounds_id() -> StringName:
	for t in catalog().types:
		if t != null and not t.passable:
			return t.id
	return _FALLBACK_BLOCKED_ID


static func create_filled(map_width: int, map_height: int, fill: StringName = &"") -> MapData:
	var data := MapData.new()
	data.resize(map_width, map_height, fill)
	return data


## 对战沙盘与编辑器新建时的示例 8×8：第 4 行（y=3）为 `01101101`（草墙墙草墙墙草墙）。
static func create_example_layout() -> MapData:
	var data := create_filled(DEFAULT_WIDTH, DEFAULT_HEIGHT)
	for x in [1, 2, 4, 5, 7]:
		data.set_cell(x, 3, &"wall_straight")
	return data


## fill 为空时用默认地块。
func resize(map_width: int, map_height: int, fill: StringName = &"") -> void:
	width = maxi(1, map_width)
	height = maxi(1, map_height)
	var resolved := catalog().resolve_id(fill) if fill != &"" else catalog().default_id
	_cells.resize(width * height)
	_cells.fill(resolved)


func cell_index(x: int, y: int) -> int:
	return y * width + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func get_cell(x: int, y: int) -> StringName:
	if not in_bounds(x, y):
		return out_of_bounds_id()
	return _cells[cell_index(x, y)]


func get_cell_vec(cell: Vector2i) -> StringName:
	return get_cell(cell.x, cell.y)


func set_cell(x: int, y: int, terrain_id: StringName) -> void:
	if not in_bounds(x, y):
		return
	_cells[cell_index(x, y)] = catalog().resolve_id(terrain_id)


func set_cell_vec(cell: Vector2i, terrain_id: StringName) -> void:
	set_cell(cell.x, cell.y, terrain_id)


func is_passable(cell: Vector2i) -> bool:
	if not in_bounds(cell.x, cell.y):
		return false
	return catalog().is_passable(get_cell_vec(cell))


func to_dict() -> Dictionary:
	var flat: Array = []
	for y in range(height):
		for x in range(width):
			flat.append(String(get_cell(x, y)))
	return {
		"format": FORMAT_ID,
		"width": width,
		"height": height,
		"cells": flat,
	}


static func from_dict(payload: Variant) -> MapData:
	if payload is not Dictionary:
		push_error("MapData: expected Dictionary")
		return null
	var d: Dictionary = payload
	var format := str(d.get("format", ""))
	if format != FORMAT_ID and format != FORMAT_ID_V1:
		push_error("MapData: unsupported format %s" % str(d.get("format")))
		return null
	var w := int(d.get("width", 0))
	var h := int(d.get("height", 0))
	if w < 1 or h < 1:
		push_error("MapData: invalid size %dx%d" % [w, h])
		return null
	var raw: Variant = d.get("cells", [])
	if raw is not Array:
		push_error("MapData: cells must be Array")
		return null
	if raw.size() != w * h:
		push_error("MapData: cells length %d != %d" % [raw.size(), w * h])
		return null
	var cat := catalog()
	var data := MapData.new()
	data.width = w
	data.height = h
	data._cells.resize(w * h)
	for i in range(raw.size()):
		var v: Variant = raw[i]
		if format == FORMAT_ID_V1:
			data._cells[i] = cat.from_legacy_code(int(v))
			continue
		var tid := StringName(str(v)) if (v is String or v is StringName) else &""
		if tid == &"" or not cat.has_id(tid):
			push_warning("MapData: unknown terrain %s at index %d, using %s" % [str(v), i, cat.default_id])
			tid = cat.default_id
		data._cells[i] = tid
	return data


static func ensure_maps_dir() -> bool:
	var err := DirAccess.make_dir_recursive_absolute(MAPS_USER_DIR)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("MapData: cannot create %s (err %d)" % [MAPS_USER_DIR, err])
		return false
	return true


static func resolve_maps_path(file_name: String) -> String:
	var base := file_name.strip_edges()
	if base.is_empty():
		base = "map_001.json"
	if not base.ends_with(".json"):
		base += ".json"
	return MAPS_USER_DIR.path_join(base.get_file())


func save_json_to_path(path: String) -> bool:
	var text := JSON.stringify(to_dict(), "\t")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("MapData: write failed %s" % path)
		return false
	f.store_string(text)
	return true


static func load_json_from_path(path: String) -> MapData:
	if not FileAccess.file_exists(path):
		push_error("MapData: missing file %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("MapData: read failed %s" % path)
		return null
	var text := f.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("MapData: JSON parse failed %s" % path)
		return null
	return from_dict(parsed)


## Vector2i -> StringName（地块 id），供 GridBoardView.set_terrain_cells / TacticalBoard.set_terrain_cells。
func terrain_dictionary() -> Dictionary:
	var out: Dictionary = {}
	for y in range(height):
		for x in range(width):
			out[Vector2i(x, y)] = get_cell(x, y)
	return out
