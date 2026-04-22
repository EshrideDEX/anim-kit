@tool
extends EditorPlugin

var bone_dock
var pose_lib_dock
var pose_lib_contents
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
	
	pose_lib_contents = preload("res://addons/anim_kit/pose_lib_dock.tscn").instantiate()
	pose_lib_dock.add_child(pose_lib_contents)
	
	add_dock(pose_lib_dock)
	
	pose_lib_contents.pose_applied.connect(bone_dock._update_current_transform)
	
	EditorInterface.get_selection().selection_changed.connect(_update_skeleton)
	
func _update_skeleton():
	var selection = EditorInterface.get_selection()
	var nodes = selection.get_selected_nodes()
	var found_skeleton: Skeleton3D = null

	for node in nodes:
		if node is Skeleton3D:
			found_skeleton = node
			break
	
	bone_dock.skeleton = found_skeleton
	
	var contents = pose_lib_dock.get_child(0)
	if contents:
		contents._set_skeleton(found_skeleton)

func _exit_tree():
	editor_main_screen.remove_child(bone_dock)
	bone_dock.free()
	
	remove_dock(pose_lib_dock)
	pose_lib_dock.free()
	
