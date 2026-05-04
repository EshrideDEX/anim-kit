@tool
extends Control

@onready var bone_list: ItemList = %BoneList
@onready var transform_panel: VBoxContainer = %TransformPanel
@onready var copy_btn: Button = %Copy
@onready var paste_btn: Button = %Paste
@onready var trans_p_btn: Button = %TransP
@onready var mirror_axis_btn: Button = %MirrorAxis
@onready var pose_mirror_btn: Button = %PoseMirror
@onready var collapse_btn: Button = %Collapse
@onready var selection_label: Label = %SelectionLabel

@onready var transform_fields = {
	"location" : [%LocX, %LocY, %LocZ],
	"rotation" : [%RotX, %RotY, %RotZ],
	"scale" : [%ScaX, %ScaY, %ScaZ],
}

# Skeleton, Transforms, and Setup
var skeleton: Skeleton3D
var copied_transforms: Array = []
var edit_start_transform: Transform3D
var editor_main_screen: Control

# Scrolling
var scroll_start_transforms: Dictionary = {}
var scroll_start_bases: Dictionary = {}
var scroll_start_scales: Dictionary = {}
var scroll_live_scales: Dictionary = {}
var scroll_timer: float = 0.0
var scroll_accumulated_delta := 0.0
var scroll_current_values := {}
var scroll_dirty := false
var is_scrolling := false

# Current State
var bone_idxs: Array

var current_location: Vector3
var current_euler: Vector3
var current_scale: Vector3

var mirror_axis := "x"
var suppress_field_signals := false

# Visuals
var ma_btn_style_nrm := StyleBoxFlat.new()
var ma_btn_style_pressed := StyleBoxFlat.new()

var bone_tween: Tween
var glow_tween: Tween
var _hovered := false

func _ready():
	set_process(true)
	editor_main_screen = EditorInterface.get_editor_main_screen()
	
	transform_panel.hide()
	call_deferred("_setup_buttons")
	
	bone_list.item_selected.connect(_on_bone_selection_changed)
	bone_list.multi_selected.connect(_on_bone_selection_changed)
	
	var types = ["loc", "rot", "sca"]
	var axes = ["x", "y", "z"]

	for type in types:
		for axis in axes:
			var node_name = type.capitalize() + axis.capitalize()
			var node: LineEdit = get_node("%" + node_name)
			
			node.text_changed.connect(_on_transform_changed.bind(type, axis))
			node.text_submitted.connect(_on_transform_submitted.bind(type, axis))
			node.focus_entered.connect(_on_tfield_focus_entered.bind(node))
			node.focus_exited.connect(_on_tfield_focus_lost.bind(node))
			node.gui_input.connect(_on_line_edit_gui_input.bind(type, axis, node))
			
			node.max_length = 24
	
	_set_dock_focus(false)

func _process(delta):
	_update_skeleton()
	_update_bone_list()
	_check_bone_external_transform_change()
	if is_scrolling:
		scroll_timer -= delta
		
		if scroll_timer <= 0.0:
			_commit_scroll_undo()
			scroll_accumulated_delta = 0.0
	
	var hovered := get_viewport().gui_get_hovered_control()

	var inside_dock := hovered != null and is_ancestor_of(hovered)

	if inside_dock and not _hovered:
		_hovered = true
		_on_dock_focus_in()

	elif not inside_dock and _hovered:
		_hovered = false
		_on_dock_focus_out()

##--------------------Handle Transform Field Focus--------------------##

func _on_tfield_focus_entered(node: LineEdit) -> void:
	if skeleton == null:
		return
		
	var idxs = _get_selected_bone_indexes()
	if idxs.is_empty():
		return

	edit_start_transform = skeleton.get_bone_pose(idxs[0])

func _on_tfield_focus_lost(node: LineEdit):
	if not node.text.is_valid_float():
		return
	
	_apply_transform(false)

##--------------------Updates--------------------##

func _update_skeleton():
	var skeleton_selected = false
	
	if skeleton:
		skeleton_selected = true
	
	visible = skeleton_selected


