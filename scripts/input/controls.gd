extends Node
## All bindings are InputMap actions. Rebinding persists in user://controls.cfg.
const KEYS := {"throttle": KEY_W, "brake": KEY_S, "left": KEY_A, "right": KEY_D, "handbrake": KEY_SPACE, "reset": KEY_R, "camera": KEY_C, "tuning": KEY_F1, "shift_up": KEY_E, "shift_down": KEY_Q, "transmission": KEY_M, "mute": KEY_V, "nitrous": KEY_N}

func _ready() -> void:
	for action in KEYS:
		InputMap.add_action(action, 0.15)
		bind_key(action, KEYS[action], false)
	axis("throttle", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	axis("left", JOY_AXIS_LEFT_X, -1.0)
	axis("right", JOY_AXIS_LEFT_X, 1.0)
	for pair in [["handbrake", JOY_BUTTON_A], ["nitrous", JOY_BUTTON_B], ["reset", JOY_BUTTON_Y], ["camera", JOY_BUTTON_RIGHT_SHOULDER], ["shift_up", JOY_BUTTON_DPAD_UP], ["shift_down", JOY_BUTTON_DPAD_DOWN]]:
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = pair[1]
		InputMap.action_add_event(pair[0], event)
	var saved := ConfigFile.new()
	if saved.load("user://controls.cfg") == OK:
		for action in KEYS:
			if saved.has_section_key("bindings", action):
				InputMap.action_erase_events(action)
				for event in saved.get_value("bindings", action):
					InputMap.action_add_event(action, event)

func axis(action: String, index: int, direction: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = -1
	event.axis = index
	event.axis_value = direction
	InputMap.action_add_event(action, event)

func bind_key(action: String, key: int, save := true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	bind_event(action, event, save)

func bind_event(action: String, event: InputEvent, save := true) -> void:
	for existing in InputMap.action_get_events(action):
		if (event is InputEventKey and existing is InputEventKey) or (not event is InputEventKey and not existing is InputEventKey):
			InputMap.action_erase_event(action, existing)
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		event.device = -1
	InputMap.action_add_event(action, event)
	if save:
		var file := ConfigFile.new()
		for name in KEYS:
			file.set_value("bindings", name, InputMap.action_get_events(name))
		file.save("user://controls.cfg")
