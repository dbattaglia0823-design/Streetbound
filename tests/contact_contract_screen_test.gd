extends SceneTree
## Contact-board behavior: separate screen, save-derived completion,
## distinct personas, full briefings, requirement locks and pause ownership.
const Screen = preload("res://scripts/ui/contact_contract_screen.gd")
const ViewData = preload("res://scripts/ui/contact_contract_view_data.gd")
const Economy = preload("res://scripts/vehicle/vehicle_ownership.gd")
const Rules = preload("res://scripts/world/driving_contract_rules.gd")
var failures: Array[String] = []

class ContractStub extends Node2D:
	var accepted_jobs: Array[String] = []
	var last_response := "started"
	var last_risk := ""
	var last_crew := false
	var availability_lock := ""

	func robbery_availability(_offer: Dictionary) -> Dictionary:
		return {"available":availability_lock.is_empty(),"rotating":true,"rotation_open":true,"rotation_seconds":120,"cooldown":30 if not availability_lock.is_empty() else 0}

	func offer_lock_reason(_contact: Dictionary, offer: Dictionary) -> String:
		if not availability_lock.is_empty() and not Rules.robbery_profile(offer).is_empty():
			return availability_lock
		if str(offer.get("id", "")) == "one_time":
			return "CONTRACT COMPLETED"
		if str(offer.get("id", "")) == "locked":
			return "REQUIRES DRIVER LEVEL 50"
		return ""

	func try_start_offer(_contact: Dictionary, offer: Dictionary, risk: String = "standard", use_crew: bool = false) -> Dictionary:
		last_risk = risk
		last_crew = use_crew
		accepted_jobs.append(str(offer.get("id","")))
		return {"result":last_response,"message":"Road route is unavailable"}

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL",label])
	if not passed:
		failures.append(label)

func offer(id: String, title: String, kind: String,
		repeatable: bool = true, details: String = "") -> Dictionary:
	return {
		"id":id,"title":title,"kind":kind,"difficulty":"pro",
		"description":details,"repeatable":repeatable,
		"cash":2250,"player_xp":260,"car_xp":180,"underground_rep":4,
		"time_limit_seconds":360,"wanted_level":2,
		"required_player_level":8,"required_underground_rep":10
	}

