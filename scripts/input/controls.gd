extends Node
## Central input bindings for driving and world menus. Both keyboard/mouse and
## controller are independently remappable and persisted to controls.cfg.
## Old files saved by the original controls script remain compatible.
const SAVE_PATH := "user://controls.cfg"
const ACTIONS := [
	"throttle", "brake", "left", "right", "handbrake", "nitrous",
	"shift_up", "shift_down", "transmission", "reset", "camera",
	"map", "garage", "upgrades", "tuning", "mute", "pause"
]
const LABELS := {
	"throttle":"Accelerate", "brake":"Brake / Reverse",
	"left":"Steer left", "right":"Steer right",
	"handbrake":"Handbrake", "nitrous":"Nitrous",
	"shift_up":"Shift up", "shift_down":"Shift down",
	"transmission":"Auto / Manual", "reset":"Reset car",
	"camera":"Camera view", "map":"Open map",
	"garage":"Garage", "upgrades":"Upgrades",
	"tuning":"Tuning / Stats", "mute":"Mute audio",
	"pause":"Pause / Menu"
}
const KEYS := {
	"throttle":KEY_W, "brake":KEY_S, "left":KEY_A, "right":KEY_D,
	"handbrake":KEY_SPACE, "nitrous":KEY_N,
	"shift_up":KEY_E, "shift_down":KEY_Q,
	"transmission":KEY_M, "reset":KEY_R, "camera":KEY_C,
	"map":KEY_TAB, "garage":KEY_G, "upgrades":KEY_U,
	"tuning":KEY_F1, "mute":KEY_V, "pause":KEY_ESCAPE
}
const BUTTONS := {
	"handbrake":JOY_BUTTON_A, "nitrous":JOY_BUTTON_B,
	"transmission":JOY_BUTTON_X, "reset":JOY_BUTTON_Y,
	"camera":JOY_BUTTON_RIGHT_SHOULDER,
	"upgrades":JOY_BUTTON_LEFT_SHOULDER,
	"tuning":JOY_BUTTON_LEFT_STICK,
	"shift_up":JOY_BUTTON_DPAD_UP, "shift_down":JOY_BUTTON_DPAD_DOWN,
	"garage":JOY_BUTTON_DPAD_RIGHT, "mute":JOY_BUTTON_DPAD_LEFT,
	"map":JOY_BUTTON_BACK, "pause":JOY_BUTTON_START
}
const AXES := {
	"throttle":[JOY_AXIS_TRIGGER_RIGHT,1.0],
	"brake":[JOY_AXIS_TRIGGER_LEFT,1.0],
	"left":[JOY_AXIS_LEFT_X,-1.0],
	"right":[JOY_AXIS_LEFT_X,1.0]
}

func _ready() -> void:
	restore_defaults(false)
	var saved := ConfigFile.new()
	if saved.load(SAVE_PATH) != OK:
		return
	# Legacy files store full arrays for each known action. New actions keep
	# their defaults; saved bindings on existing actions remain unchanged.
	for action in ACTIONS:
		if not saved.has_section_key("bindings",action):
			continue
		var events: Variant = saved.get_value("bindings",action)
		if not events is Array:
			continue
		InputMap.action_erase_events(action)
		for item in events:
			if item is InputEvent and device_kind(item) != "":
				var event: InputEvent = item.duplicate()
				if device_kind(event) == "controller":
					event.device = -1
				InputMap.action_add_event(action,event)


func device_kind(event: InputEvent) -> String:
	if event is InputEventKey or event is InputEventMouseButton:
		return "keyboard"
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return "controller"
	return ""


