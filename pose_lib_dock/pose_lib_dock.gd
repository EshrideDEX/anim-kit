@tool
class_name PoseLibraryDock extends VBoxContainer

@onready var pose_list: ItemList = $ScrollContainer/PoseList
@onready var new_pose_btn: Button = $NewPose
@onready var info_lable: Label = $Info

var editor_main_screen: Control

func _ready() -> void:
	editor_main_screen = EditorInterface.get_editor_main_screen()
	_setup_buttons()
	
	if pose_list.item_count <= 0:
		new_pose_btn.show()
		$ScrollContainer.hide()
		$HBoxContainer.hide()
		info_lable.text = "No poses created yet.\nCreate a new one!"
	else:
		new_pose_btn.hide()
		$ScrollContainer.show()
		$HBoxContainer.hide()
		info_lable.text = ""
		info_lable.hide()

func _setup_buttons() -> void:
	new_pose_btn.text = ""
	new_pose_btn.icon = editor_main_screen.get_theme_icon("Add", "EditorIcons")
