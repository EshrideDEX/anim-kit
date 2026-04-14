@tool
extends EditorPlugin

var bone_dock
var pose_lib_dock
var editor_main_screen: Control

func _enter_tree():
	bone_dock = preload("res://addons/anim_kit/bone_dock.tscn").instantiate()
	bone_dock.name = "AnimKit"
	editor_main_screen = EditorInterface.get_editor_main_screen()
	editor_main_screen.add_child(bone_dock)
	
	pose_lib_dock = EditorDock.new()
	pose_lib_dock.name = "PoseLibDock"
	pose_lib_dock.title = "Pose Library"
	pose_lib_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	
	var pos_lib_contents = preload("res://addons/anim_kit/pose_lib_dock.tscn").instantiate()
	pose_lib_dock.add_child(pos_lib_contents)
	
	add_dock(pose_lib_dock)

func _exit_tree():
	editor_main_screen.remove_child(bone_dock)
	bone_dock.free()
	
	remove_dock(pose_lib_dock)
	pose_lib_dock.free
	
