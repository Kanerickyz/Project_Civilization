class_name MapConfig
extends Resource
## 地图尺寸与生成参数。正式数值放 .tres；下列为可改默认。


@export var map_radius: int = 8
@export var hex_size: float = 26.0
@export var wfc_max_retries: int = 32
## 初始揭开半径：1 = 中心 + 六邻 ≈ 7 格。可改。
@export var initial_reveal_radius: int = 1
@export var fog_color: Color = Color("1e2430cc")
@export var reveal_only_on_player_turn: bool = true
