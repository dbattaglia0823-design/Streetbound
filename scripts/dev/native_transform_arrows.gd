extends RefCounted
## Native map-editor asset transform arrows. Keep precise typed entry while
## giving the spinner arrows useful coarse/fine mouse increments.
const LEFT_STEP := 1.0
const RIGHT_STEP := 0.1
const PRECISION := 0.001
const ARROW_WIDTH := 24.0

static func nudge(spin: SpinBox,button: MouseButton,up: bool) -> void:
	if not spin.editable or button not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		return
	var amount: float=LEFT_STEP if button==MOUSE_BUTTON_LEFT else RIGHT_STEP
	if not up:amount=-amount
	# Range.step must remain small to preserve .1 clicks and typed coordinates.
	spin.value=snappedf(spin.value+amount,PRECISION)

static func attach(spin: SpinBox) -> Control:
	spin.step=PRECISION
	# The built-in SpinBox up/down arrows increment by Range.step (.001).
	# Capture just that arrow strip; leave the numeric text field untouched.
	var arrows:=Control.new()
	arrows.name="TransformArrowHitArea"
	spin.add_child(arrows)
	arrows.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	arrows.offset_left=-ARROW_WIDTH
	arrows.offset_right=0.0
	arrows.mouse_filter=Control.MOUSE_FILTER_STOP
	arrows.tooltip_text="Left click arrows: +/-1    Right click arrows: +/-0.1"
	arrows.gui_input.connect(func(event: InputEvent)->void:
		if not event is InputEventMouseButton:return
		var mouse:=event as InputEventMouseButton
		if not mouse.pressed or mouse.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:return
		nudge(spin,mouse.button_index,mouse.position.y<arrows.size.y*.5)
		arrows.accept_event()
	)
	return arrows
