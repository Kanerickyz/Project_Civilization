extends SceneTree


func _initialize() -> void:
	var smoke_script: Script = load("res://scripts/core/project_load_smoke_test.gd")
	var ok: bool = smoke_script.run_all()
	if ok:
		print("PROJECT_LOAD_SMOKE_OK")
	quit(0 if ok else 1)