func run() -> void:
	var economy := Economy.new(false)
	var contracts := ContractStub.new()
	root.add_child(contracts)
	var jobs: Array = [
		offer("repeatable","Harbor Delivery","smuggling",true,
			"Collect the shipment and reach the marina unseen."),
		offer("one_time","The Last Pickup","robbery",false),
		offer("locked","High Stakes","getaway",true)
	]
	var contact := {
		"id":"marker-contact-1","name":"Mara Voss",
		"type":"contract_contact",
		"properties":{"contact_style":"business",
			"contact_role":"PRIVATE FIXER",
			"contact_greeting":"I only work with reliable drivers.",
			"contact_bio":"Selective contracts for drivers with a clean escape record.",
			"offers":jobs}
	}
	var one_time_key := ViewData.event_key("morrow-test",contact,jobs[1])
	var repeat_key := ViewData.event_key("morrow-test",contact,jobs[0])
	economy.completed_driving_contracts[one_time_key] = 1
	economy.completed_driving_contracts[repeat_key] = 2
	check("completion_key_matches_contract_save_format",
		one_time_key == "morrow-test::marker-contact-1_one_time")
	check("legacy_saves_default_to_no_completed_jobs",
		ViewData.completions({}, "morrow-test", contact, jobs[1]) == 0)
	check("completed_nonrepeatable_job_stays_completed",
		ViewData.offer_state(1,false,"CONTRACT COMPLETED") == "COMPLETED"
		and not ViewData.can_accept(1,false,"CONTRACT COMPLETED"))
	check("repeatable_job_marks_prior_completions",
		ViewData.offer_state(2,true,"") == "REPEATABLE / 2 COMPLETE"
		and ViewData.can_accept(2,true,""))
	check("locked_jobs_have_clear_lock_state",
		ViewData.offer_state(0,true,"REQUIRES DRIVER LEVEL 50") == "LOCKED"
		and not ViewData.can_accept(0,true,"REQUIRES DRIVER LEVEL 50"))
	check("custom_job_description_preserved",
		ViewData.description(jobs[0]).contains("marina"))
	check("fallback_description_preserved",
		ViewData.description({"kind":"robbery"}).contains("crew"))
	var identity: Dictionary = ViewData.identity(contact)
	check("authored_personality_visible",identity.role=="PRIVATE FIXER" and
		identity.greeting=="I only work with reliable drivers." and
		identity.name=="Mara Voss")
	var alt_persona: Dictionary = ViewData.identity({
		"name":"Another Fixer","properties":{"contact_style":"street","contact_role":""}
	})
	check("different_persona_presets_provide_distinct_identity",
		alt_persona.role != identity.role and
		alt_persona.greeting != identity.greeting)
	var board := CanvasLayer.new()
	board.set_script(Screen)
	board.set("contracts",contracts)
	board.set("economy",economy)
	board.set("world_id","morrow-test")
	root.add_child(board)
	await process_frame
	check("contact_screen_uses_dedicated_fullscreen_overlay",
		is_instance_valid(board.get("backdrop")) and
		(board.get("backdrop") as Control).visible == false)
	check("open_contact_pauses_world",bool(board.call("open_contact",contact))
		and paused and bool(board.get("is_open")))
	check("all_jobs_displayed",(board.get("job_buttons") as Array).size()==3)
	check("name_and_role_are_shown",
		(board.get("name_label") as Label).text=="MARA VOSS"
		and (board.get("role_label") as Label).text=="PRIVATE FIXER")
	check("repeatable_completion_status_and_briefing",
		(board.get("status_label") as Label).text.contains("2 COMPLETE")
		and (board.get("description_label") as RichTextLabel).text.contains("marina"))
	check("earnings_and_xp_are_visible",
		(board.get("payout_label") as Label).text.contains("$2,250")
		and (board.get("xp_label") as Label).text.contains("260 DRIVER XP"))
	board.call("_select_job",1)
	check("one_time_completed_button_disabled",
		(board.get("accept_button") as Button).disabled
		and (board.get("status_label") as Label).text.contains("COMPLETED"))
	board.call("_accept_selected")
	check("completed_job_cannot_be_reaccepted",
		contracts.accepted_jobs.is_empty() and paused)
	board.call("_select_job",2)
	check("locked_job_shows_requirement",
		(board.get("status_label") as Label).text.contains("LOCKED")
		and (board.get("accept_button") as Button).disabled)
	board.call("_accept_selected")
	check("locked_job_cannot_start",contracts.accepted_jobs.is_empty())
	board.call("_select_job",0)
	contracts.last_response="unreachable"
	board.call("_accept_selected")
	check("failed_start_keeps_contact_screen_open",
		paused and bool(board.get("is_open")) and
		(board.get("feedback_label") as Label).text.contains("route"))
	contracts.last_response="started"
	board.call("_accept_selected")
	check("successful_start_closes_without_eating_rewards",
		not paused and not bool(board.get("is_open"))
		and contracts.accepted_jobs == ["repeatable","repeatable"]
		and economy.completed_driving_contracts[one_time_key] == 1)
	var risk_contact: Dictionary = contact.duplicate(true)
	risk_contact.properties.offers = [Rules.make_robbery_offer("jewelry","target","dropoff")]
	check("risk_board_opens",bool(board.call("open_contact",risk_contact)))
	check("risk_selector_visible_for_profile",(board.get("risk_selector") as OptionButton).visible)
	contracts.availability_lock="COOLDOWN 00:30"
	board.call("_select_job",0)
	check("cooldown_disables_accept",(board.get("accept_button") as Button).disabled and (board.get("status_label") as Label).text.contains("COOLDOWN 00:30"))
	board.call("_accept_selected")
	check("cooldown_cannot_accept",bool(board.get("is_open")))
	contracts.availability_lock=""
	board.call("_risk_changed",2)
	check("risk_preview_recalculates_payout_and_heat",(board.get("payout_label") as Label).text.contains("$36,250") and (board.get("timing_label") as Label).text.contains("HEAT: 4"))
	board.call("_accept_selected")
	check("risk_selection_passes_separately_from_authored_offer",contracts.last_risk=="maximum" and not bool(board.get("is_open")))
	check("contact_can_reopen_after_accept",bool(board.call("open_contact",contact)) and paused)
	board.call("close_screen")
	check("close_screen_restores_world_pause",not paused and not bool(board.get("is_open")))
	check("contact_can_open_for_scene_transition",bool(board.call("open_contact",contact)) and paused)
	root.remove_child(board)
	check("removing_contact_overlay_releases_owned_pause",not paused)
	board.queue_free()
	contracts.queue_free()
	print("CONTACT CONTRACT SCREEN: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)
