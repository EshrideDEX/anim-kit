@tool
class_name PoseLibraryDock extends VBoxContainer

@onready var pose_list: HFlowContainer = $ScrollContainer/PoseList
@onready var new_pose_btn: Button = %NewPose
@onready var info_lable: Label = $Info
@onready var save_btn: Button = %Save
@onready var load_btn: Button = %Load
@onready var delete_btn: Button = %Delete


var editor_main_screen: Control
var skeleton: Skeleton3D

var new_pose_popup: PopupPanel
var new_pose_name_field: LineEdit
var bone_list: ItemList

signal pose_applied

func _ready() -> void:
	editor_main_screen = EditorInterface.get_editor_main_screen()
	_setup_buttons()
	_setup_popups()
	_refresh_pose_buttons()
	
	if pose_list.get_child_count() <= 0:
		$ScrollContainer.hide()
		$HBoxContainer.hide()
		info_lable.text = "No poses created yet.\nCreate a new one!"
	else:
		$ScrollContainer.show()
		$HBoxContainer.hide()
		info_lable.text = ""
		info_lable.hide()

##------------------Pose Managment--------------------##

func _on_new_pose_btn_pressed() -> void:
	if skeleton == null or not is_instance_valid(skeleton):
		info_lable.text = "Select a Skeleton3D first!"
		return
	
	_refresh_bone_list()
	new_pose_popup.popup_centered()
	new_pose_name_field.grab_focus()

func _on_pose_button_gui_input(event: InputEvent, btn_name: String) -> void:
	if event is InputEventMouseButton and event.is_released():
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_delete_pose_file(btn_name)
			call_deferred("_refresh_pose_buttons")

func _on_confirm_create_pose(pose_name: String) -> void:
	if skeleton == null or not is_instance_valid(skeleton):
		info_lable.text = "Select a Skeleton3D first!"
		return
	
	var clean_name := pose_name.strip_edges()
	if clean_name.is_empty():
		return
	
	var pose_file_name := clean_name.to_lower().validate_filename()
	var pose_data := _build_pose_dict(clean_name)
	
	_write_pose_file(pose_file_name, pose_data)
	_refresh_pose_buttons()
	new_pose_popup.hide()
	new_pose_name_field.text = ""

func _add_pose_button(file_name: String, pose_data: Dictionary) -> void:
	var btn := Button.new()
	btn.text = pose_data.get("pose_name", file_name.get_basename())
	btn.name = file_name
	btn.custom_minimum_size = Vector2(75.0, 75.0)
	btn.pressed.connect(_on_pose_button_pressed.bind(file_name))
	btn.gui_input.connect(_on_pose_button_gui_input.bind(file_name))
	btn.tooltip_text = "Middle click to delete this pose"
	pose_list.add_child(btn)

func _on_pose_button_pressed(file_name: String) -> void:
	var dir_path := "user://AnimKit/poses/%s" % _get_skeleton_id()
	var pose_data := _read_pose_file("%s/%s" % [dir_path, file_name])
	
	if pose_data.is_empty():
		return
	
	_apply_pose(pose_data)

func _on_clear_bone_list_selection() -> void:
	bone_list.deselect_all()

func _on_cancel_create_pose() -> void:
	new_pose_popup.hide()

##------------------Read/Write Pose Files--------------------##
func _write_pose_file(pose_name: String, pose_data: Dictionary) -> void:
	var dir_path := _ensure_pose_dir()
	var file_path := "%s/%s.pose.json" % [dir_path, pose_name]
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(pose_data, "\t"))
	file.close()

