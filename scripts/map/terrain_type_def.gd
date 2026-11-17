class_name TerrainTypeDef
extends Resource
## 一种地块类型：可通行性 + 表现引用。条目放 resources/terrain/*.tres，由 TerrainCatalog 汇总。


## 存档与代码中引用的稳定 id（JSON v2 写入此值）。
@export var id: StringName = &""
@export var display_name: String = ""
@export var passable: bool = true
## 中间格挡普攻视线（如树林）；邻格攻击不受影响。城墙默认 false。
@export var blocks_attack: bool = false
## 单位进入该格时清除燃烧层数（如湖泊）。
@export var clears_burn_on_enter: bool = false
## 该格不点燃；站在其上的单位不受燃烧施加（如湖泊）。
@export var burn_immune: bool = false
## tactical_map_v1 旧整数码（0 可走 / 1 不可走）；-1 表示无旧码。
@export var legacy_code: int = -1
## 网格缺失时的回退色，也用于地块顶面。
@export var editor_color: Color = Color("6f9a3c")
@export var mesh: Mesh
## 按 surface 序覆盖 mesh 材质；为空时用 mesh 自带材质。
@export var surface_materials: Array[Material] = []
## 直线型地块（如直城墙）按相邻同类自动转向：仅南北有同类时转 90°。
@export var orient_to_neighbors: bool = false
