extends CanvasLayer
## Dedicated driving-only contact board. Replaces the small fast-travel popup.
## It does not edit the map, calculate payouts or introduce on-foot controls.
signal closed
signal accepted(job_id: String)

const ViewData = preload("res://scripts/ui/contact_contract_view_data.gd")
const Rules = preload("res://scripts/world/driving_contract_rules.gd")
const DESIGN := Vector2(1120.0, 690.0)
const INK := Color("#edf1ed")
const MUTED := Color("#a9bbb8")
const PANEL_BG := Color("#0c171c")
const SECONDARY := Color("#142329")
const BORDER := Color("#486064")
const HIGHLIGHT := Color("#f0b267")

var economy: Object
var contracts: Node2D
var world_id := "morrow-coast"
var active_contact: Dictionary = {}
var offers: Array[Dictionary] = []
var selected_index := -1
var is_open := false
var _owns_pause := false

var backdrop: Control
var frame: Panel
var name_label: Label
var role_label: Label
var greeting_label: Label
var bio_label: Label
var avatar: Label
var portrait_panel: Panel
var reputation_label: Label
var stats_label: Label
var job_list: VBoxContainer
var job_buttons: Array[Button] = []
var job_title: Label
var job_subtitle: Label
var description_label: RichTextLabel
var payout_label: Label
var xp_label: Label
var timing_label: Label
var requirements_label: Label
var status_label: Label
var feedback_label: Label
var accept_button: Button
var selected_accent := HIGHLIGHT

func _panel_style(bg: Color, edge: Color, thick: int = 1, rounding: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = edge
	style.set_border_width_all(thick)
	style.set_corner_radius_all(rounding)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _text(parent: Node, value: String, font_size: int, color: Color,
		at: Vector2, dimensions: Vector2, wrap_text: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if wrap_text:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	else:
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)
	return label

func _line(parent: Node, at: Vector2, length: float, tint: Color) -> void:
	var bar := ColorRect.new()
	bar.position = at
	bar.size = Vector2(length, 1.0)
	bar.color = tint
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)