func _read_pose_file(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	
	var parsed := JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	
	return parsed

func _delete_pose_file(file_name: String) -> void:
	var path := "user://AnimKit/poses/%s/%s" % [_get_skeleton_id(), file_name]
	
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _ensure_pose_dir() -> String:
	var base := "user://AnimKit"
	var poses := "%s/poses" % base
	var skel_dir := "%s/%s" % [poses, _get_skeleton_id()]
	
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("AnimKit"):
		dir.make_dir("AnimKit")
	
	dir = DirAccess.open(base)
	if not dir.dir_exists("poses"):
		dir.make_dir("poses")
	
	dir = DirAccess.open(poses)
	if not dir.dir_exists(_get_skeleton_id()):
		dir.make_dir(_get_skeleton_id())
	
	return skel_dir

func _build_pose_dict(pose_name: String) -> Dictionary:
	var pose := {
		"pose_name" : pose_name,
		"skeleton_id" : _get_skeleton_id(),
		"bones" : {}
	}
	
	for i in range(bone_list.item_count):
		if not bone_list.is_selected(i):
			continue
		
		var bone_name = skeleton.get_bone_name(i)
		var transform = skeleton.get_bone_pose(i)
		
		pose["bones"][bone_name] = {
			"position" : [
				transform.origin.x,
				transform.origin.y,
				transform.origin.z
			],
			"rotation" : [
				transform.basis.get_euler().x,
				transform.basis.get_euler().y,
				transform.basis.get_euler().z
			],
			"scale" : [transform.basis.get_scale().x,
			transform.basis.get_scale().y,
			transform.basis.get_scale().z
			]
		}
	
	return pose

func _apply_pose(pose_data: Dictionary) -> void:
	if skeleton == null or not is_instance_valid(skeleton):
		return
	
	var bones: Dictionary = pose_data.get("bones", {})
	var undo_redo = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Load Pose")
	
	for bone_name in bones.keys():
		var bone_idx := skeleton.find_bone(bone_name)
		if bone_idx == -1:
			continue
		
		var data: Dictionary = bones[bone_name]
		var pos := data.get("position", [0.0, 0.0, 0.0])
		var rot := data.get("rotation", [0.0, 0.0, 0.0])
		var scl := data.get("scale", [1.0, 1.0, 1.0])
		
		var new_transform := Transform3D()
		new_transform.origin = Vector3(pos[0], pos[1], pos[2])
		new_transform.basis = Basis.from_euler(Vector3(rot[0], rot[1], rot[2]))
		new_transform.basis = new_transform.basis.scaled(Vector3(scl[0], scl[1], scl[2]))
		
		var old_transform := skeleton.get_bone_pose(bone_idx)
		undo_redo.add_do_method(skeleton, "set_bone_pose", bone_idx, new_transform)
		undo_redo.add_undo_method(skeleton, "set_bone_pose", bone_idx, old_transform)
	
	undo_redo.add_do_method(self, "_emit_pose_applied")
	undo_redo.add_undo_method(self, "_emit_pose_applied")
	undo_redo.commit_action()

func _emit_pose_applied():
	emit_signal("pose_applied")

##------------------Updates--------------------##

func _refresh_bone_list():
	if skeleton == null or !is_instance_valid(skeleton):
		bone_list.clear()
		return
	
	bone_list.clear()
	
	for i in range(skeleton.get_bone_count()):
		bone_list.add_item(skeleton.get_bone_name(i))

	if skeleton.get_bone_count() > 0:
		for i in range(bone_list.item_count):
			bone_list.select(i, false)

func _refresh_pose_buttons() -> void:
	for child in pose_list.get_children():
		if child != new_pose_btn:
			child.queue_free()
	
	var dir_path := "user://AnimKit/poses/%s" % _get_skeleton_id()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	
	var files: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".pose.json"):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	files.sort()
	
	for fn in files:
		var full_path := "%s/%s" % [dir_path, fn]
		var pose_data := _read_pose_file(full_path)
		if pose_data.is_empty():
			continue
		
		_add_pose_button(fn, pose_data)
	
	if new_pose_btn.get_parent() != pose_list:
		new_pose_btn.reparent(pose_list)
	
	pose_list.move_child(new_pose_btn, -1)

##------------------Shortcuts--------------------##

