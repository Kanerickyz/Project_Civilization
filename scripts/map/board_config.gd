class_name BoardConfig
extends Resource
## 方格棋盘尺寸与镜头参数。正式数值放 resources/map/board_config.tres。


@export var grid_width: int = 10
@export var grid_height: int = 8
@export var cell_size: float = 1.0
@export var tile_height: float = 0.14
@export var tile_inset: float = 0.94
@export var color_light: Color = Color("3d4a58")
@export var color_dark: Color = Color("2a3440")
## 相对水平面的仰角（度）。战术战棋式斜俯视约 45°。
@export var camera_pitch_deg: float = 45.0
@export var camera_yaw_deg: float = 45.0
@export var camera_distance: float = 36.0
@export var camera_ortho_size: float = 10.0
@export var camera_zoom_min: float = 0.65
@export var camera_zoom_max: float = 1.9
@export var camera_zoom_default: float = 1.0
@export var camera_pan_sensitivity: float = 0.02
## 剪纸 Billboard 在格内的目标世界高度（约一格内可辨认，不压满半盘）。
@export var unit_world_height: float = 0.88
