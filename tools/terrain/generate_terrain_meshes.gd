extends SceneTree
## 程序化生成低模地块网格（草地格 / 直城墙格），保存为文本 .tres。
## 运行：godot --headless --path . --script res://tools/terrain/generate_terrain_meshes.gd
## 尺寸全部由 board_config.tres 换算；原点在格心、底板中心（与 GridBoardView 格块放置一致）。
## 顶点色为 sRGB，alpha = 草地斑块遮罩（1 = 接受 shader 世界噪声斑块）。


const BOARD_CONFIG_PATH := "res://resources/map/board_config.tres"
const OUT_DIR := "res://resources/terrain/meshes"
const GRASS_OUT := OUT_DIR + "/grass_tile.tres"
const WALL_OUT := OUT_DIR + "/wall_straight.tres"

const GRASS_SEED := 20261019
const WALL_SEED := 7731
const GRASS_TOP_DIVS := 4
const GRASS_TUFTS := 5

## 墙端石块齐 ±cell/2（相邻墙格首尾相接），灰缝芯体内缩一条缝宽，避免穿出与共面闪烁。
## 以下比例单位均为 U（= cell_size），来自三视图参考。
const WALL_HEIGHT_U := 0.6
const WALL_BODY_U := 0.46
const WALL_THICK_U := 0.16
const WALL_CORE_THICK_U := 0.13
const WALL_ROWS := 4
const WALL_STONE_LEN_U := 0.25
const WALL_GAP_U := 0.014
const MERLON_SPANS_U: Array[Vector2] = [Vector2(-0.5, -0.29), Vector2(-0.11, 0.11), Vector2(0.29, 0.5)]
const WALL_CLEAR_U := 0.15

## 顶面顶点色保持中性白，棋盘深浅由 GridBoardView 按格乘 grass_toon.albedo_tint。
const GRASS_TOP_NEUTRAL := Color(1.0, 1.0, 1.0, 1.0)
const GRASS_SIDE_TOP := Color("7a8150")
const GRASS_SIDE_BOTTOM := Color("666242")
const BLADE_BASE := Color("4f6a2a")
const BLADE_TIP := Color("93a24a")
const MORTAR := Color("3b352e")
## 墙身石砖两色（近 editor_color #8e887f，无光照时仍能分辨块面）
const WALL_STONE_LIGHT := Color("9c958c")
const WALL_STONE_DARK := Color("716c65")

var _cell := 1.0
var _tile_h := 0.14
var _inset := 0.94


func _initialize() -> void:
	var cfg = load(BOARD_CONFIG_PATH)
	if cfg == null:
		push_error("generate_terrain_meshes: missing %s" % BOARD_CONFIG_PATH)
		quit(1)
		return
	_cell = cfg.cell_size
	_tile_h = cfg.tile_height
	_inset = cfg.cell_size * cfg.tile_inset
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var grass := ArrayMesh.new()
	_add_surface(grass, _build_grass(GRASS_SEED, false))
	var wall := ArrayMesh.new()
	_add_surface(wall, _build_grass(GRASS_SEED + 1, true))
	_add_surface(wall, _build_wall_stone(WALL_SEED))

	for pair in [[grass, GRASS_OUT], [wall, WALL_OUT]]:
		var mesh := pair[0] as ArrayMesh
		var path := String(pair[1])
		var err := ResourceSaver.save(mesh, path)
		if err != OK:
			push_error("generate_terrain_meshes: save %s failed (%d)" % [path, err])
			quit(1)
			return
		print("TERRAIN_MESH ", path, " surfaces=", mesh.get_surface_count(), " tris=", _tri_count(mesh), " aabb=", mesh.get_aabb())
	print("TERRAIN_MESHES_OK")
	quit(0)


func _add_surface(mesh: ArrayMesh, st: SurfaceTool) -> void:
	st.index()
	st.commit(mesh)