func _on_pose_popup_window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I and event.is_command_or_control_pressed():
			_invert_bone_list_selection()
			get_viewport().set_input_as_handled() 
		if event.is_action_pressed("ui_accept"):
			_on_confirm_create_pressed()

##------------------Helpers------------------##

func _set_skeleton(new_skeleton: Skeleton3D) -> void:
	if skeleton == new_skeleton:
		return
	
	skeleton = new_skeleton
	
	if skeleton == null:
		pose_list.visible = false
		return
	
	pose_list.visible = true
	
	_refresh_bone_list()
	_refresh_pose_buttons()

func _get_skeleton_id() -> String:
	if skeleton == null or !is_instance_valid(skeleton):
		return ""
	
	if skeleton.has_meta("animkit_id"):
		return skeleton.get_meta("animkit_id")
	
	var id := _generate_uuid()
	skeleton.set_meta("animkit_id", id)
	return id

func _generate_uuid() -> String:
	return "%s_%s" % [Time.get_unix_time_from_system(), randi()]

func _invert_bone_list_selection() -> void:
	for i in range(bone_list.get_item_count()):
		if bone_list.is_selected(i):
			bone_list.deselect(i)
		else:
			bone_list.select(i, false)

##------------------Additional Setup--------------------##

func _setup_buttons() -> void:
	new_pose_btn.text = ""
	new_pose_btn.icon = editor_main_screen.get_theme_icon("Add", "EditorIcons")
	
	save_btn.text = ""
	save_btn.icon = editor_main_screen.get_theme_icon("Save", "EditorIcons")
	load_btn.text = ""
	load_btn.icon = editor_main_screen.get_theme_icon("Load", "EditorIcons")
	delete_btn.text = ""
	delete_btn.icon = editor_main_screen.get_theme_icon("Remove", "EditorIcons")

func _on_confirm_create_pressed() -> void:
	_on_confirm_create_pose(new_pose_name_field.text)

func _setup_popups() -> void:
	new_pose_popup = PopupPanel.new()
	new_pose_popup.window_input.connect(_on_pose_popup_window_input)
	
	var vbox = VBoxContainer.new()
	new_pose_popup.add_child(vbox)
	
	var scroll_cont = ScrollContainer.new()
	scroll_cont.custom_minimum_size = Vector2(0.0, 180.0)
	scroll_cont.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	bone_list = ItemList.new()
	bone_list.select_mode = ItemList.SELECT_MULTI
	bone_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bone_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_cont.add_child(bone_list)
	vbox.add_child(scroll_cont)
	
	var hbox_top = HBoxContainer.new()
	new_pose_name_field = LineEdit.new()
	new_pose_name_field.placeholder_text = "Enter pose name..."
	new_pose_name_field.mouse_filter = Control.MOUSE_FILTER_PASS
	new_pose_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_pose_name_field.text_submitted.connect(_on_confirm_create_pose)
	hbox_top.add_child(new_pose_name_field)
	var info_icn = TextureRect.new()
	info_icn.texture = editor_main_screen.get_theme_icon("NodeInfo", "EditorIcons")
	info_icn.tooltip_text = "Use Ctrl + I (or Cmd + I) to invert current bone selection"
	info_icn.custom_minimum_size = Vector2(16, 16)
	info_icn.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	info_icn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hbox_top.add_child(info_icn)
	vbox.add_child(hbox_top)
	
	var hbox_bottom = HBoxContainer.new()
	var confirm_btn = Button.new()
	confirm_btn.text = "Create"
	confirm_btn.pressed.connect(_on_confirm_create_pressed)
	hbox_bottom.add_child(confirm_btn)
	var clear_btn = Button.new()
	clear_btn.text = "Clear"
	clear_btn.pressed.connect(_on_clear_bone_list_selection)
	hbox_bottom.add_child(clear_btn)
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel_create_pose)
	hbox_bottom.add_child(cancel_btn)
	
	vbox.add_child(hbox_bottom)
	
	add_child(new_pose_popup)
