@tool
extends Control

@onready var bone_list = $VBoxContainer/ScrollContainer/BoneList
@onready var transform_panel: TabContainer = %TransformPanel
@onready var copy_btn: Button = %Copy
@onready var paste_btn: Button = %Paste
@onready var trans_p_btn: Button = %TransP

@onready var transform_fields = {
	"location" : [%LocX, %LocY, %LocZ],
	"rotation" : [%RotX, %RotY, %RotZ],
	"scale" : [%ScaX, %ScaY, %ScaZ],
}

var skeleton: Skeleton3D
var copied_transform: Transform3D
var edit_start_transform: Transform3D
var editor_main_screen: Control

var dragging := false
var last_drag_x := 0

var bone_idx: int

var current_location: Vector3
var current_euler: Vector3
var current_scale: Vector3

func _ready():
	set_process(true)
	editor_main_screen = EditorInterface.get_editor_main_screen()
	
	transform_panel.hide()
	call_deferred("_setup_buttons")
	
	var types = ["loc", "rot", "sca"]
	var axes = ["x", "y", "z"]

	for type in types:
		for axis in axes:
			var node_name = type.capitalize() + axis.capitalize()
			var node = get_node("%" + node_name)
			
			node.text_submitted.connect(_on_transform_changed.bind(type, axis))
			node.focus_entered.connect(_on_focus_entered.bind(node, type, axis))
			node.focus_exited.connect(_on_focus_lost.bind(node, type, axis))
			node.gui_input.connect(_on_line_edit_gui_input.bind(type, axis, node))

func _process(_delta):
	_update_skeleton()
	_update_bone_list()
	_check_bone_external_transform_change()

##------------------Handle Focus--------------------##

func _on_focus_entered(node: LineEdit) -> void:
	if skeleton == null:
		return
		
	var idx = _get_selected_bone_index()
	if idx == -1:
		return
	
	edit_start_transform = skeleton.get_bone_pose(idx)

func _on_focus_lost(node: LineEdit, type: String, axis: String):
	if not node.text.is_valid_float():
		return
	
	_apply_transform(false)

##------------------Updates--------------------##

func _update_skeleton():
	var selection = EditorInterface.get_selection()
	var nodes = selection.get_selected_nodes()
	var skeleton_selected = false
	
	skeleton = null

	for node in nodes:
		if node is Skeleton3D:
			skeleton = node
			skeleton_selected = true
			break
	
	visible = skeleton_selected


func _update_bone_list():
	if skeleton == null:
		bone_list.clear()
		bone_idx = -1
		return

	if bone_list.item_count != skeleton.get_bone_count():
		bone_list.clear()

		for i in range(skeleton.get_bone_count()):
			bone_list.add_item(skeleton.get_bone_name(i))
	

##------------------Bone Selection--------------------##

func _get_selected_bone_index():
	var selected = bone_list.get_selected_items()
	if selected.size() == 0:
		return -1
	return selected[0]

func _on_bone_selected(index: int) -> void:
	bone_idx = index
	_update_current_transform()

##------------------Copy/Paste--------------------##

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

	var undo_redo = EditorInterface.get_editor_undo_redo()

	var old_transform: Transform3D = skeleton.get_bone_pose(bone_idx)

	# Convert copied GLOBAL → LOCAL
	var parent_idx: int = skeleton.get_bone_parent(bone_idx)
	var new_transform: Transform3D

	if parent_idx == -1:
		# Root bone
		new_transform = copied_transform
	else:
		var parent_global: Transform3D = skeleton.get_bone_global_pose(parent_idx)
		new_transform = parent_global.affine_inverse() * copied_transform
	
	# Paste undo/redo
	undo_redo.create_action("Paste Bone Transform (World)")

	undo_redo.add_do_method(skeleton, "set_bone_pose", bone_idx, new_transform)
	undo_redo.add_undo_method(skeleton, "set_bone_pose", bone_idx, old_transform)

	undo_redo.add_do_method(self, "_update_current_transform")
	undo_redo.add_undo_method(self, "_update_current_transform")

	undo_redo.commit_action()

func _on_paste_mirrored_pressed() -> void:
	if skeleton == null:
		return

	var bone_idx = _get_selected_bone_index()
	if bone_idx == -1:
		return

	var bone_name = skeleton.get_bone_name(bone_idx)
	var target_name = _get_mirrored_bone_name(bone_name)

	var target_idx = skeleton.find_bone(target_name)
	if target_idx == -1:
		print("No mirrored bone found for: ", bone_name)
		return

	var undo_redo = EditorInterface.get_editor_undo_redo()
	var old_transform: Transform3D = skeleton.get_bone_pose(target_idx)
	var mirrored_global: Transform3D = _mirror_transform(copied_transform)
	
	# Convert copied GLOBAL → LOCAL
	var parent_idx: int = skeleton.get_bone_parent(target_idx)
	var new_transform: Transform3D

	if parent_idx == -1:
		new_transform = mirrored_global
	else:
		var parent_global: Transform3D = skeleton.get_bone_global_pose(parent_idx)
		new_transform = parent_global.affine_inverse() * mirrored_global

	# Paste mirrored undo/redo
	undo_redo.create_action("Paste Mirrored Bone Transform")

	undo_redo.add_do_method(skeleton, "set_bone_pose", target_idx, new_transform)
	undo_redo.add_undo_method(skeleton, "set_bone_pose", target_idx, old_transform)

	undo_redo.add_do_method(self, "_update_current_transform")
	undo_redo.add_undo_method(self, "_update_current_transform")

	undo_redo.commit_action()

