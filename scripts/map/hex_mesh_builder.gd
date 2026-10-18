class_name HexMeshBuilder
extends RefCounted
## 尖顶六边棱柱网格（XZ 平面）；供 3D 沙盘占位地形。


## 生成底面 y=0、顶面 y=height 的六边棱柱。hex_size 为中心到尖顶距离。
static func build_prism(hex_size: float, height: float) -> ArrayMesh:
	var top_y := maxf(height, 0.02)
	var top := PackedVector3Array()
	var bottom := PackedVector3Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * float(i) - 30.0)
		var x := hex_size * cos(angle)
		var z := hex_size * sin(angle)
		top.append(Vector3(x, top_y, z))
		bottom.append(Vector3(x, 0.0, z))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 顶面（上法线），扇形。
	for i in 6:
		var i1 := (i + 1) % 6
		_add_tri(st, Vector3(0.0, top_y, 0.0), top[i], top[i1], Vector3.UP)

	# 底面（下法线）。
	for i in 6:
		var i1 := (i + 1) % 6
		_add_tri(st, Vector3(0.0, 0.0, 0.0), bottom[i1], bottom[i], Vector3.DOWN)

	# 侧面。
	for i in 6:
		var i1 := (i + 1) % 6
		var outward := ((top[i] + top[i1]) * 0.5)
		outward.y = 0.0
		if outward.length_squared() < 0.0001:
			outward = Vector3.FORWARD
		else:
			outward = outward.normalized()
		_add_tri(st, bottom[i], top[i], top[i1], outward)
		_add_tri(st, bottom[i], top[i1], bottom[i1], outward)

	st.generate_normals()
	return st.commit()


static func _add_tri(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	n: Vector3
) -> void:
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)
