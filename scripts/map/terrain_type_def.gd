class_name TerrainTypeDef
extends Resource
## 一种地块类型：可通行性 + 表现引用。条目放 resources/terrain/*.tres，由 TerrainCatalog 汇总。


## 存档与代码中引用的稳定 id（JSON v2 写入此值）。
@export var id: StringName = &""
@export var display_name: String = ""
@export var passable: bool = true
## tactical_map_v1 旧整数码（0 可走 / 1 不可走）；-1 表示无旧码。
@export var legacy_code: int = -1
## 网格缺失时的回退色，也用于编辑器图例。
@export var editor_color: Color = Color("6f9a3c")
@export var mesh: Mesh
## 按 surface 序覆盖 mesh 材质；为空时用 mesh 自带材质。
@export var surface_materials: Array[Material] = []
## 直线型地块（如直城墙）按相邻同类自动转向：仅南北有同类时转 90°。
@export var orient_to_neighbors: bool = false
