class_name TerrainType
extends RefCounted
## 第一版地形大类 ID。顺序勿重排（若以后写入 .tres 序列化）。


enum Id {
	OCEAN,
	BEACH,
	GRASSLAND,
	FOREST,
	HILLS,
	MOUNTAIN,
	DESERT,
	MARSH,
	SNOW,
}


const COUNT := 9


static func display_name(id: int) -> String:
	match id:
		Id.OCEAN:
			return "海洋"
		Id.BEACH:
			return "沙滩"
		Id.GRASSLAND:
			return "草原"
		Id.FOREST:
			return "森林"
		Id.HILLS:
			return "丘陵"
		Id.MOUNTAIN:
			return "山地"
		Id.DESERT:
			return "沙漠"
		Id.MARSH:
			return "沼泽"
		Id.SNOW:
			return "雪原"
		_:
			return "未知"


## 3D 占位挤出高度（世界单位）。分层夸大以便 ~45° 俯视可读，非最终美术。
static func placeholder_height(id: int) -> float:
	match id:
		Id.OCEAN:
			return 0.12
		Id.BEACH:
			return 0.28
		Id.GRASSLAND:
			return 0.62
		Id.FOREST:
			return 1.05
		Id.HILLS:
			return 1.45
		Id.MOUNTAIN:
			return 2.25
		Id.DESERT:
			return 0.55
		Id.MARSH:
			return 0.38
		Id.SNOW:
			return 0.8
		_:
			return 0.5


## 占位色：可读区分即可，非最终美术。
static func placeholder_color(id: int) -> Color:
	match id:
		Id.OCEAN:
			return Color("2a5f8f")
		Id.BEACH:
			return Color("e8d5a3")
		Id.GRASSLAND:
			return Color("6b9e4a")
		Id.FOREST:
			return Color("2d6a3e")
		Id.HILLS:
			return Color("8b7355")
		Id.MOUNTAIN:
			return Color("6e6e6e")
		Id.DESERT:
			return Color("d4a84b")
		Id.MARSH:
			return Color("4f7a5c")
		Id.SNOW:
			return Color("e8eef5")
		_:
			return Color("ff00ff")


## 开局中心簇强制可站陆地（不含海/滩/山地）。可改。
static func is_start_land(id: int) -> bool:
	return id == Id.GRASSLAND or id == Id.FOREST or id == Id.HILLS \
		or id == Id.DESERT or id == Id.MARSH or id == Id.SNOW