func _update_bone_list():
	if skeleton == null:
		bone_list.clear()
		bone_idxs = []
		return

	if bone_list.item_count != skeleton.get_bone_count():
		bone_list.clear()

		for i in range(skeleton.get_bone_count()):
			bone_list.add_item(skeleton.get_bone_name(i))

		if skeleton.get_bone_count() > 0:
				bone_list.select(0)
				_on_bone_selection_changed(0)

func _update_selection_info():
	var selected = _get_selected_bone_indexes()
	if selection_label:
		if selected.is_empty():
			selection_label.text = "No bones selected"
		elif selected.size() == 1:
			selection_label.text = "1 bone selected"
		else:
			selection_label.text = str(selected.size()) + " bones selected"

##--------------------Bone Selection--------------------##

func _get_selected_bone_indexes() -> Array:
	var selected = bone_list.get_selected_items()
	if selected.size() == 0:
		return []
	return selected

func _on_bone_selection_changed(index: int = -1, selected: bool = false) -> void:
	bone_idxs = _get_selected_bone_indexes()
	_update_current_transform()
	_update_selection_info()

##--------------------Copy/Paste--------------------##

func _on_copy_pressed() -> void:
	if skeleton == null:
		return

	var bn_idxs = _get_selected_bone_indexes()
	if bn_idxs.is_empty():
		return
	
	copied_transforms.clear()
	
	for idx in bn_idxs:
		var bone_name = skeleton.get_bone_name(idx)
		var bone_trans: Transform3D = skeleton.get_bone_pose(idx) # local, not global
		
		copied_transforms.append({
			"bone_name": bone_name,
			"bone_trans": bone_trans
		})

func _on_paste_pressed() -> void:
	if skeleton == null:
		return

	var selected := _get_selected_bone_indexes()
	if selected.is_empty() or copied_transforms.is_empty():
		return
	
	if selected.size() != copied_transforms.size():
		push_warning("Paste failed: Selected %d bones but copied %d bones. Select exactly %d bones to paste." %
			[selected.size(), copied_transforms.size(), copied_transforms.size()])
		return
	
	var undo_redo = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Paste Bone Transforms")

	for i in range(selected.size()):
		var target_idx: int = selected[i]
		var copied_data: Dictionary = copied_transforms[i]
		var new_local: Transform3D = copied_data["bone_trans"]
		var old_local: Transform3D = skeleton.get_bone_pose(target_idx)

		undo_redo.add_do_method(skeleton, "set_bone_pose", target_idx, new_local)
		undo_redo.add_undo_method(skeleton, "set_bone_pose", target_idx, old_local)

	undo_redo.add_do_method(self, "_update_current_transform")
	undo_redo.add_undo_method(self, "_update_current_transform")
	undo_redo.commit_action()

func _on_paste_mirrored_pressed() -> void:
	if skeleton == null:
		return

	if copied_transforms.is_empty() or copied_transforms.size() != bone_list.get_selected_items().size():
		push_warning("Paste requires the same number of copied and selected bones.")
		return

	var undo_redo = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Paste Mirrored Bone Transforms")

	for copied_data in copied_transforms:
		var source_name: String = copied_data["bone_name"]
		var copied_local: Transform3D = copied_data["bone_trans"]

		var target_name: String = _get_mirrored_bone_name(source_name)
		var target_idx: int = skeleton.find_bone(target_name)

		if target_idx == -1:
			print("No mirrored bone found for: ", source_name)
			continue
		
		var old_local: Transform3D = skeleton.get_bone_pose(target_idx)
		var mirrored_local: Transform3D = _mirror_transform(copied_local, mirror_axis)

		undo_redo.add_do_method(skeleton, "set_bone_pose", target_idx, mirrored_local)
		undo_redo.add_undo_method(skeleton, "set_bone_pose", target_idx, old_local)

	undo_redo.add_do_method(self, "_update_current_transform")
	undo_redo.add_undo_method(self, "_update_current_transform")
	undo_redo.commit_action()

func _on_paste_button_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if Input.is_key_pressed(KEY_SHIFT):
			_on_paste_mirrored_pressed()
		else:
			_on_paste_pressed()

##--------------------Bone/Pose Mirroring--------------------##

