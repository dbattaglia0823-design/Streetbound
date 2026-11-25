extends Node
## Central gamepad menu focus. Raw pad inputs are handled only while a
## registered screen is visible. Free-roam bindings and keyboard/mouse
## remain independent of this fixed, always-reachable UI navigation scheme.
const DEADZONE := 0.55
const RELEASE_ZONE := 0.32
const REPEAT_DELAY := 0.34
const REPEAT_INTERVAL := 0.12
var scopes: Array[Dictionary] = []
var using_gamepad := false
var _active_id := 0
var _direction := Vector2.ZERO
var _stick := Vector2.ZERO
var _repeat_clock := 0.0
var _held_device := -1
var _last_focus: Dictionary = {}

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	# Explicit bindings also cover Godot's native OptionButton popups
	# and Window dialogs. They are never included in the driving rebind file.
	for pair in [["ui_accept",JOY_BUTTON_A],["ui_cancel",JOY_BUTTON_B],
		["ui_left",JOY_BUTTON_DPAD_LEFT],["ui_right",JOY_BUTTON_DPAD_RIGHT],
		["ui_up",JOY_BUTTON_DPAD_UP],["ui_down",JOY_BUTTON_DPAD_DOWN]]:
		var action: String=pair[0]
		var button:=InputEventJoypadButton.new()
		button.device=-1;button.button_index=int(pair[1])
		if not InputMap.has_action(action):InputMap.add_action(action)
		if not InputMap.action_has_event(action,button):InputMap.action_add_event(action,button)
	for pair in [["ui_left",JOY_AXIS_LEFT_X,-1.0],["ui_right",JOY_AXIS_LEFT_X,1.0],
		["ui_up",JOY_AXIS_LEFT_Y,-1.0],["ui_down",JOY_AXIS_LEFT_Y,1.0]]:
		var action: String=pair[0]
		var motion:=InputEventJoypadMotion.new()
		motion.device=-1;motion.axis=int(pair[1]);motion.axis_value=float(pair[2])
		if not InputMap.action_has_event(action,motion):InputMap.action_add_event(action,motion)
	# Native popup input needs a deliberate stick displacement as well.
	for action in ["ui_left","ui_right","ui_up","ui_down"]:
		InputMap.action_set_deadzone(action,DEADZONE)

func register_scope(root: Control, priority: int, back: Callable,
		capture: Callable=Callable()) -> void:
	if not is_instance_valid(root):return
	scopes.append({"root":weakref(root),"priority":priority,"back":back,"capture":capture})
	root.tree_exiting.connect(_forget.bind(root.get_instance_id()),CONNECT_ONE_SHOT)

func _forget(id: int) -> void:
	_last_focus.erase(id)
	for i in range(scopes.size()-1,-1,-1):
		var root: Variant=scopes[i].root.get_ref()
		if not is_instance_valid(root) or root.get_instance_id()==id:scopes.remove_at(i)
	if _active_id==id:_active_id=0;_reset_repeat()

func _visible(node: Node) -> bool:
	if not is_instance_valid(node) or not node.is_inside_tree():return false
	var parent: Node=node
	while parent!=null:
		if parent.process_mode==Node.PROCESS_MODE_DISABLED:return false
		if parent is CanvasItem:
			var item:=parent as CanvasItem
			if not item.visible or item.modulate.a<=0.01:return false
		elif parent is CanvasLayer and not (parent as CanvasLayer).visible:return false
		elif parent is Window and not (parent as Window).visible:return false
		parent=parent.get_parent()
	return true

func active_scope() -> Dictionary:
	var best: Dictionary={}
	var priority: int=-100000
	for entry in scopes:
		var root: Control=entry.root.get_ref() as Control
		if _visible(root) and int(entry.priority)>=priority:
			priority=int(entry.priority)
			best=entry
	return best

func blocks_driving() -> bool:
	return not active_scope().is_empty()

func _in_scope(root: Node, control: Control) -> bool:
	return is_instance_valid(control) and (control==root or root.is_ancestor_of(control)) and _visible(control)

func _collect(node: Node, output: Array[Control]) -> void:
	if not _visible(node):return
	if node is Window or node is SubViewport:return
	if node is ScrollContainer:
		(node as ScrollContainer).follow_focus=true
	if node is Control:
		var control:=node as Control
		if control is BaseButton and not (control as BaseButton).disabled and control.focus_mode!=Control.FOCUS_NONE:
			output.append(control)
		elif (control is LineEdit or control is TextEdit or control is ItemList or
				control is Slider or control is TabBar or control is Tree) and control.focus_mode!=Control.FOCUS_NONE:
			output.append(control)
		elif control is SpinBox and (control as SpinBox).editable:
			var field: LineEdit=(control as SpinBox).get_line_edit()
			field.focus_mode=Control.FOCUS_ALL
			output.append(field)
		if control is TabContainer:
			var bar: TabBar=(control as TabContainer).get_tab_bar()
			bar.focus_mode=Control.FOCUS_ALL
			output.append(bar)
	for child in node.get_children():
		_collect(child,output)

