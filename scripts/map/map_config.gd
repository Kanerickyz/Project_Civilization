class_name MapConfig
extends Resource
## 地图尺寸与生成参数。正式数值放 .tres；下列为可改默认。


@export var map_radius: int = 8
## 3D 六边中心到尖顶距离（世界单位）。可改。
@export var hex_size: float = 1.0
@export var wfc_max_retries: int = 48
## 初始揭开半径：1 = 中心 + 六邻 ≈ 7 格。可改。
@export var initial_reveal_radius: int = 1
@export var fog_color: Color = Color("1e2430cc")
@export var reveal_only_on_player_turn: bool = true
## 战略俯视俯角（度），Civ 式约 45。可改。
@export var camera_pitch_deg: float = 50.0
## 正交相机沿视线的放置距离（不影响缩放，只保证能看见挤出高度）。
@export var camera_distance: float = 40.0
## 正交竖直可视范围（世界单位）；滚轮缩放改此有效值。越小地图越大。
@export var camera_ortho_size: float = 7.2
@export var camera_zoom_min: float = 0.65
@export var camera_zoom_max: float = 1.9
@export var camera_zoom_default: float = 1.05
@export var camera_pan_sensitivity: float = 0.018
