@tool
extends EditorPlugin

var dock
var copy_btn: Button
var paste_btn: Button
var editor_main_screen: Control

func _enter_tree():
	dock = preload("res://addons/anim_kit/bone_dock.tscn").instantiate()
	dock.name = "AnimKit"
	editor_main_screen = EditorInterface.get_editor_main_screen()
	editor_main_screen.add_child(dock)
	
	call_deferred("_setup_buttons")

func _setup_buttons():
	copy_btn = dock.get_node("%Copy")
	paste_btn = dock.get_node("%Paste")
	
	copy_btn.icon = editor_main_screen.get_theme_icon("ActionCopy", "EditorIcons")
	paste_btn.icon = editor_main_screen.get_theme_icon("ActionPaste", "EditorIcons")

	copy_btn.text = ""
	paste_btn.text = ""

func _exit_tree():
	editor_main_screen.remove_child(dock)
	dock.free()
