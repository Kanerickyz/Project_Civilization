class_name StrategicFog
extends RefCounted
## 整局战略迷雾；分边已揭开集合（本切片默认）。可改。


enum Side {
	PLAYER,
	RIVAL,
}


var _revealed: Dictionary = {
	Side.PLAYER: {},
	Side.RIVAL: {},
}


func clear() -> void:
	_revealed[Side.PLAYER] = {}
	_revealed[Side.RIVAL] = {}


func reveal(side: int, cell: Vector2i) -> void:
	(_revealed[side] as Dictionary)[cell] = true


func reveal_many(side: int, cells: Array[Vector2i]) -> void:
	for cell in cells:
		reveal(side, cell)


func is_revealed(side: int, cell: Vector2i) -> bool:
	return (_revealed[side] as Dictionary).has(cell)


func revealed_cells(side: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for key in (_revealed[side] as Dictionary).keys():
		out.append(key as Vector2i)
	return out


## 与己方已揭开格邻接的未揭开格才可点开。
func can_reveal(side: int, cell: Vector2i, map_radius: int) -> bool:
	if is_revealed(side, cell):
		return false
	if not HexCoords.in_radius(cell, map_radius):
		return false
	for n in HexCoords.neighbors_in_radius(cell, map_radius):
		if is_revealed(side, n):
			return true
	return false


func try_reveal(side: int, cell: Vector2i, map_radius: int) -> bool:
	if not can_reveal(side, cell, map_radius):
		return false
	reveal(side, cell)
	return true
