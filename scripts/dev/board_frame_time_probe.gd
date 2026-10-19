extends SceneTree
## 沙盘帧时间粗测：关 vsync、不限帧，预热后统计 N 帧平均/95 分位（毫秒）。
## 用法：godot --path . --display-driver x11 --rendering-driver opengl3 --resolution 1280x720 \
##   --script res://scripts/dev/board_frame_time_probe.gd -- [frames]

var _frames := 400
var _warmup := 60
var _samples: PackedFloat64Array = PackedFloat64Array()
var _last_us := 0
var _count := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_frames = int(args[0])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.add_child((load("res://scenes/main/sandbox.tscn") as PackedScene).instantiate())


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_count += 1
		if _count > _warmup:
			_samples.append(float(now - _last_us) / 1000.0)
	_last_us = now
	if _samples.size() >= _frames:
		var sorted := _samples.duplicate()
		sorted.sort()
		var total := 0.0
		for s in _samples:
			total += s
		print("FRAME_TIME_MS avg=%.2f p95=%.2f frames=%d renderer=%s" % [
			total / _samples.size(),
			sorted[int(sorted.size() * 0.95)],
			_samples.size(),
			RenderingServer.get_current_rendering_method(),
		])
		quit(0)
	return false
