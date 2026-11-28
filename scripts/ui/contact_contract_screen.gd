extends CanvasLayer
## Dedicated driving-only contact board. Replaces the small fast-travel popup.
## It does not edit the map, calculate payouts or introduce on-foot controls.
signal closed
signal accepted(job_id: String)

const ViewData = preload("res://scripts/ui/contact_contract_view_data.gd")
const Rules = preload("res://scripts/world/driving_contract_rules.gd")
const RacingStyle = preload("res://scripts/ui/racing_menu_style.gd")
const DESIGN := Vector2(1120.0, 690.0)
const INK := RacingStyle.TEXT
const MUTED := RacingStyle.MUTED
const PANEL_BG := RacingStyle.INK
const SECONDARY := RacingStyle.PANEL
const BORDER := RacingStyle.EDGE
const HIGHLIGHT := RacingStyle.ACCENT

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
var risk_selector: OptionButton
var selected_risk := "standard"
var crew_toggle: CheckButton
var use_hired_crew := false
var _availability_second := -1

func _capacity_lock(offer: Dictionary) -> String:
	if is_instance_valid(contracts) and contracts.has_method("vehicle_requirement"):
		return str(contracts.call("vehicle_requirement",offer))
	return ""
var selected_accent := HIGHLIGHT

func _panel_style(bg: Color, edge: Color, thick: int = 1, rounding: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = edge
	style.set_border_width_all(thick)
	style.set_corner_radius_all(mini(rounding,6))
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
	RacingStyle.button(button,selected,button.get_theme_font_size("font_size"))
	button.alignment=HORIZONTAL_ALIGNMENT_LEFT

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
	job_title = _text(details, "", 23, INK, Vector2(20, 14), Vector2(350, 35))
	job_subtitle = _text(details, "", 13, HIGHLIGHT,
		Vector2(20, 54), Vector2(360, 25))
	risk_selector = OptionButton.new()
	risk_selector.name = "RobberyRisk"
	risk_selector.position = Vector2(400,50)
	risk_selector.size = Vector2(246,36)
	for risk in Rules.ROBBERY_RISKS:
		risk_selector.add_item("RISK: "+str(risk).to_upper())
	risk_selector.select(1)
	risk_selector.visible = false
	RacingStyle.button(risk_selector,false,14)
	risk_selector.item_selected.connect(_risk_changed)
	details.add_child(risk_selector)
	crew_toggle = CheckButton.new()
	crew_toggle.name = "UseHiredCrew"
	crew_toggle.text = "USE ASSIGNED CREW"
	crew_toggle.position = Vector2(375,4)
	crew_toggle.size = Vector2(270,40)
	crew_toggle.add_theme_font_size_override("font_size",12)
	crew_toggle.visible = false
	crew_toggle.toggled.connect(_crew_changed)
	details.add_child(crew_toggle)
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
	selected_risk = "standard"
	_availability_second = -1
	use_hired_crew = false
	crew_toggle.set_pressed_no_signal(false)
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
	var rep_value := int(economy.get("underground_reputation"))
	reputation_label.text = "%s / %d REP" % [Rules.rank_name(rep_value).to_upper(),rep_value]
	var career := Rules.career_state(rep_value)
	stats_label.text = "%d JOBS / %s" % [offers.size(),"MAX RANK" if bool(career.max_rank) else "%d REP TO %s" % [int(career.remaining),str(career.next_rank).to_upper()]]
	feedback_label.text = ""
	_rebuild_jobs()
	_select_job(selected_index)
	backdrop.visible = true
	is_open = true
	_owns_pause = true
	get_tree().paused = true
	_resize()
	return true

func _job_row_text(offer: Dictionary) -> String:
	return "%s\n%s  /  %s  /  %s" % [str(offer.get("title","Untitled")).to_upper(),
		str(offer.get("kind","courier")).to_upper(),str(offer.get("difficulty","rookie")).to_upper(),_offer_state(offer)]

func _process(_dt: float) -> void:
	if not is_open or not is_instance_valid(contracts) or not contracts.has_method("robbery_availability"):
		return
	var now := int(Time.get_unix_time_from_system())
	if now==_availability_second:
		return
	_availability_second = now
	for i in mini(offers.size(),job_buttons.size()):
		if not Rules.robbery_profile(offers[i]).is_empty():
			job_buttons[i].text = _job_row_text(offers[i])
	if selected_index>=0 and selected_index<offers.size() and not Rules.robbery_profile(offers[selected_index]).is_empty():
		var previous_feedback := feedback_label.text
		_select_job(selected_index)
		feedback_label.text = previous_feedback

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
		var line := _job_row_text(offer)
		var button := Button.new()
		button.text = line
		button.custom_minimum_size = Vector2(344, 72)
		button.add_theme_font_size_override("font_size", 14)
		button.clip_text = true
		button.pressed.connect(_select_job.bind(i))
		_style_button(button, i == selected_index)
		job_list.add_child(button)
		job_buttons.append(button)

func _crew_changed(enabled: bool) -> void:
	use_hired_crew = enabled
	_select_job(selected_index)

func _risk_changed(index: int) -> void:
	if index < 0 or index >= Rules.ROBBERY_RISKS.size():
		return
	selected_risk = Rules.ROBBERY_RISKS[index]
	_select_job(selected_index)

func _select_job(index: int) -> void:
	if index != selected_index:
		selected_risk = "standard"
	selected_index = index
	risk_selector.visible = false
	crew_toggle.visible = false
	risk_selector.select(Rules.ROBBERY_RISKS.find(selected_risk))
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
	var profile := Rules.robbery_profile(offer)
	if not profile.is_empty():
		risk_selector.visible = true
		offer = Rules.with_robbery_risk(offer,selected_risk)
	var kind := str(offer.get("kind", "courier"))
	var rewards: Dictionary = Rules.configured_reward(kind, offer)
	var wanted: int = Rules.configured_wanted(kind, offer)
	var time_seconds: float = Rules.configured_time(kind, offer)
	var crew: Array = []
	var quote: Dictionary = {}
	if not profile.is_empty() and economy.has_method("crew_for_offer"):
		var assigned: Array = economy.call("crew_for_offer",offer)
		crew_toggle.visible = true
		crew_toggle.disabled = assigned.is_empty()
		crew_toggle.tooltip_text = "Assign hired specialists from Pause > Career > Crew. Unfilled slots use the default crew."
		if use_hired_crew and not assigned.is_empty():
			crew = assigned
			quote = economy.call("quote_crew",offer,crew)
			time_seconds *= float(quote.get("time_factor",1.0))
			rewards["cash"] = int(quote.get("cash",rewards.cash))
			rewards["underground_rep"] = int(quote.get("underground_rep",rewards.underground_rep))
	var lock := _lock_reason(offers[index])
	if lock.is_empty():
		lock = _capacity_lock(offer)
	var count := _completion_count(offers[index])
	var repeatable := bool(offer.get("repeatable", true))
	job_title.text = str(offer.get("title", "Driving Contract")).to_upper()
	job_subtitle.text = "%s   /   %s DIFFICULTY" % [
		kind.to_upper(), str(offer.get("difficulty", "rookie")).to_upper()]
	description_label.text = ViewData.description(offer)
	var payload := Rules.robbery_payload(offer)
	if payload != Vector2i.ZERO:
		var added_mass := float(payload.y+payload.x*75)
		if is_instance_valid(contracts) and contracts.has_method("projected_payload_mass"):
			added_mass = float(contracts.call("projected_payload_mass",offer))
		description_label.text += "\nVehicle: %d seats including driver / %d kg cargo / +%.0f kg loaded mass." % [payload.x+1,payload.y,added_mass]
	if not quote.is_empty():
		description_label.text += "\nCrew: %s / %d default / cut %s" % [str(quote.names),payload.x-crew.size(),economy.call("dollars",int(quote.cut))]
	payout_label.text = "%s CASH%s" % [economy.call("dollars", int(rewards.get("cash", 0)))," NET" if not quote.is_empty() else ""]
	xp_label.text = "+%d DRIVER XP   /   +%d CAR XP\n+%d UNDERGROUND REP" % [
		int(rewards.get("player_xp", 0)),
		int(rewards.get("car_xp", 0)),
		int(rewards.get("underground_rep", 0))]
	timing_label.text = "TIME LIMIT: %dm %02ds   /   POLICE HEAT: %d / 5" % [
		int(time_seconds) / 60, int(time_seconds) % 60, wanted]
	if not profile.is_empty():
		timing_label.text += "   /   CREW: %.1fs" % maxf(3.0,Rules.configured_robbery_hold(offer)*float(quote.get("hold_factor",1.0)))
	requirements_label.text = "REQUIRES LEVEL %d   /   REP %d   /   %s" % [
		int(offer.get("required_player_level", 1)),
		Rules.required_rep(offer),
		"REPEATABLE" if repeatable else "ONE-TIME"]
	status_label.text = "STATUS: " + ViewData.offer_state(count, repeatable, lock)
	if not profile.is_empty() and contracts.has_method("robbery_availability"):
		var availability: Dictionary = contracts.call("robbery_availability",offer)
		var rotation_info := "ALWAYS LISTED" if not bool(availability.get("rotating",false)) else ("ROTATES OUT IN " if bool(availability.get("rotation_open",false)) else "ROTATES IN ")+Rules.timer_text(int(availability.get("rotation_seconds",0)))
		description_label.text += "\n"+rotation_info+" / LOCATION COOLDOWN "+Rules.timer_text(Rules.location_cooldown(offer))
		if int(availability.get("cooldown",0))>0:
			description_label.text += " / REMAINING "+Rules.timer_text(int(availability.cooldown))
	if not lock.is_empty() and not (count>0 and not repeatable) and not status_label.text.contains(lock):
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
	if not Rules.robbery_profile(offer).is_empty() and not _capacity_lock(Rules.with_robbery_risk(offer,selected_risk)).is_empty():
		_select_job(selected_index)
		return
	var response: Dictionary
	if Rules.robbery_profile(offer).is_empty():
		response = contracts.call("try_start_offer", active_contact, offer)
	else:
		if use_hired_crew and economy.has_method("crew_for_offer") and not (economy.call("crew_for_offer",offer) as Array).is_empty():
			response = contracts.call("try_start_offer", active_contact, offer, selected_risk, true)
		else:
			response = contracts.call("try_start_offer", active_contact, offer, selected_risk)
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
