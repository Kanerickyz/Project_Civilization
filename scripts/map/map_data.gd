class_name MapData
extends RefCounted
## 可序列化的方格地图（编辑器产出；对战加载为后续切片）。


const FORMAT_ID := "tactical_map_v1"
const DEFAULT_WIDTH := 8
const DEFAULT_HEIGHT := 8
const MAPS_USER_DIR := "user://maps/"


var width: int = DEFAULT_WIDTH
var height: int = DEFAULT_HEIGHT
var _cells: PackedInt32Array = PackedInt32Array()


static func create_filled(map_width: int, map_height: int, fill: int = MapTerrainType.Id.WALKABLE) -> MapData:
	var data := MapData.new()
	data.resize(map_width, map_height, fill)
	return data


func resize(map_width: int, map_height: int, fill: int = MapTerrainType.Id.WALKABLE) -> void:
	width = maxi(1, map_width)
	height = maxi(1, map_height)
	_cells.resize(width * height)
	_cells.fill(fill)


func cell_index(x: int, y: int) -> int:
	return y * width + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func get_cell(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return MapTerrainType.Id.BLOCKED
	return _cells[cell_index(x, y)]


func get_cell_vec(cell: Vector2i) -> int:
	return get_cell(cell.x, cell.y)


func set_cell(x: int, y: int, terrain_id: int) -> void:
	if not in_bounds(x, y):
		return
	terrain_id = MapTerrainType.normalize_id(terrain_id)
	_cells[cell_index(x, y)] = terrain_id


func set_cell_vec(cell: Vector2i, terrain_id: int) -> void:
	set_cell(cell.x, cell.y, terrain_id)


func to_dict() -> Dictionary:
	var flat: Array = []
	for y in range(height):
		for x in range(width):
			flat.append(get_cell(x, y))
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
	if str(d.get("format", "")) != FORMAT_ID:
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
	var data := MapData.new()
	data.width = w
	data.height = h
	data._cells.resize(w * h)
	for i in range(raw.size()):
		data._cells[i] = MapTerrainType.normalize_id(int(raw[i]))
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


func terrain_dictionary() -> Dictionary:
	var out: Dictionary = {}
	for y in range(height):
		for x in range(width):
			out[Vector2i(x, y)] = get_cell(x, y)
	return out