func _mirror_full_pose() -> void:
	if skeleton == null or not is_instance_valid(skeleton):
		return
	
	var mirrored_globals := {} # target_idx -> mirrored global transform
	var old_transforms := {}    # target_idx -> old local transform
	
	# Pass 1: compute all mirrored globals first
	for i in range(skeleton.get_bone_count()):
		var source_name := skeleton.get_bone_name(i)
		var target_name := _get_mirrored_bone_name(source_name)
		var target_idx := skeleton.find_bone(target_name)
		
		if target_idx == -1:
			continue
		
		var source_global: Transform3D = skeleton.get_bone_global_pose(i)
		mirrored_globals[target_idx] = _mirror_transform(source_global, mirror_axis)
		old_transforms[target_idx] = skeleton.get_bone_pose(target_idx)
	
	# Pass 2: convert mirrored globals to local using mirrored parents when available
	var edits := []
	for target_idx in mirrored_globals.keys():
		var mirrored_global: Transform3D = mirrored_globals[target_idx]
		var parent_idx: int = skeleton.get_bone_parent(target_idx)
		var new_local: Transform3D
		
		if parent_idx == -1:
			new_local = mirrored_global
		else:
			var parent_global: Transform3D
			if mirrored_globals.has(parent_idx):
				parent_global = mirrored_globals[parent_idx]
			else:
				parent_global = skeleton.get_bone_global_pose(parent_idx)
			
			new_local = parent_global.affine_inverse() * mirrored_global
		
		edits.append({
			"target_idx": target_idx,
			"old_transform": old_transforms[target_idx],
			"new_transform": new_local
		})
	
	var undo_redo = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Mirror Full Pose")
	
	for edit in edits:
		undo_redo.add_do_method(skeleton, "set_bone_pose", edit["target_idx"], edit["new_transform"])
		undo_redo.add_undo_method(skeleton, "set_bone_pose", edit["target_idx"], edit["old_transform"])
	
	undo_redo.add_do_method(self, "_update_current_transform")
	undo_redo.add_undo_method(self, "_update_current_transform")
	undo_redo.commit_action()

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

func _on_mirror_axis_btn_pressed() -> void:
	match mirror_axis:
		"x":
			mirror_axis = "y"
			mirror_axis_btn.text = " Y "
			ma_btn_style_nrm.set_bg_color(Color(0.447, 0.725, 0.0, 0.9))
			ma_btn_style_pressed.set_bg_color(Color(0.571, 0.784, 0.37, 0.9))
		"y":
			mirror_axis = "z"
			mirror_axis_btn.text = " Z "
			ma_btn_style_nrm.set_bg_color(Color(0.0, 0.714, 0.824, 0.9))
			ma_btn_style_pressed.set_bg_color(Color(0.543, 0.762, 0.822, 0.9))
		"z":
			mirror_axis = "x"
			mirror_axis_btn.text = " X "
			ma_btn_style_nrm.set_bg_color(Color(1.0, 0.282, 0.361, 0.9))
			ma_btn_style_pressed.set_bg_color(Color(1.0, 0.441, 0.47, 0.9))

##--------------------Handle Transforms--------------------##

func _update_current_transform():
	if skeleton == null:
		return
	
	var selected := _get_selected_bone_indexes()
	
	suppress_field_signals = true
	
	if selected.is_empty():
		for key in transform_fields:
			for node in transform_fields[key]:
				node.text = ""
		suppress_field_signals = false
		return
	
	var bone_idx: int = selected[0]
	var transform: Transform3D = skeleton.get_bone_pose(bone_idx)
	
	current_location = transform.origin
	current_scale = transform.basis.get_scale()
	current_euler = transform.basis.get_euler() * (180.0 / PI)
	
	if is_scrolling and scroll_live_scales.has(bone_idx):
		current_scale = scroll_live_scales[bone_idx]
	else:
		current_scale = transform.basis.get_scale()
	
	var data_map = {
		"location": current_location,
		"rotation": current_euler,
		"scale": current_scale
	}

	for key in transform_fields:
		var vector_value: Vector3 = data_map[key]
		var nodes: Array = transform_fields[key]
		
		nodes[0].text = str(snapped(vector_value.x, 0.001))
		nodes[1].text = str(snapped(vector_value.y, 0.001))
		nodes[2].text = str(snapped(vector_value.z, 0.001))
	
	if selected.size() > 1:
		for key in transform_fields:
			for node in transform_fields[key]:
				node.text = "---"
	
	suppress_field_signals = false