func _on_paste_button_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if Input.is_key_pressed(KEY_SHIFT):
			_on_paste_mirrored_pressed()
		else:
			_on_paste_pressed()

func _get_mirrored_bone_name(name: String) -> String:
	var replacements = [
		[".L", ".R"],
		["_L", "_R"],
		["-L", "-R"],
		[" L", " R"],
		["Left", "Right"],
		["left", "right"]
	]

	for pair in replacements:
		if name.contains(pair[0]):
			return name.replace(pair[0], pair[1])
		if name.contains(pair[1]):
			return name.replace(pair[1], pair[0])

	return name

func _mirror_transform(t: Transform3D, axis: String = "x") -> Transform3D:
	var flip := Vector3(1, 1, 1)

	match axis:
		"x": flip.x = -1
		"y": flip.y = -1
		"z": flip.z = -1

	var mirror := Basis(
		Vector3(flip.x, 0, 0),
		Vector3(0, flip.y, 0),
		Vector3(0, 0, flip.z)
	)

	var mirrored := Transform3D()

	mirrored.origin = mirror * t.origin
	mirrored.basis = mirror * t.basis * mirror

	return mirrored

##------------------Handle Transforms--------------------##

func _update_current_transform():
	if bone_idx == -1 or skeleton == null:
		return
	var transform = skeleton.get_bone_pose(bone_idx)
	current_location = transform.origin
	current_scale = transform.basis.get_scale()
	current_euler = transform.basis.get_euler() * (180.0 / PI)
	
	var data_map = {
		"location": current_location,
		"rotation": current_euler,
		"scale": current_scale
	}

	for key in transform_fields:
		var vector_value = data_map[key]
		var nodes = transform_fields[key]
		
		nodes[0].text = str(snapped(vector_value.x, 0.001))
		nodes[1].text = str(snapped(vector_value.y, 0.001))
		nodes[2].text = str(snapped(vector_value.z, 0.001))

func _on_transform_changed(new_text: String, type: String, axis: String) -> void:
	if not new_text.is_valid_float(): return
	var val = float(new_text)
	
	match type:
		"loc": current_location[axis] = val
		"rot": current_euler[axis] = val
		"sca": current_scale[axis] = max(val, 0.001) # Safety clamp so scale won't reach 0
	
	_apply_transform()

func _check_bone_external_transform_change():
	if bone_idx == -1 or skeleton == null:
		return
	
	var transform = skeleton.get_bone_pose(bone_idx)
	var bone_loc = transform.origin
	var bone_scale = transform.basis.get_scale()
	var bone_euler = transform.basis.get_euler() * 180.0 / PI
	
	# Only update transforms when user is not actively editing fields
	for key in transform_fields:
		var nodes = transform_fields[key]
		for node in nodes:
			if node.has_focus():
				return
	# Check if anything changed
	if bone_loc != current_location or bone_scale != current_scale or bone_euler != current_euler:
		current_location = bone_loc
		current_scale = bone_scale
		current_euler = bone_euler
		_update_current_transform()

func _apply_transform(live := true) -> void:
	if bone_idx == -1:
		return
	
	var rad_euler = current_euler * (PI / 180.0)
	var new_basis = Basis.from_euler(rad_euler)
	new_basis = new_basis.scaled(current_scale)
	var new_transform = Transform3D(new_basis, current_location)

	if live:
		# Real-time preview (NO undo)
		skeleton.set_bone_pose(bone_idx, new_transform)
	else:
		# Final commit (WITH undo)
		_commit_transform_with_undo(new_transform)

func _commit_transform_with_undo(new_transform: Transform3D) -> void:
	var undo_redo = EditorInterface.get_editor_undo_redo()

	var old_transform = edit_start_transform

	undo_redo.create_action("Transform Bone")

	undo_redo.add_do_method(skeleton, "set_bone_pose", bone_idx, new_transform)
	undo_redo.add_undo_method(skeleton, "set_bone_pose", bone_idx, old_transform)

	undo_redo.commit_action()

##------------------Gestures--------------------##
func _on_line_edit_gui_input(event: InputEvent, type: String, axis: String, node: LineEdit) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			var step = 0.1 if event.ctrl_pressed else 1.0
			_increment_field(node, type, axis, step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			var step = 0.1 if event.ctrl_pressed else 1.0
			_increment_field(node, type, axis, -step)

func _increment_field(node: LineEdit, type: String, axis: String, step: float):
	if not node.text.is_valid_float():
		return
	
	var value = float(node.text)
	
	if type == "rot":
		value += step*10
	else:
		value += step/10
	
	if type == "sca":
		value = max(value, 0.001)
	
	node.text = str(snapped(value, 0.001))
	_on_transform_changed(node.text, type, axis)

##------------------Additional Setup--------------------##

func _on_transform_panel_btn_toggled(pressed: bool) -> void:
	transform_panel.visible = pressed

func _setup_buttons():
	copy_btn.icon = editor_main_screen.get_theme_icon("ActionCopy", "EditorIcons")
	paste_btn.icon = editor_main_screen.get_theme_icon("ActionPaste", "EditorIcons")

	copy_btn.text = ""
	paste_btn.text = ""
