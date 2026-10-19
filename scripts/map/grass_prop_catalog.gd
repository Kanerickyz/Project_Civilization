class_name GrassPropCatalog
extends Resource
## 草地格 Billboard 装饰贴图表（6 种剪纸草簇，由上传 spritesheet 切分）。

const DEFAULT_PATH := "res://resources/terrain/grass_prop_catalog.tres"

@export var prop_textures: Array[Texture2D] = []

static var _default_cache: GrassPropCatalog


static func load_default() -> GrassPropCatalog:
	if _default_cache == null:
		var loaded := load(DEFAULT_PATH)
		if loaded is GrassPropCatalog:
			_default_cache = loaded as GrassPropCatalog
		else:
			push_warning("GrassPropCatalog: missing %s" % DEFAULT_PATH)
			_default_cache = GrassPropCatalog.new()
	return _default_cache