func _on_transform_changed(new_text: String, type: String, axis: String) -> void:
	if suppress_field_signals:
		return
	
	if new_text.is_empty() or new_text == "-" or new_text == "." or new_text == "-.":
		return

	if not new_text.is_valid_float():
		return
	
	var val := float(new_text)
	var selected := _get_selected_bone_indexes()
	if selected.is_empty():
		return
	
	if selected.size() == 1:
		var axis_idx := _axis_to_index(axis)
		
		match type:
			"loc":
				current_location[axis_idx] = val
			"rot":
				current_euler[axis_idx] = val
			"sca":
				current_scale[axis_idx] = max(val, 0.001)
		
		_apply_transform(true)

func _on_transform_submitted(new_text: String, type: String, axis: String) -> void:
	if not new_text.is_valid_float():
		return
	
	var val := float(new_text)
	var selected := _get_selected_bone_indexes()
	if selected.is_empty():
		return
	
	var axis_idx := _axis_to_index(axis)
	var undo_redo = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Set " + type.capitalize() + " " + axis.to_upper())
	
	for bone_idx in selected:
		var current_transform: Transform3D = skeleton.get_bone_pose(bone_idx)
		var location := current_transform.origin
		var scale := current_transform.basis.get_scale()
		var euler := current_transform.basis.get_euler() * (180.0 / PI)
		
		match type:
			"loc":
				location[axis_idx] = val
			"rot":
				euler[axis_idx] = val
			"sca":
				scale[axis_idx] = max(val, 0.001)
		
		var rad_euler := euler * (PI / 180.0)
		var new_basis := Basis.from_euler(rad_euler)
		new_basis = new_basis.scaled(scale)
		var new_transform := Transform3D(new_basis, location)
		
		undo_redo.add_do_method(skeleton, "set_bone_pose", bone_idx, new_transform)
		undo_redo.add_undo_method(skeleton, "set_bone_pose", bone_idx, current_transform)
		
	
	undo_redo.commit_action()

func _check_bone_external_transform_change():
	if skeleton == null:
		return
	
	if is_scrolling:
		return
	
	var selected := _get_selected_bone_indexes()
	if selected.is_empty():
		return
	
	# If any field has focus, skip auto-update
	for key in transform_fields:
		for node in transform_fields[key]:
			if node.has_focus():
				return
	
	# Check if ANY selected bone changed
	var needs_update = false
	
	for bone_idx in selected:
		var transform: Transform3D = skeleton.get_bone_pose(bone_idx)
		var bone_loc := transform.origin
		var bone_scale := transform.basis.get_scale()
		var bone_euler := transform.basis.get_euler() * 180.0 / PI
		
		# Compare with current display values
		if bone_loc != current_location or bone_scale != current_scale or bone_euler != current_euler:
			needs_update = true
			break
	
	if needs_update:
		_update_current_transform()

func _apply_transform(live := true) -> void:
	if skeleton == null:
		return
	
	var selected := _get_selected_bone_indexes()
	if selected.is_empty():
		return
	
	var rad_euler := current_euler * (PI / 180.0)
	var new_basis := Basis.from_euler(rad_euler)
	new_basis = new_basis.scaled(current_scale)
	var new_transform := Transform3D(new_basis, current_location)

	if live:
		# Real-time preview (NO undo)
		for bone_idx in selected:
			skeleton.set_bone_pose(bone_idx, new_transform)
	else:
		# Final commit (WITH undo)
		_commit_transform_with_undo(new_transform)

