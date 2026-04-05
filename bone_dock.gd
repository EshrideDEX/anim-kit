@tool
extends Control

@onready var bone_list = $VBoxContainer/ScrollContainer/BoneList
@onready var transform_panel: TabContainer = %TransformPanel
@onready var copy_btn: Button = %Copy
@onready var paste_btn: Button = %Paste
@onready var trans_p_btn: Button = %TransP

var skeleton: Skeleton3D
var copied_transform: Transform3D
var editor_main_screen: Control


func _ready():
	set_process(true)
	editor_main_screen = EditorInterface.get_editor_main_screen()
	
	transform_panel.hide()
	call_deferred("_setup_buttons")


func _process(_delta):
	_update_skeleton()
	_update_bone_list()


func _update_skeleton():
	var selection = EditorInterface.get_selection()
	var nodes = selection.get_selected_nodes()
	var skeleton_selected = false
	
	skeleton = null

	for node in nodes:
		if node is Skeleton3D:
			skeleton = node
			skeleton_selected = true
			#print("Found Skeleton: %s" % skeleton)
			break
	
	visible = skeleton_selected


func _update_bone_list():
	if skeleton == null:
		bone_list.clear()
		return

	if bone_list.item_count != skeleton.get_bone_count():
		bone_list.clear()

		for i in skeleton.get_bone_count():
			bone_list.add_item(skeleton.get_bone_name(i))
			#print("Added bone %s to bone list" % skeleton.get_bone_name(i))


func _get_selected_bone_index():
	var selected = bone_list.get_selected_items()
	if selected.size() == 0:
		return -1
	return selected[0]


func _on_copy_pressed() -> void:
	if skeleton == null:
		return

	var bone_idx = _get_selected_bone_index()
	if bone_idx == -1:
		return

	copied_transform = skeleton.get_bone_global_pose(bone_idx)


func _on_paste_pressed() -> void:
	if skeleton == null:
		return

	var bone_idx = _get_selected_bone_index()
	if bone_idx == -1:
		return

	skeleton.set_bone_global_pose(bone_idx, copied_transform)

func _on_transform_panel_btn_toggled(pressed: bool) -> void:
	transform_panel.visible = pressed

func _setup_buttons():
	copy_btn.icon = editor_main_screen.get_theme_icon("ActionCopy", "EditorIcons")
	paste_btn.icon = editor_main_screen.get_theme_icon("ActionPaste", "EditorIcons")

	copy_btn.text = ""
	paste_btn.text = ""