func _tri_count(mesh: ArrayMesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		n += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


## Godot 正面为顺时针；a,b,c,d 自动纠正为从法线一侧看逆时针后反向写入。
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	if (b - a).cross(c - a).dot(n) < 0.0:
		var tv := b
		b = d
		d = tv
		var tc := cb
		cb = cd
		cd = tc
	_vert(st, a, n, ca)
	_vert(st, c, n, cc)
	_vert(st, b, n, cb)
	_vert(st, a, n, ca)
	_vert(st, d, n, cd)
	_vert(st, c, n, cc)


func _vert(st: SurfaceTool, v: Vector3, n: Vector3, c: Color) -> void:
	st.set_normal(n)
	st.set_color(c)
	st.add_vertex(v)


func _build_grass(seed_value: int, keep_center_clear: bool) -> SurfaceTool:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := _inset * 0.5
	var top := _tile_h * 0.5
	var bottom := -_tile_h * 0.5

	var colors: Array[Color] = []
	for iz in GRASS_TOP_DIVS + 1:
		for ix in GRASS_TOP_DIVS + 1:
			colors.append(GRASS_TOP_NEUTRAL)
	var row := GRASS_TOP_DIVS + 1
	for iz in GRASS_TOP_DIVS:
		for ix in GRASS_TOP_DIVS:
			var x0 := -half + _inset * ix / GRASS_TOP_DIVS
			var x1 := -half + _inset * (ix + 1) / GRASS_TOP_DIVS
			var z0 := -half + _inset * iz / GRASS_TOP_DIVS
			var z1 := -half + _inset * (iz + 1) / GRASS_TOP_DIVS
			_quad(
				st,
				Vector3(x0, top, z0), Vector3(x0, top, z1), Vector3(x1, top, z1), Vector3(x1, top, z0),
				Vector3.UP,
				colors[iz * row + ix], colors[(iz + 1) * row + ix],
				colors[(iz + 1) * row + ix + 1], colors[iz * row + ix + 1]
			)

	var side_t := GRASS_SIDE_TOP
	var side_b := GRASS_SIDE_BOTTOM
	side_t.a = 0.0
	side_b.a = 0.0
	for n in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var nn := n as Vector3
		var tangent := Vector3(-nn.z, 0.0, nn.x)
		var o := nn * half
		_quad(
			st,
			o - tangent * half + Vector3(0, bottom, 0), o - tangent * half + Vector3(0, top, 0),
			o + tangent * half + Vector3(0, top, 0), o + tangent * half + Vector3(0, bottom, 0),
			nn, side_b, side_t, side_t, side_b
		)

	var placed := 0
	var guard := 0
	while placed < GRASS_TUFTS and guard < 200:
		guard += 1
		var px := rng.randf_range(-half * 0.8, half * 0.8)
		var pz := rng.randf_range(-half * 0.8, half * 0.8)
		if keep_center_clear and absf(pz) < WALL_CLEAR_U * _cell:
			continue
		_add_tuft(st, rng, Vector3(px, top, pz))
		placed += 1
	return st


func _add_tuft(st: SurfaceTool, rng: RandomNumberGenerator, base: Vector3) -> void:
	var base_c := BLADE_BASE
	var tip_c := BLADE_TIP.lerp(GRASS_TOP_NEUTRAL, rng.randf_range(0.0, 0.25))
	base_c.a = 0.0
	tip_c.a = 0.0
	var yaw0 := rng.randf_range(0.0, TAU)
	for i in 3:
		var yaw := yaw0 + TAU * i / 3.0 + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var w := rng.randf_range(0.03, 0.04) * _cell
		var h := rng.randf_range(0.065, 0.095) * _cell
		var lean := rng.randf_range(0.02, 0.04) * _cell
		var a := base - side * w * 0.5 + dir * 0.006
		var b := base + side * w * 0.5 + dir * 0.006
		var tip := base + dir * lean + Vector3(0.0, h, 0.0)
		for flip in [false, true]:
			if flip:
				_vert(st, a, Vector3.UP, base_c)
				_vert(st, b, Vector3.UP, base_c)
				_vert(st, tip, Vector3.UP, tip_c)
			else:
				_vert(st, a, Vector3.UP, base_c)
				_vert(st, tip, Vector3.UP, tip_c)
				_vert(st, b, Vector3.UP, base_c)


func _build_wall_stone(seed_value: int) -> SurfaceTool:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ground := _tile_h * 0.5
	var half_len := _cell * 0.5
	var body_top := ground + WALL_BODY_U * _cell
	var crest_top := ground + WALL_HEIGHT_U * _cell
	var gap := WALL_GAP_U * _cell
	var core_half := WALL_CORE_THICK_U * _cell * 0.5
	var stone_half := WALL_THICK_U * _cell * 0.5

	var mortar := MORTAR
	mortar.a = 0.0
	_box(st, Vector3(-half_len + gap, ground, -core_half), Vector3(half_len - gap, body_top - gap, core_half), mortar, mortar)
	for span in MERLON_SPANS_U:
		_box(
			st,
			Vector3(span.x * _cell + gap, body_top - gap, -core_half),
			Vector3(span.y * _cell - gap, crest_top - gap, core_half),
			mortar, mortar
		)

	var row_h := (body_top - ground) / WALL_ROWS
	var stone_len := WALL_STONE_LEN_U * _cell
	var brick_i := 0
	for r in WALL_ROWS:
		var y0 := ground + row_h * r
		var y1 := y0 + row_h
		var edges: Array[float] = [-half_len]
		var x := -half_len + (stone_len * 0.5 if r % 2 == 1 else 0.0)
		while true:
			x += stone_len * rng.randf_range(0.82, 1.18)
			if x >= half_len - stone_len * 0.35:
				break
			if x - edges[edges.size() - 1] > stone_len * 0.3:
				edges.append(x)
		edges.append(half_len)
		for i in edges.size() - 1:
			_stone(st, rng, edges[i], edges[i + 1], y0, y1, stone_half, gap, false, brick_i & 1)
			brick_i += 1

	for span in MERLON_SPANS_U:
		var x0 := span.x * _cell
		var x1 := span.y * _cell
		var mid := (x0 + x1) * 0.5 + rng.randf_range(-0.015, 0.015) * _cell
		_stone(st, rng, x0, mid, body_top, crest_top, stone_half, gap, true, brick_i & 1)
		brick_i += 1
		_stone(st, rng, mid, x1, body_top, crest_top, stone_half, gap, true, brick_i & 1)
		brick_i += 1
	return st


func _stone(st: SurfaceTool, rng: RandomNumberGenerator, x0: float, x1: float, y0: float, y1: float, half_t: float, gap: float, crest: bool, parity: int) -> void:
	var t := half_t + rng.randf_range(-0.006, 0.004) * _cell
	var brick := WALL_STONE_LIGHT if parity == 0 else WALL_STONE_DARK
	brick.a = 0.0
	var side := brick
	var top := brick
	var h_top := y1 - gap * 0.5 + (rng.randf_range(-0.004, 0.004) * _cell if not crest else 0.0)
	var half_len := _cell * 0.5
	var lo_x := x0 if is_equal_approx(x0, -half_len) else x0 + gap * 0.5
	var hi_x := x1 if is_equal_approx(x1, half_len) else x1 - gap * 0.5
	_box(st, Vector3(lo_x, y0 + gap * 0.5, -t), Vector3(hi_x, h_top, t), side, top)


## 五面盒（省略底面）；侧面下暗上亮（上沿近似手绘边缘高光），顶面单独上色。
func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, side: Color, top: Color) -> void:
	var side_lo := side.darkened(0.2)
	side_lo.a = side.a
	var side_hi := side.lightened(0.1)
	side_hi.a = side.a
	side = side_hi
	_quad(st, Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3.UP, top, top, top, top)
	_quad(st, Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3.RIGHT, side_lo, side, side, side_lo)
	_quad(st, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3.LEFT, side_lo, side, side, side_lo)
	_quad(st, Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3.BACK, side_lo, side, side, side_lo)
	_quad(st, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3.FORWARD, side_lo, side, side, side_lo)
