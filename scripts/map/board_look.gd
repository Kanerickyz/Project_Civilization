class_name BoardLook
extends Resource
## 棋盘画面：主光 / 天光补光 / 投影 / 背景 / 调色。正式数值见 resources/map/board_look.tres。
## 全部效果在 GL Compatibility（含 Web）可用。Web 回退：shadow_on_web=false 时不画实时投影（Compatibility
## 每盏带影灯多一遍绘制），角色仍有脚下软影；post_adjust_on_web=false 时只保留 tonemap。


@export_group("Key light")
@export var key_color: Color = Color("ffefd6")
@export var key_energy: float = 0.8
## 俯角（度，负值朝下）与偏航（度）。偏航 -90° ≈ 影子落向屏幕右下。
@export var key_pitch_deg: float = -50.0
@export var key_yaw_deg: float = -70.0

@export_group("Shadow")
@export var shadow_enabled: bool = true
## Web 上是否画实时投影；默认关以保帧时，城墙影子在 Web 上缺席。
@export var shadow_on_web: bool = false
@export var shadow_opacity: float = 1.0
@export var shadow_blur: float = 0.6
@export var shadow_max_distance: float = 70.0
@export var shadow_bias: float = 0.05
@export var shadow_normal_bias: float = 1.0

@export_group("Sky fill")
@export var ambient_color: Color = Color("9fb6d0")
@export var ambient_energy: float = 0.36
@export var background_color: Color = Color("56603a")

@export_group("Color grading")
@export var tonemap_mode: Environment.ToneMapper = Environment.TONE_MAPPER_LINEAR
@export var tonemap_exposure: float = 1.0
@export var tonemap_white: float = 1.0
@export var post_adjust_enabled: bool = true
## Web 上额外的全屏调色 pass；低端设备可关，关后只少一层饱和/对比微调。
@export var post_adjust_on_web: bool = true
@export var adjust_brightness: float = 1.0
@export var adjust_contrast: float = 1.06
@export var adjust_saturation: float = 0.88

@export_group("Units")
## Billboard 角色脚下软影（不透明度 0 = 关）。
@export var unit_blob_opacity: float = 0.62
@export var unit_blob_radius: float = 0.46
## 角色乘色，让剪纸与暖光场景同调。
@export var unit_modulate: Color = Color("fff6e8")


func shadow_active() -> bool:
	if not shadow_enabled:
		return false
	if OS.has_feature("web") and not shadow_on_web:
		return false
	return true


func post_adjust_active() -> bool:
	if not post_adjust_enabled:
		return false
	if OS.has_feature("web") and not post_adjust_on_web:
		return false
	return true
