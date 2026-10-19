class_name GrassTileDecor
extends RefCounted
## 按格坐标种子在草地格上摆放 Sprite3D 草簇（Y 轴 Billboard）。

const GLOBAL_SEED := 918273645
const GRASS_TERRAIN_ID := &"grass"


static func should_decorate(terrain_id: StringName) -> bool:
	return terrain_id == GRASS_TERRAIN_ID


static func sync_cell(
	host: Node3D,
	cell: Vector2i,
	world_center: Vector3,
	config: BoardConfig,
	textures: Array[Texture2D],
	terrain_id: StringName
) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.free()
	if config == null or not should_decorate(terrain_id) or textures.is_empty():
		return
	var rng := _cell_rng(cell)
	var inset := config.cell_size * config.tile_inset
	var half := inset * 0.42
	var count := rng.randi_range(0, 3)
	var top_y := config.tile_height
	for _i in count:
		var tex: Texture2D = textures[rng.randi_range(0, textures.size() - 1)]
		if tex == null:
			continue
		var spr := Sprite3D.new()
		spr.name = "GrassProp"
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spr.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.92, 1.0))
		var world_h := config.cell_size * rng.randf_range(0.13, 0.21)
		var tex_h := float(tex.get_height())
		if tex_h > 0.0:
			spr.pixel_size = world_h / tex_h
		var ox := rng.randf_range(-half, half)
		var oz := rng.randf_range(-half, half)
		spr.position = Vector3(world_center.x + ox, top_y, world_center.z + oz)
		spr.rotation_degrees.y = rng.randf_range(0.0, 360.0)
		host.add_child(spr)


static func _cell_rng(cell: Vector2i) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash(Vector3i(cell.x, cell.y, GLOBAL_SEED)))
	return rng