func _button(parent: Node, label: String, at: Vector2, dimensions: Vector2,
		action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.position = at
	button.size = dimensions
	button.pressed.connect(action)
	button.add_theme_font_size_override("font_size", 15)
	_style_button(button, false)
	parent.add_child(button)
	return button

func _style_button(button: Button, selected: bool) -> void:
	var edge := selected_accent if selected else BORDER
	var normal := _panel_style(Color("#273b3c") if selected else SECONDARY, edge,
		2 if selected else 1, 9)
	var hover := _panel_style(Color("#284046"), selected_accent, 2, 9)
	var pressed := _panel_style(Color("#395250"), selected_accent, 2, 9)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("disabled", _panel_style(Color("#172125"), Color("#415156"), 1, 9))
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL

func _ready() -> void:
	name = "ContractContactScreen"
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	backdrop = Control.new()
	backdrop.name = "ContractBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.01, 0.02, 0.025, 0.78)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.add_child(dimmer)
	frame = Panel.new()
	frame.name = "ContactFrame"
	frame.size = DESIGN
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.add_theme_stylebox_override("panel", _panel_style(PANEL_BG, BORDER, 2, 16))
	backdrop.add_child(frame)
	_build_frame()
	backdrop.visible = false
	get_node("/root/MenuNavigation").register_scope(backdrop,19,close_screen)
	get_viewport().size_changed.connect(_resize)
	_resize()

func _build_frame() -> void:
	_text(frame, "UNDERGROUND NETWORK   /   CONTRACT CONTACT", 13,
		HIGHLIGHT, Vector2(28, 18), Vector2(760, 23))
	_button(frame, "CLOSE  [ ESC ]", Vector2(922, 15), Vector2(170, 38), close_screen)
	_line(frame, Vector2(26, 58), 1068, Color("#40555b"))
	portrait_panel = Panel.new()
	portrait_panel.position = Vector2(28, 78)
	portrait_panel.size = Vector2(112, 116)
	frame.add_child(portrait_panel)
	avatar = _text(portrait_panel, "?", 50, INK,
		Vector2(16, 14), Vector2(80, 78))
	avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label = _text(frame, "", 29, INK, Vector2(160, 76), Vector2(570, 43))
	role_label = _text(frame, "", 14, HIGHLIGHT, Vector2(162, 120), Vector2(565, 24))
	greeting_label = _text(frame, "", 15, INK,
		Vector2(162, 150), Vector2(610, 47), true)
	reputation_label = _text(frame, "", 16, HIGHLIGHT,
		Vector2(798, 84), Vector2(290, 35))
	stats_label = _text(frame, "", 12, MUTED,
		Vector2(800, 132), Vector2(280, 50), true)
	bio_label = _text(frame, "", 13, MUTED,
		Vector2(28, 202), Vector2(1050, 35), true)
	_line(frame, Vector2(26, 248), 1068, Color("#40555b"))
	_text(frame, "AVAILABLE CONTRACTS", 16, INK, Vector2(30, 263), Vector2(370, 29))
	_text(frame, "JOB BRIEFING", 16, INK, Vector2(432, 263), Vector2(500, 29))
	var scroll := ScrollContainer.new()
	scroll.name = "ContractScroll"
	scroll.position = Vector2(27, 300)
	scroll.size = Vector2(375, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	job_list = VBoxContainer.new()
	job_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	job_list.custom_minimum_size.x = 356
	job_list.add_theme_constant_override("separation", 8)
	scroll.add_child(job_list)
	var details := Panel.new()
	details.position = Vector2(420, 298)
	details.size = Vector2(671, 333)
	details.add_theme_stylebox_override("panel", _panel_style(SECONDARY, BORDER, 1, 12))
	frame.add_child(details)
	job_title = _text(details, "", 23, INK, Vector2(20, 14), Vector2(627, 35))
	job_subtitle = _text(details, "", 13, HIGHLIGHT,
		Vector2(20, 54), Vector2(627, 25))
	_line(details, Vector2(20, 91), 632, Color("#40555b"))
	description_label = RichTextLabel.new()
	description_label.name = "JobDescription"
	description_label.position = Vector2(20, 102)
	description_label.size = Vector2(625, 71)
	description_label.bbcode_enabled = false
	description_label.scroll_active = true
	description_label.add_theme_font_size_override("normal_font_size", 15)
	description_label.add_theme_color_override("default_color", INK)
	details.add_child(description_label)
	payout_label = _text(details, "", 18, HIGHLIGHT,
		Vector2(20, 177), Vector2(313, 32))
	xp_label = _text(details, "", 13, MUTED,
		Vector2(336, 177), Vector2(312, 45), true)
	timing_label = _text(details, "", 13, INK,
		Vector2(20, 215), Vector2(625, 26))
	requirements_label = _text(details, "", 13, MUTED,
		Vector2(20, 246), Vector2(625, 25))
	status_label = _text(details, "", 13, HIGHLIGHT,
		Vector2(20, 283), Vector2(625, 28))
	feedback_label = _text(frame, "", 13, Color("#ffba93"),
		Vector2(424, 636), Vector2(666, 30), true)
	accept_button = _button(frame, "ACCEPT CONTRACT", Vector2(28, 640),
		Vector2(374, 40), _accept_selected)

func _resize() -> void:
	if not is_instance_valid(frame):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var zoom := minf((viewport_size.x - 14.0) / DESIGN.x,
		(viewport_size.y - 14.0) / DESIGN.y)
	zoom = clampf(zoom, 0.30, 1.10)
	frame.scale = Vector2.ONE * zoom
	frame.position = (viewport_size - DESIGN * zoom) * 0.5

func _completion_count(offer: Dictionary) -> int:
	if not is_instance_valid(economy):
		return 0
	var history: Variant = economy.get("completed_driving_contracts")
	if not history is Dictionary:
		return 0
	return ViewData.completions(history, world_id, active_contact, offer)

func _lock_reason(offer: Dictionary) -> String:
	if not is_instance_valid(contracts):
		return "CONTRACTS UNAVAILABLE"
	return str(contracts.call("offer_lock_reason", active_contact, offer))

func _offer_state(offer: Dictionary) -> String:
	return ViewData.offer_state(_completion_count(offer),
		bool(offer.get("repeatable", true)), _lock_reason(offer))

func open_contact(contact: Dictionary) -> bool:
	if is_open or get_tree().paused or not is_instance_valid(economy) or 			not is_instance_valid(contracts):
		return false
	if str(contact.get("type", "")) != "contract_contact":
		return false
	active_contact = contact.duplicate(true)
	offers.clear()
	for item in active_contact.get("properties", {}).get("offers", []):
		if item is Dictionary:
			offers.append(item)
	selected_index = 0 if not offers.is_empty() else -1
	var persona: Dictionary = ViewData.identity(active_contact)
	selected_accent = persona["accent"]
	name_label.text = str(persona["name"]).to_upper()
	role_label.text = str(persona["role"]).to_upper()
	greeting_label.text = "\"" + str(persona["greeting"]) + "\""
	bio_label.text = str(persona["bio"])
	bio_label.tooltip_text = bio_label.text
	avatar.text = str(persona["name"]).substr(0, 1).to_upper()
	avatar.add_theme_color_override("font_color", selected_accent)
	portrait_panel.add_theme_stylebox_override("panel",
		_panel_style(Color("#192b30"), selected_accent, 2, 12))
	reputation_label.text = "UNDERGROUND REP  %d" % int(economy.get("underground_reputation"))
	stats_label.text = "%d JOBS AVAILABLE  /  VEHICLE-ONLY CONTACT" % offers.size()
	feedback_label.text = ""
	_rebuild_jobs()
	_select_job(selected_index)
	backdrop.visible = true
	is_open = true
	_owns_pause = true
	get_tree().paused = true
	_resize()
	return true

func _rebuild_jobs() -> void:
	for child in job_list.get_children():
		job_list.remove_child(child)
		child.queue_free()
	job_buttons.clear()
	if offers.is_empty():
		var empty := Label.new()
		empty.text = "NO JOBS YET\nThis contact has no configured contracts."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", MUTED)
		job_list.add_child(empty)
		return
	for i in offers.size():
		var offer: Dictionary = offers[i]
		var status := _offer_state(offer)
		var line := "%s\n%s  /  %s  /  %s" % [
			str(offer.get("title", "Untitled")).to_upper(),
			str(offer.get("kind", "courier")).to_upper(),
			str(offer.get("difficulty", "rookie")).to_upper(), status]
		var button := Button.new()
		button.text = line
		button.custom_minimum_size = Vector2(344, 72)
		button.add_theme_font_size_override("font_size", 14)
		button.clip_text = true
		button.pressed.connect(_select_job.bind(i))
		_style_button(button, i == selected_index)
		job_list.add_child(button)
		job_buttons.append(button)

func _select_job(index: int) -> void:
	selected_index = index
	for i in job_buttons.size():
		_style_button(job_buttons[i], i == selected_index)
	if index < 0 or index >= offers.size():
		job_title.text = "NO AVAILABLE JOBS"
		job_subtitle.text = "CONTACT NOT CONFIGURED"
		description_label.text = "This contact has no contracts to review."
		payout_label.text = ""
		xp_label.text = ""
		timing_label.text = ""
		requirements_label.text = ""
		status_label.text = ""
		accept_button.disabled = true
		return
	var offer: Dictionary = offers[index]
	var kind := str(offer.get("kind", "courier"))
	var rewards: Dictionary = Rules.configured_reward(kind, offer)
	var wanted: int = Rules.configured_wanted(kind, offer)
	var time_seconds: float = Rules.configured_time(kind, offer)
	var lock := _lock_reason(offer)
	var count := _completion_count(offer)
	var repeatable := bool(offer.get("repeatable", true))
	job_title.text = str(offer.get("title", "Driving Contract")).to_upper()
	job_subtitle.text = "%s   /   %s DIFFICULTY" % [
		kind.to_upper(), str(offer.get("difficulty", "rookie")).to_upper()]
	description_label.text = ViewData.description(offer)
	payout_label.text = "%s CASH" % economy.call("dollars", int(rewards.get("cash", 0)))
	xp_label.text = "+%d DRIVER XP   /   +%d CAR XP\n+%d UNDERGROUND REP" % [
		int(rewards.get("player_xp", 0)),
		int(rewards.get("car_xp", 0)),
		int(rewards.get("underground_rep", 0))]
	timing_label.text = "TIME LIMIT: %dm %02ds   /   POLICE HEAT: %d / 5" % [
		int(time_seconds) / 60, int(time_seconds) % 60, wanted]
	requirements_label.text = "REQUIRES LEVEL %d   /   REP %d   /   %s" % [
		int(offer.get("required_player_level", 1)),
		int(offer.get("required_underground_rep", 0)),
		"REPEATABLE" if repeatable else "ONE-TIME"]
	status_label.text = "STATUS: " + ViewData.offer_state(count, repeatable, lock)
	if not lock.is_empty() and not (count>0 and not repeatable):
		status_label.text += " / "+lock
	accept_button.disabled = not ViewData.can_accept(count, repeatable, lock)
	accept_button.text = "ACCEPT CONTRACT" if not accept_button.disabled else 		("COMPLETED" if count > 0 and not repeatable else "CONTRACT LOCKED")
	feedback_label.text = ""

func _accept_selected() -> void:
	if not is_open or selected_index < 0 or selected_index >= offers.size():
		return
	var offer: Dictionary = offers[selected_index]
	if not ViewData.can_accept(_completion_count(offer),
			bool(offer.get("repeatable", true)), _lock_reason(offer)):
		_select_job(selected_index)
		return
	var response: Dictionary = contracts.call("try_start_offer", active_contact, offer)
	if str(response.get("result", "")) == "started":
		accepted.emit(str(offer.get("id", "")))
		close_screen()
	else:
		feedback_label.text = str(response.get("message", "Unable to start contract."))
		_rebuild_jobs()
		_select_job(selected_index)
		feedback_label.text = str(response.get("message", "Unable to start contract."))

func close_screen() -> void:
	if not is_open:
		return
	backdrop.visible = false
	is_open = false
	get_viewport().gui_release_focus()
	if _owns_pause:
		get_tree().paused = false
	_owns_pause = false
	active_contact.clear()
	offers.clear()
	job_buttons.clear()
	closed.emit()

func _exit_tree() -> void:
	# Leaving the world or removing the overlay must never strand the game
	# in a paused state. Only release pauses that this screen acquired.
	if _owns_pause and get_tree() != null and get_tree().paused:
		get_tree().paused = false
	_owns_pause = false
	is_open = false

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	var close_key: bool = event.is_action_pressed("pause") or (
		event is InputEventKey and event.pressed and not event.echo and
		(event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE))
	if close_key:
		close_screen()
		get_viewport().set_input_as_handled()