func focusables(root: Control) -> Array[Control]:
	var result: Array[Control]=[]
	_collect(root,result)
	return result

func _focus(root: Control, control: Control) -> void:
	if not _in_scope(root,control):return
	control.grab_focus()
	_last_focus[root.get_instance_id()]=weakref(control)
	var parent: Node=control.get_parent()
	while is_instance_valid(parent) and parent!=root:
		if parent is ScrollContainer:
			(parent as ScrollContainer).ensure_control_visible.call_deferred(control)
		parent=parent.get_parent()

func _ensure_focus(root: Control, prefer_button: bool=false) -> Control:
	var items:=focusables(root)
	var focused: Control=root.get_viewport().gui_get_focus_owner()
	if items.has(focused) and not (prefer_button and (focused is LineEdit or focused is TextEdit)):
		return focused
	var previous: Variant=_last_focus.get(root.get_instance_id())
	if previous is WeakRef:
		var old: Control=previous.get_ref() as Control
		if items.has(old):_focus(root,old);return old
	if prefer_button:
		for candidate in items:
			if candidate is BaseButton:
				_focus(root,candidate);return candidate
	if not items.is_empty():
		_focus(root,items[0]);return items[0]
	return null

func _step_focus(root: Control, step: int) -> void:
	var items:=focusables(root)
	if items.is_empty():return
	var focused: Control=root.get_viewport().gui_get_focus_owner()
	var index:=items.find(focused)
	_focus(root,items[posmod(index+step if index>=0 else (0 if step>0 else items.size()-1),items.size())])

func _move(root: Control, direction: Vector2) -> void:
	var current:=_ensure_focus(root)
	if current==null:return
	var spin: SpinBox=current.get_parent() as SpinBox
	if spin!=null and absf(direction.x)>0.5:
		spin.value=clampf(spin.value+spin.step*direction.x,spin.min_value,spin.max_value)
		return
	if current is Slider and absf(direction.x)>0.5:
		var slider:=current as Slider
		slider.value=clampf(slider.value+maxf(slider.step,0.01)*direction.x,slider.min_value,slider.max_value)
		return
	if current is ItemList or current is Tree or (current is TabBar and absf(direction.x)>0.5):
		_queue_key(root,_arrow_key(direction))
		return
	var side: Side=SIDE_LEFT if direction.x<0 else SIDE_RIGHT if direction.x>0 else SIDE_TOP if direction.y<0 else SIDE_BOTTOM
	var items:=focusables(root)
	var neighbor: Control=current.find_valid_focus_neighbor(side)
	if neighbor!=current and items.has(neighbor):
		_focus(root,neighbor);return
	# Restrict geometric fallback to the current screen, even when the
	# underlying HUD or pause page has a nearer focusable button.
	var origin:=current.get_global_rect().get_center()
	var score:=INF
	var best: Control
	for candidate in items:
		if candidate==current:continue
		var delta:=candidate.get_global_rect().get_center()-origin
		var forward:=delta.dot(direction)
		if forward<=1.0:continue
		var cost:=forward+absf(delta.cross(direction))*2.7
		if cost<score:score=cost;best=candidate
	if best!=null:_focus(root,best)

func _arrow_key(direction: Vector2) -> int:
	if direction.x<0:return KEY_LEFT
	if direction.x>0:return KEY_RIGHT
	return KEY_UP if direction.y<0 else KEY_DOWN

func _queue_key(root: Control, code: int) -> void:
	# Send only GUI keyboard equivalents to the viewport, not global
	# Input.parse_input_event; this cannot hold a driving action.
	_send_key.call_deferred(weakref(root),code)

func _send_key(reference: WeakRef, code: int) -> void:
	var root: Control=reference.get_ref() as Control
	var active:=active_scope()
	if root==null or active.is_empty() or active.root.get_ref()!=root:return
	var viewport:=root.get_viewport()
	for pressed in [true,false]:
		if not is_instance_valid(viewport):return
		var key:=InputEventKey.new()
		key.keycode=code;key.pressed=pressed
		viewport.push_input(key,true)

