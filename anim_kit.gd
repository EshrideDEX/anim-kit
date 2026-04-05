@tool
extends EditorPlugin

var dock
var editor_main_screen: Control

func _enter_tree():
	dock = preload("res://addons/anim_kit/bone_dock.tscn").instantiate()
	dock.name = "AnimKit"
	editor_main_screen = EditorInterface.get_editor_main_screen()
	editor_main_screen.add_child(dock)

func _exit_tree():
	editor_main_screen.remove_child(dock)
	dock.free()
