class_name BoardEdgeShape
extends RefCounted
## 默认对战盘边缘不规则缩进：在约 8×8 外包内缺边角格，避免规整正方。


const VOID_ID := &"void"

## 8×8 行掩码：1=在盘，0=盘外 void。形状故意不对称。
const MASK_8X8: Array = [
	[0, 1, 1, 1, 1, 0, 0, 0],
	[1, 1, 1, 1, 1, 1, 0, 0],
	[1, 1, 1, 1, 1, 1, 1, 0],
	[1, 1, 1, 1, 1, 1, 1, 1],
	[0, 1, 1, 1, 1, 1, 1, 1],
	[1, 1, 1, 1, 1, 1, 1, 0],
	[0, 1, 1, 1, 1, 1, 0, 0],
	[0, 0, 1, 1, 1, 1, 0, 0],
]


## 返回应标为 void 的格子；非 8×8 默认不缩进。
static func void_cells(width: int, height: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if width != 8 or height != 8:
		return out
	for y in range(8):
		var row: Array = MASK_8X8[y]
		for x in range(8):
			if int(row[x]) == 0:
				out.append(Vector2i(x, y))
	return out


## 把 void 写入 MapData（覆盖湖/林）。
static func apply_to_map(map: MapData) -> void:
	if map == null:
		return
	for cell in void_cells(map.width, map.height):
		map.set_cell_vec(cell, VOID_ID)


## 把 void 写入棋盘地形字典。
static func apply_to_board(board: TacticalBoard) -> void:
	if board == null:
		return
	var cells := board.terrain_cells()
	for cell in void_cells(board.grid_width, board.grid_height):
		cells[cell] = VOID_ID
	board.set_terrain_cells(cells)