func _apply_relative_transform_to_bone(bone_idx: int, type: String, axis: String, delta: float) -> void:
	var source_transform: Transform3D = scroll_start_transforms.get(bone_idx, skeleton.get_bone_pose(bone_idx))
	var location = source_transform.origin
	var scale = scroll_start_scales.get(bone_idx, Vector3.ONE)
	var start_basis = scroll_start_bases.get(bone_idx, source_transform.basis.orthonormalized())
	var axis_idx := _axis_to_index(axis)

	match type:
		"loc":
			location[axis_idx] += delta

		"rot":
			var rot_axis: Vector3

			match axis:
				"x":
					rot_axis = start_basis.x.normalized()
				"y":
					rot_axis = start_basis.y.normalized()
				"z":
					rot_axis = start_basis.z.normalized()
				_:
					rot_axis = Vector3.RIGHT

			start_basis = start_basis.rotated(rot_axis, deg_to_rad(delta))

		"sca":
			scale[axis_idx] = max(scale[axis_idx] + delta, 0.001)
			scale = scale.max(Vector3(0.001, 0.001, 0.001))
	
	scroll_live_scales[bone_idx] = scale
	
	var rot = start_basis.get_rotation_quaternion()
	var basis = Basis(rot)
	basis = basis.scaled(scale)
	skeleton.set_bone_pose(bone_idx, Transform3D(basis, location))

func _axis_to_index(axis: String) -> int:
	match axis:
		"x":
			return 0
		"y":
			return 1
		"z":
			return 2
		_:
			return 0

func _commit_transform_with_undo(new_transform: Transform3D) -> void:
	var selected := _get_selected_bone_indexes()
	if selected.is_empty():
		return
	
	var undo_redo = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Transform Bones")

	for bone_idx in selected:
		var old_transform: Transform3D = skeleton.get_bone_pose(bone_idx)

		undo_redo.add_do_method(skeleton, "set_bone_pose", bone_idx, new_transform)
		undo_redo.add_undo_method(skeleton, "set_bone_pose", bone_idx, old_transform)

	undo_redo.add_do_method(self, "_update_current_transform")
	undo_redo.add_undo_method(self, "_update_current_transform")
	undo_redo.commit_action()

##--------------------Gestures--------------------##

