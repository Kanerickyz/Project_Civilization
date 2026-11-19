extends SceneTree
## 已由 pc98_random_shape_capture.gd 取代（10×8/8×10 随机边缘）。
## 保留入口：转发到随机预览脚本的默认路径。

const FWD := "res://scripts/dev/pc98_random_shape_capture.gd"


func _initialize() -> void:
	push_warning("pc98_irregular_edge_capture: forwarding to pc98_random_shape_capture")
	var script: GDScript = load(FWD) as GDScript
	if script == null:
		push_error("forward target missing")
		quit(1)
		return
	var runner: SceneTree = script.new() as SceneTree
	# SceneTree scripts expect to be the main loop; just document deprecation.
	push_error(
		"Use: godot --path . --script res://scripts/dev/pc98_random_shape_capture.gd -- <out.png>"
	)
	quit(1)
