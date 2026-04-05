@tool
extends Control

@onready var bone_list = $VBoxContainer/ScrollContainer/BoneList
@onready var copy_btn = $VBoxContainer/HBoxContainer/Copy
@onready var paste_btn = $VBoxContainer/HBoxContainer/Paste

var skeleton: Skeleton3D
var copied_transform: Transform3D


func _ready():
	set_process(true)
	copy_btn.pressed.connect(_on_copy_pressed)
	paste_btn.pressed.connect(_on_paste_pressed)


func _process(_delta):
	_update_skeleton()
	_update_bone_list()


func _update_skeleton():
	var selection = EditorInterface.get_selection()
	var nodes = selection.get_selected_nodes()
	
	skeleton = null

	for node in nodes:
		if node is Skeleton3D:
			skeleton = node
			#print("Found Skeleton: %s" % skeleton)
			return


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


func _on_copy_pressed():
	if skeleton == null:
		return

	var bone_idx = _get_selected_bone_index()
	if bone_idx == -1:
		return

	copied_transform = skeleton.get_bone_global_pose(bone_idx)


func _on_paste_pressed():
	if skeleton == null:
		return

	var bone_idx = _get_selected_bone_index()
	if bone_idx == -1:
		return

	skeleton.set_bone_global_pose(bone_idx, copied_transform)
