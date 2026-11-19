class_name BoardConfig
extends Resource
## 方格棋盘尺寸与镜头参数。正式数值放 resources/map/board_config.tres。


@export var grid_width: int = 8
@export var grid_height: int = 8
@export var cell_size: float = 1.0
@export var tile_height: float = 0.14
@export var tile_inset: float = 0.98
## 已废弃：对战开局改为内部 seed 成簇生成湖/林（见 ClusterTerrainGenerator）。保留字段以免旧 .tres 报错。
@export_file("*.json") var terrain_map_path: String = ""
@export var color_light: Color = Color("3d4a58")
@export var color_dark: Color = Color("2a3440")
## 2D 斜视：pitch/yaw 参与地面→屏幕正交投影；Camera2D 可见高度基准为 camera_ortho_size（与滚轮 _zoom 相乘）。camera_distance 未使用。
@export var camera_pitch_deg: float = 45.0
@export var camera_yaw_deg: float = 45.0
@export var camera_distance: float = 36.0
@export var camera_ortho_size: float = 10.0
## 产品层缩放下限；实际下限还会与「当前视口刚好看全盘」取更小值，避免竖屏看不全。
@export var camera_zoom_min: float = 0.35
@export var camera_zoom_max: float = 1.9
@export var camera_zoom_default: float = 1.0
## 相对「抓住地图」1:1 的倍率。Camera2D 已用 zoom 把像素换算成世界位移，勿再沿用旧 3D 的 0.02。
@export var camera_pan_sensitivity: float = 1.0
## 灯光 / 投影 / 背景（resources/map/board_look.tres）；为空时用 BoardLook 默认值。
@export var look: BoardLook
## Sprite2D 在格内的目标世界高度（约一格内可辨认，不压满半盘）。
@export var unit_world_height: float = 0.88