func _key_event(key: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	return event


func _button_event(button: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	return event


func _axis_event(axis_id: int, direction: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = -1
	event.axis = axis_id
	event.axis_value = signf(direction)
	return event


func restore_defaults(save: bool = true) -> bool:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action,0.15)
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action,_key_event(int(KEYS[action])))
		if BUTTONS.has(action):
			InputMap.action_add_event(action,_button_event(int(BUTTONS[action])))
		elif AXES.has(action):
			var axis_binding: Array = AXES[action]
			InputMap.action_add_event(action,
				_axis_event(int(axis_binding[0]),float(axis_binding[1])))
	return _save_bindings() if save else true


func binding(action: String, kind: String) -> InputEvent:
	if not ACTIONS.has(action):
		return null
	for event in InputMap.action_get_events(action):
		if device_kind(event) == kind:
			return event
	return null


func binding_text(action: String, kind: String) -> String:
	var event := binding(action,kind)
	if event == null:
		return "Unbound"
	if event is InputEventKey:
		var key: InputEventKey = event
		var key_string := OS.get_keycode_string(
			key.physical_keycode if key.physical_keycode != 0 else key.keycode)
		var modifiers := ""
		if key.ctrl_pressed: modifiers += "Ctrl+"
		if key.alt_pressed: modifiers += "Alt+"
		if key.shift_pressed: modifiers += "Shift+"
		if key.meta_pressed: modifiers += "Meta+"
		return modifiers+key_string
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event
		match mouse.button_index:
			MOUSE_BUTTON_LEFT: return "Mouse Left"
			MOUSE_BUTTON_RIGHT: return "Mouse Right"
			MOUSE_BUTTON_MIDDLE: return "Mouse Middle"
			MOUSE_BUTTON_XBUTTON1: return "Mouse Back"
			MOUSE_BUTTON_XBUTTON2: return "Mouse Forward"
		return "Mouse %d" % mouse.button_index
	if event is InputEventJoypadButton:
		var pad: InputEventJoypadButton = event
		match pad.button_index:
			JOY_BUTTON_A: return "A / Cross"
			JOY_BUTTON_B: return "B / Circle"
			JOY_BUTTON_X: return "X / Square"
			JOY_BUTTON_Y: return "Y / Triangle"
			JOY_BUTTON_LEFT_SHOULDER: return "LB / L1"
			JOY_BUTTON_RIGHT_SHOULDER: return "RB / R1"
			JOY_BUTTON_LEFT_STICK: return "Left Stick Press"
			JOY_BUTTON_RIGHT_STICK: return "Right Stick Press"
			JOY_BUTTON_DPAD_UP: return "D-Pad Up"
			JOY_BUTTON_DPAD_DOWN: return "D-Pad Down"
			JOY_BUTTON_DPAD_LEFT: return "D-Pad Left"
			JOY_BUTTON_DPAD_RIGHT: return "D-Pad Right"
			JOY_BUTTON_BACK: return "View / Select"
			JOY_BUTTON_START: return "Menu / Start"
		return "Controller Button %d" % pad.button_index
	if event is InputEventJoypadMotion:
		var axis_event: InputEventJoypadMotion = event
		var suffix := "+" if axis_event.axis_value > 0 else "-"
		match axis_event.axis:
			JOY_AXIS_LEFT_X: return "Left Stick Right" if suffix=="+" else "Left Stick Left"
			JOY_AXIS_LEFT_Y: return "Left Stick Down" if suffix=="+" else "Left Stick Up"
			JOY_AXIS_RIGHT_X: return "Right Stick Right" if suffix=="+" else "Right Stick Left"
			JOY_AXIS_RIGHT_Y: return "Right Stick Down" if suffix=="+" else "Right Stick Up"
			JOY_AXIS_TRIGGER_LEFT: return "LT / L2" if suffix=="+" else "LT / L2 (-)"
			JOY_AXIS_TRIGGER_RIGHT: return "RT / R2" if suffix=="+" else "RT / R2 (-)"
		return "Controller Axis %d %s" % [axis_event.axis,suffix]
	return "Unbound"


func _signature(event: InputEvent) -> String:
	if event is InputEventKey:
		var key: InputEventKey = event
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		return "key:%d:%d:%d:%d:%d" % [
			code,int(key.ctrl_pressed),int(key.shift_pressed),
			int(key.alt_pressed),int(key.meta_pressed)]
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	if event is InputEventJoypadButton:
		return "pad:%d" % (event as InputEventJoypadButton).button_index
	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		return "axis:%d:%d" % [motion.axis,1 if motion.axis_value > 0 else -1]
	return ""


func _replace_kind(action: String, kind: String, event: InputEvent) -> void:
	for prior in InputMap.action_get_events(action):
		if device_kind(prior) == kind:
			InputMap.action_erase_event(action,prior)
	if event != null:
		var fresh: InputEvent = event.duplicate()
		if kind == "controller":
			fresh.device = -1
		InputMap.action_add_event(action,fresh)


func rebind(action: String, kind: String, event: InputEvent) -> Dictionary:
	if not ACTIONS.has(action) or kind not in ["keyboard","controller"] or \
			event == null or device_kind(event) != kind:
		return {"status":"invalid"}
	if event is InputEventKey:
		var key: InputEventKey = event
		if key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE or \
				(key.keycode == 0 and key.physical_keycode == 0):
			return {"status":"reserved"}
	if event is InputEventMouseButton and \
			(event as InputEventMouseButton).button_index >= MOUSE_BUTTON_WHEEL_UP:
		return {"status":"reserved"}
	if event is InputEventJoypadMotion and \
			absf((event as InputEventJoypadMotion).axis_value) < 0.5:
		return {"status":"invalid"}
	var prior: InputEvent = binding(action,kind)
	var conflicting := ""
	for other in ACTIONS:
		if other == action:
			continue
		var bound: InputEvent = binding(other,kind)
		if bound != null and _signature(bound) == _signature(event):
			conflicting = other
			break
	# Never silently steal a button: exchanging existing bindings keeps both
	# actions usable, with a single atomic controls.cfg save.
	if conflicting != "":
		_replace_kind(conflicting,kind,prior)
	_replace_kind(action,kind,event)
	var saved := _save_bindings()
	if not saved:
		_replace_kind(action,kind,prior)
		if conflicting != "":
			_replace_kind(conflicting,kind,event)
		return {"status":"save_failed"}
	return {"status":"bound","swapped_action":conflicting}


func clear_binding(action: String, kind: String) -> bool:
	if not ACTIONS.has(action) or kind not in ["keyboard","controller"]:
		return false
	if action == "pause" and binding("pause","controller" if kind=="keyboard" else "keyboard") == null:
		return false
	var old: InputEvent = binding(action,kind)
	_replace_kind(action,kind,null)
	if _save_bindings():
		return true
	_replace_kind(action,kind,old)
	return false


func _save_bindings() -> bool:
	var file := ConfigFile.new()
	for action in ACTIONS:
		file.set_value("bindings",action,InputMap.action_get_events(action))
	return file.save(SAVE_PATH) == OK


# Compatibility with original Controls public helpers.
func axis(action: String, index: int, direction: float) -> void:
	if ACTIONS.has(action):
		rebind(action,"controller",_axis_event(index,direction))


func bind_key(action: String, key: int, save: bool = true) -> void:
	if not ACTIONS.has(action):
		return
	if save:
		rebind(action,"keyboard",_key_event(key))
	else:
		_replace_kind(action,"keyboard",_key_event(key))


func bind_event(action: String, event: InputEvent, save: bool = true) -> void:
	if not ACTIONS.has(action):
		return
	var kind := device_kind(event)
	if kind == "":
		return
	if save:
		rebind(action,kind,event)
	else:
		_replace_kind(action,kind,event)
