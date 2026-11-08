extends Control
## Functional UI Layout Contract v2 adapter for Godot 4.
## Attach to an empty Control, call load_from_file(), then connect action_requested.
signal action_requested(action_id: String, payload: Dictionary)

var layout: Dictionary = {}
var bindings: Dictionary = {}
var controls: Dictionary = {}

func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("UI template missing: " + path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("UI template must be a JSON object")
		return false
	return apply_layout(parsed)

func apply_layout(spec: Dictionary) -> bool:
	if int(spec.get("version", -1)) != 2:
		push_error("Unsupported UI template version")
		return false
	var nodes: Variant = spec.get("nodes", [])
	if not nodes is Array or nodes.size() > 120:
		push_error("Invalid UI template nodes")
		return false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	controls.clear()
	layout = spec.duplicate(true)
	var lookup: Dictionary = {}
	for item in nodes:
		if item is Dictionary:
			lookup[str(item.get("id", ""))] = item
	for edge in spec.get("edges", []):
		if not edge is Dictionary:
			continue
		var from_id: String = str(edge.get("from", ""))
		var to_id: String = str(edge.get("to", ""))
		if not lookup.has(from_id) or not lookup.has(to_id):
			continue
		var first: Dictionary = lookup[from_id]
		var last: Dictionary = lookup[to_id]
		var a := Vector2(float(first.get("x", 0)) + float(first.get("w", 0)) / 2.0, float(first.get("y", 0)) + float(first.get("h", 0)) / 2.0)
		var b := Vector2(float(last.get("x", 0)) + float(last.get("w", 0)) / 2.0, float(last.get("y", 0)) + float(last.get("h", 0)) / 2.0)
		var line := Line2D.new()
		line.name = "Connection_" + from_id + "_" + to_id
		line.default_color = Color(0.64, 0.72, 0.80)
		line.width = 3.0
		line.add_point(a)
		line.add_point(b)
		line.z_index = 1
		add_child(line)
	var viewport: Dictionary = spec.get("viewport", {})
	custom_minimum_size = Vector2(float(viewport.get("width", 800)), float(viewport.get("height", 500)))
	for entry in nodes:
		if not entry is Dictionary:
			continue
		var ui: Control = _make_control(entry)
		if ui == null:
			continue
		add_child(ui)
		ui.position = Vector2(float(entry.get("x", 0)), float(entry.get("y", 0)))
		ui.size = Vector2(float(entry.get("w", 200)), float(entry.get("h", 60)))
		ui.set_meta("ui_binding", str(entry.get("bindingKey", "")))
		ui.set_meta("ui_action", str(entry.get("actionId", "")))
		controls[str(entry.get("id", ""))] = ui
	set_data(bindings)
	return true

func _make_control(entry: Dictionary) -> Control:
	var kind: String = str(entry.get("type", ""))
	var label_text: String = str(entry.get("label", ""))
	var action: String = str(entry.get("actionId", ""))
	var node_id: String = str(entry.get("id", ""))
	var ui: Control
	match kind:
		"panel":
			ui = Panel.new()
		"label":
			var label_node := Label.new()
			label_node.text = label_text
			label_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			ui = label_node
		"button", "slot":
			var button := Button.new()
			button.text = label_text
			button.pressed.connect(_dispatch_click.bind(action, node_id))
			ui = button
		"progress":
			var bar := ProgressBar.new()
			bar.max_value = 100
			bar.show_percentage = false
			ui = bar
		"toggle":
			var toggle := CheckBox.new()
			toggle.text = label_text
			toggle.toggled.connect(_dispatch_value.bind(action, node_id))
			ui = toggle
		"slider":
			var slider := HSlider.new()
			slider.min_value = 0
			slider.max_value = 100
			slider.value_changed.connect(_dispatch_value.bind(action, node_id))
			ui = slider
		"input":
			var input := LineEdit.new()
			input.placeholder_text = label_text
			input.text_submitted.connect(_dispatch_value.bind(action, node_id))
			ui = input
		"grid", "list":
			var scroll := ScrollContainer.new()
			var items := GridContainer.new()
			items.name = "Entries"
			items.columns = 4 if kind == "grid" else 1
			scroll.add_child(items)
			ui = scroll
		_:
			return null
	ui.name = node_id.validate_node_name()
	if kind in ["button", "slot"]:
		var shape: String = str(entry.get("shape", "rectangle"))
		if shape in ["circle", "rounded"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.22, 0.31, 0.43)
			var radius: int = 999 if shape == "circle" else 16
			style.set_corner_radius_all(radius)
			(ui as Button).add_theme_stylebox_override("normal", style)
			(ui as Button).add_theme_stylebox_override("hover", style)
			(ui as Button).add_theme_stylebox_override("pressed", style)
	ui.z_index = 2 if kind in ["button", "slot"] else 0
	ui.set_meta("ui_type", kind)
	return ui

func _dispatch_click(action: String, node_id: String) -> void:
	if not action.is_empty():
		action_requested.emit(action, {"nodeId": node_id})

func _dispatch_value(value: Variant, action: String, node_id: String) -> void:
	if not action.is_empty():
		action_requested.emit(action, {"nodeId": node_id, "value": value})

func _dispatch_item(action: String, node_id: String, index: int, item: Variant) -> void:
	if not action.is_empty():
		action_requested.emit(action, {"nodeId": node_id, "index": index, "item": item})

func _lookup(key: String) -> Variant:
	if key.is_empty():
		return null
	if bindings.has(key):
		return bindings[key]
	var current: Variant = bindings
	for part in key.split("."):
		if not current is Dictionary or not current.has(part):
			return null
		current = current[part]
	return current

func _display(value: Variant) -> String:
	if value == null:
		return ""
	if value is Dictionary:
		for key in ["name", "label", "title"]:
			if value.has(key):
				return str(value[key])
		return ""
	return str(value)

func set_data(data: Dictionary) -> void:
	bindings = data
	for entry in layout.get("nodes", []):
		if not entry is Dictionary:
			continue
		var id: String = str(entry.get("id", ""))
		if not controls.has(id):
			continue
		var ui: Control = controls[id]
		var value: Variant = _lookup(str(entry.get("bindingKey", "")))
		var kind: String = str(entry.get("type", ""))
		match kind:
			"label":
				if value != null:
					(ui as Label).text = _display(value)
			"slot":
				if value != null:
					(ui as Button).text = _display(value)
			"progress":
				(ui as ProgressBar).value = clampf(float(value) if value != null else 0.0, 0.0, 100.0)
			"toggle":
				(ui as CheckBox).set_pressed_no_signal(bool(value) if value != null else false)
			"slider":
				(ui as HSlider).set_value_no_signal(clampf(float(value) if value != null else 0.0, 0.0, 100.0))
			"input":
				if not (ui as LineEdit).has_focus():
					(ui as LineEdit).text = _display(value)
			"grid", "list":
				var items_container: GridContainer = ui.get_node("Entries") as GridContainer
				for child in items_container.get_children():
					items_container.remove_child(child)
					child.queue_free()
				if value is Array:
					for index in range(value.size()):
						var item: Variant = value[index]
						var button := Button.new()
						button.text = _display(item)
						button.pressed.connect(_dispatch_item.bind(str(entry.get("actionId", "")), id, index, item))
						items_container.add_child(button)