func _on_line_edit_gui_input(event: InputEvent, type: String, axis: String, node: LineEdit) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			var step = 0.1 if event.ctrl_pressed else 1.0
			_increment_field(node, type, axis, step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			var step = 0.1 if event.ctrl_pressed else 1.0
			_increment_field(node, type, axis, -step)

##--------------------Shortcuts--------------------##

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I and event.is_command_or_control_pressed():
			var focus_owner := get_viewport().gui_get_focus_owner()
			if focus_owner is LineEdit:
				return
			
			_invert_bone_list_selection()

func _invert_bone_list_selection() -> void:
	for i in range(bone_list.get_item_count()):
		if bone_list.is_selected(i):
			bone_list.deselect(i)
		else:
			bone_list.select(i, false)

##--------------------Scroll Incrementing--------------------##

func _increment_field(node: LineEdit, type: String, axis: String, step: float):
	var selected := _get_selected_bone_indexes()
	if selected.is_empty():
		return
	
	if not is_scrolling:
		is_scrolling = true
		scroll_dirty = false
		scroll_current_values.clear()
		
		scroll_start_transforms.clear()
		scroll_start_bases.clear()
		scroll_start_scales.clear()
		scroll_live_scales.clear()
		
		for bone_idx in selected:
			var start_xform: Transform3D = skeleton.get_bone_pose(bone_idx)
			scroll_start_transforms[bone_idx] = start_xform
			scroll_start_bases[bone_idx] = start_xform.basis.orthonormalized()
			scroll_start_scales[bone_idx] = start_xform.basis.get_scale()
	
	scroll_dirty = true
	
	if type == "rot":
		step *= 10.0
	else:
		step /= 10.0
	
	var key := "%s_%s" % [type, axis]
	scroll_current_values[key] = scroll_current_values.get(key, 0.0) + step
	var delta: float = scroll_current_values[key]
	
	for bone_idx in selected:
		_apply_relative_transform_to_bone(bone_idx, type, axis, delta)
	
	_update_current_transform()
	
	# Scroll debounce timer
	scroll_timer = 0.5

func _commit_scroll_undo() -> void:
	if not scroll_dirty:
		is_scrolling = false
		scroll_start_transforms.clear()
		return
	
	var selected := _get_selected_bone_indexes()
	if selected.is_empty():
		is_scrolling = false
		scroll_dirty = false
		scroll_start_transforms.clear()
		return
	
	var undo_redo = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Scroll Transform Bones")
	
	for bone_idx in selected:
		var new_transform: Transform3D = skeleton.get_bone_pose(bone_idx)
		var old_transform: Transform3D = scroll_start_transforms.get(bone_idx)
		
		if old_transform != null:
			undo_redo.add_do_method(skeleton, "set_bone_pose", bone_idx, new_transform)
			undo_redo.add_undo_method(skeleton, "set_bone_pose", bone_idx, old_transform)
	
	undo_redo.add_do_method(self, "_update_current_transform")
	undo_redo.add_undo_method(self, "_update_current_transform")
	undo_redo.commit_action()
	
	# Reset
	is_scrolling = false
	scroll_dirty = false
	scroll_current_values.clear()
	scroll_start_transforms.clear()
	scroll_start_bases.clear()
	scroll_start_scales.clear()
	scroll_live_scales.clear()

##------------------Effects------------------##

func _on_dock_focus_in() -> void:
	_set_dock_focus(true)

func _on_dock_focus_out() -> void:
	_set_dock_focus(false)

func _set_dock_focus(active: bool) -> void:
	if bone_tween:
		bone_tween.kill()
	
	bone_tween = create_tween()

	if active:
		bone_tween.tween_property(
			self,
			"modulate",
			Color(1, 1, 1, 0.95),
			0.12
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		bone_tween.parallel().tween_property(
			self,
			"scale",
			Vector2(1.01, 1.01),
			0.12
		)
		
	else:
		bone_tween.tween_property(
			self,
			"modulate",
			Color(0.445, 0.534, 0.542, 0.4),
			0.15
		)

		bone_tween.parallel().tween_property(
			self,
			"scale",
			Vector2(1, 1),
			0.15
		)

##--------------------Additional Setup--------------------##

func _on_transform_panel_btn_toggled(pressed: bool) -> void:
	if !bone_list.visible:
		return
	
	transform_panel.visible = pressed

func _on_collapse_btn_pressed(pressed: bool):
	if !pressed:
		collapse_btn.icon = editor_main_screen.get_theme_icon("ArrowDown", "EditorIcons")
		collapse_btn.tooltip_text = "Collapse Bone Dock"
		$VBoxContainer/HBoxContainer2.alignment = BoxContainer.ALIGNMENT_CENTER
	else:
		collapse_btn.icon = editor_main_screen.get_theme_icon("ArrowUp", "EditorIcons")
		collapse_btn.tooltip_text = "Expand Bone Dock"
		$VBoxContainer/HBoxContainer2.alignment = BoxContainer.ALIGNMENT_END
	
	bone_list.visible = !pressed
	$VBoxContainer/HBoxContainer.visible = !pressed
	selection_label.visible = !pressed
	mirror_axis_btn.visible = !pressed
	pose_mirror_btn.visible = !pressed
	trans_p_btn.visible = !pressed
	transform_panel.visible = !pressed

func _setup_buttons():
	copy_btn.icon = editor_main_screen.get_theme_icon("ActionCopy", "EditorIcons")
	paste_btn.icon = editor_main_screen.get_theme_icon("ActionPaste", "EditorIcons")
	trans_p_btn.text = ""
	trans_p_btn.icon = editor_main_screen.get_theme_icon("Panels2", "EditorIcons")
	collapse_btn.text = ""
	collapse_btn.icon = editor_main_screen.get_theme_icon("ArrowUp", "EditorIcons")
	

	copy_btn.text = ""
	paste_btn.text = ""
	
	ma_btn_style_nrm.set_bg_color(Color(1.0, 0.282, 0.361, 0.9))
	ma_btn_style_pressed.set_bg_color(Color(1.0, 0.441, 0.47, 0.9))
	mirror_axis_btn.add_theme_stylebox_override("normal", ma_btn_style_nrm)
	mirror_axis_btn.add_theme_stylebox_override("hover", ma_btn_style_nrm)
	mirror_axis_btn.add_theme_stylebox_override("pressed", ma_btn_style_pressed)
	ma_btn_style_nrm.set_corner_radius_all(5)
	ma_btn_style_pressed.set_corner_radius_all(5)