func _popup_open(root: Control) -> bool:
	var focused: Control=root.get_viewport().gui_get_focus_owner()
	if focused is OptionButton and (focused as OptionButton).get_popup().visible:return true
	# A popup owns its own native GUI input (including A/B). Do not
	# navigate behind it or send a second confirmation.
	return false

func _reset_repeat() -> void:
	_direction=Vector2.ZERO;_stick=Vector2.ZERO;_repeat_clock=0.0;_held_device=-1

func _set_direction(root: Control, direction: Vector2, device: int) -> void:
	if direction==_direction and device==_held_device:return
	_direction=direction;_held_device=device
	_repeat_clock=REPEAT_DELAY
	if direction!=Vector2.ZERO:_move(root,direction)

func _stick_direction() -> Vector2:
	var threshold:=RELEASE_ZONE if _direction!=Vector2.ZERO else DEADZONE
	if maxf(absf(_stick.x),absf(_stick.y))<threshold:return Vector2.ZERO
	if absf(_stick.x)>absf(_stick.y):return Vector2(signf(_stick.x),0)
	return Vector2(0,signf(_stick.y))

func _process(dt: float) -> void:
	var entry:=active_scope()
	var root: Control=null if entry.is_empty() else entry.root.get_ref() as Control
	var id:=root.get_instance_id() if root!=null else 0
	if id!=_active_id:
		_active_id=id
		_reset_repeat()
		if using_gamepad and root!=null:_ensure_focus(root,true)
	if root==null or not using_gamepad:return
	var capture: Callable=entry.capture
	if capture.is_valid() and bool(capture.call()):_reset_repeat();return
	if _popup_open(root):_reset_repeat();return
	var focused: Control=root.get_viewport().gui_get_focus_owner()
	if not _in_scope(root,focused):_ensure_focus(root)
	if _direction!=Vector2.ZERO:
		_repeat_clock-=dt
		if _repeat_clock<=0.0:
			_repeat_clock=REPEAT_INTERVAL
			_move(root,_direction)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length()>2.0) or event is InputEventKey:
		# Synthetic GUI key presses must not disable controller navigation.
		if not event is InputEventKey or event.physical_keycode!=0:
			using_gamepad=false;_reset_repeat()
		return
	if not event is InputEventJoypadButton and not event is InputEventJoypadMotion:return
	var entry:=active_scope()
	if entry.is_empty():
		if event is InputEventJoypadButton and event.pressed:using_gamepad=true
		elif event is InputEventJoypadMotion and absf(event.axis_value)>DEADZONE:using_gamepad=true
		return
	var root: Control=entry.root.get_ref() as Control
	var capture: Callable=entry.capture
	if capture.is_valid() and bool(capture.call()):return
	if _popup_open(root):return
	var switched:=not using_gamepad
	using_gamepad=true
	if _active_id!=root.get_instance_id():
		_active_id=root.get_instance_id();_reset_repeat();switched=true
	if switched:_ensure_focus(root,true)
	# Consume pad actions while the menu owns input. E.g. D-pad shifting,
	# garage, nitrous and upgrade shortcuts cannot activate under a modal.
	get_viewport().set_input_as_handled()
	if event is InputEventJoypadMotion:
		var motion:=event as InputEventJoypadMotion
		if motion.axis==JOY_AXIS_LEFT_X:_stick.x=motion.axis_value
		elif motion.axis==JOY_AXIS_LEFT_Y:_stick.y=motion.axis_value
		else:return
		_set_direction(root,_stick_direction(),motion.device)
		return
	var button:=event as InputEventJoypadButton
	var dir:=Vector2.ZERO
	match button.button_index:
		JOY_BUTTON_DPAD_LEFT:dir=Vector2.LEFT
		JOY_BUTTON_DPAD_RIGHT:dir=Vector2.RIGHT
		JOY_BUTTON_DPAD_UP:dir=Vector2.UP
		JOY_BUTTON_DPAD_DOWN:dir=Vector2.DOWN
	if dir!=Vector2.ZERO:
		if button.pressed:_set_direction(root,dir,button.device)
		elif _direction==dir:_set_direction(root,Vector2.ZERO,button.device)
		return
	if not button.pressed:return
	match button.button_index:
		JOY_BUTTON_A:
			if _ensure_focus(root)!=null:_queue_key(root,KEY_ENTER)
		JOY_BUTTON_B,JOY_BUTTON_START:
			_reset_repeat()
			var back: Callable=entry.back
			if back.is_valid():back.call()
		JOY_BUTTON_LEFT_SHOULDER:_step_focus(root,-1)
		JOY_BUTTON_RIGHT_SHOULDER:_step_focus(root,1)
