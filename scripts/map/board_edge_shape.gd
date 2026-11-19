class_name BoardEdgeShape
extends RefCounted
## 对战盘：每次开局在 10×8 / 8×10 二选一，再随机边缘缩进（void 缺格）。


const VOID_ID := &"void"
## 边缘每侧最大缩进格数（相对外包矩形）；偏轻，保留 10×8/8×10 体量感。
const MAX_EDGE_INDENT := 1
## 缩进后剩余最小「实心」跨度，避免左右/上下对咬掏空。
const MIN_SOLID_SPAN := 5
## 每侧至少要留下的可部署/敌方半盘空位粗下限。
const MIN_SIDE_CELLS := 12


## 开局外包尺寸：10×8 或 8×10。
static func pick_battle_size(rng: RandomNumberGenerator) -> Vector2i:
	if rng.randf() < 0.5:
		return Vector2i(10, 8)
	return Vector2i(8, 10)


## 按外包尺寸估 camera_ortho_size（略大于长边）。
static func ortho_size_for(width: int, height: int) -> float:
	return float(maxi(width, height)) * 0.9


## 随机边缘 void；保证连通核与左右半盘有足够空位。
static func void_cells(
	width: int, height: int, rng: RandomNumberGenerator
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if width < 6 or height < 6 or rng == null:
		return out
	var present: Array = []
	present.resize(width * height)
	for i in range(present.size()):
		present[i] = true

	var top: Array[int] = []
	var bot: Array[int] = []
	top.resize(width)
	bot.resize(width)
	for x in range(width):
		var max_t := mini(MAX_EDGE_INDENT, height - MIN_SOLID_SPAN)
		top[x] = rng.randi_range(0, maxi(0, max_t))
		var max_b := mini(MAX_EDGE_INDENT, height - MIN_SOLID_SPAN - top[x])
		bot[x] = rng.randi_range(0, maxi(0, max_b))

	var left: Array[int] = []
	var right: Array[int] = []
	left.resize(height)
	right.resize(height)
	for y in range(height):
		var max_l := mini(MAX_EDGE_INDENT, width - MIN_SOLID_SPAN)
		left[y] = rng.randi_range(0, maxi(0, max_l))
		var max_r := mini(MAX_EDGE_INDENT, width - MIN_SOLID_SPAN - left[y])
		right[y] = rng.randi_range(0, maxi(0, max_r))

	# 角区再咬一口，避免边缘太平。
	_nibble_corners(width, height, top, bot, left, right, rng)

	for y in range(height):
		for x in range(width):
			var voided := (
				y < top[x]
				or y >= height - bot[x]
				or x < left[y]
				or x >= width - right[y]
			)
			if voided:
				present[y * width + x] = false

	_ensure_side_capacity(present, width, height, true, rng)
	_ensure_side_capacity(present, width, height, false, rng)
	_keep_largest_component(present, width, height)

	for y2 in range(height):
		for x2 in range(width):
			if not present[y2 * width + x2]:
				out.append(Vector2i(x2, y2))
	return out


## 把 void 写入 MapData（覆盖湖/林）。
static func apply_to_map(map: MapData, rng: RandomNumberGenerator) -> void:
	if map == null or rng == null:
		return
	for cell in void_cells(map.width, map.height, rng):
		map.set_cell_vec(cell, VOID_ID)


## 把 void 写入棋盘地形字典。
static func apply_to_board(board: TacticalBoard, rng: RandomNumberGenerator) -> void:
	if board == null or rng == null:
		return
	var cells := board.terrain_cells()
	for cell in void_cells(board.grid_width, board.grid_height, rng):
		cells[cell] = VOID_ID
	board.set_terrain_cells(cells)


static func _nibble_corners(
	width: int,
	height: int,
	top: Array[int],
	bot: Array[int],
	left: Array[int],
	right: Array[int],
	rng: RandomNumberGenerator
) -> void:
	for x in [0, width - 1]:
		if x < 0 or x >= width:
			continue
		if rng.randf() < 0.55:
			top[x] = mini(height - MIN_SOLID_SPAN, maxi(top[x], 1))
		if rng.randf() < 0.55:
			bot[x] = mini(height - MIN_SOLID_SPAN - top[x], maxi(bot[x], 1))
	for y in [0, height - 1]:
		if y < 0 or y >= height:
			continue
		if rng.randf() < 0.55:
			left[y] = mini(width - MIN_SOLID_SPAN, maxi(left[y], 1))
		if rng.randf() < 0.55:
			right[y] = mini(width - MIN_SOLID_SPAN - left[y], maxi(right[y], 1))


## 若左/右半盘 present 过少，把该侧靠外缘的 void 补回。
static func _ensure_side_capacity(
	present: Array, width: int, height: int, left_side: bool, rng: RandomNumberGenerator
) -> void:
	var mid := int(width / 2)
	var x0 := 0 if left_side else mid
	var x1 := mid if left_side else width
	var count := 0
	for y in range(height):
		for x in range(x0, x1):
			if present[y * width + x]:
				count += 1
	if count >= MIN_SIDE_CELLS:
		return
	var candidates: Array[Vector2i] = []
	for y2 in range(height):
		for x2 in range(x0, x1):
			if not present[y2 * width + x2]:
				candidates.append(Vector2i(x2, y2))
	# 优先补回更靠盘心的格，避免补成规整外框。
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ca := absf(float(a.x) - float(width) * 0.5) + absf(float(a.y) - float(height) * 0.5)
		var cb := absf(float(b.x) - float(width) * 0.5) + absf(float(b.y) - float(height) * 0.5)
		return ca < cb
	)
	var need := MIN_SIDE_CELLS - count
	var i := 0
	while need > 0 and i < candidates.size():
		var c: Vector2i = candidates[i]
		i += 1
		# 轻微随机跳过，避免补洞太整齐。
		if rng.randf() < 0.25 and need < candidates.size() - i:
			continue
		present[c.y * width + c.x] = true
		need -= 1


## 只保留最大连通块（4 邻），其余标 void，避免浮岛。
static func _keep_largest_component(present: Array, width: int, height: int) -> void:
	var best: Array[Vector2i] = []
	var seen: Dictionary = {}
	for y in range(height):
		for x in range(width):
			var start := Vector2i(x, y)
			if not present[y * width + x] or seen.has(start):
				continue
			var comp: Array[Vector2i] = []
			var stack: Array[Vector2i] = [start]
			seen[start] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				comp.append(c)
				for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var n: Vector2i = c + d
					if n.x < 0 or n.y < 0 or n.x >= width or n.y >= height:
						continue
					if seen.has(n) or not present[n.y * width + n.x]:
						continue
					seen[n] = true
					stack.append(n)
			if comp.size() > best.size():
				best = comp
	if best.is_empty():
		return
	var keep: Dictionary = {}
	for c2 in best:
		keep[c2] = true
	for y2 in range(height):
		for x2 in range(width):
			var cell := Vector2i(x2, y2)
			if present[y2 * width + x2] and not keep.has(cell):
				present[y2 * width + x2] = false
