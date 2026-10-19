extends Control

const SANDBOX_SCENE_PATH := "res://scenes/main/sandbox.tscn"
const MAP_EDITOR_SCENE_PATH := "res://scenes/main/map_editor.tscn"
const UiThemeScript := preload("res://scripts/ui/ui_theme.gd")

@onready var _start_button: Button = %StartButton
@onready var _map_editor_button: Button = %MapEditorButton
@onready var _exit_button: Button = %ExitButton
@onready var _version_label: Label = %VersionLabel


func _ready() -> void:
	UiThemeScript.apply(self)
	_start_button.pressed.connect(_on_start_pressed)
	_map_editor_button.pressed.connect(_on_map_editor_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_refresh_version_label()
	if OS.has_feature("web"):
		_exit_button.visible = false
	_start_button.grab_focus()


func _refresh_version_label() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	if version.is_empty():
		version = "0.0.0"
	_version_label.text = "v%s" % version


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(SANDBOX_SCENE_PATH)


func _on_map_editor_pressed() -> void:
	get_tree().change_scene_to_file(MAP_EDITOR_SCENE_PATH)


func _on_exit_pressed() -> void:
	if OS.has_feature("web"):
		return
	get_tree().quit()
