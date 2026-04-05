@tool
extends EditorPlugin

var dock

func _enter_tree():
	dock = preload("res://addons/anim_kit/bone_dock.tscn").instantiate()
	dock.name = "AnimKit"
	var editor_main_screen = get_editor_interface().get_editor_main_screen()
	editor_main_screen.add_child(dock)

func _exit_tree():
	var editor_main_screen = get_editor_interface().get_editor_main_screen()
	editor_main_screen.remove_child(dock)
	dock.free()
