extends SceneTree
## Regression for the three-column pause hub: actual event data, current car,
## saved driver stats, waypoint selection, dynamic Cars, and retained game flows.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures.append(label)

func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var pause = game.pause_menu
	pause.pause_game()
	await process_frame
	var dash = pause.dashboard
	var hud: Variant = get_first_node_in_group("streetbound_world_map_hud")
	check("pause_hub_replaces_visible_legacy_layout",
		paused and dash.visible and pause.pause_screen.visible and
		is_zero_approx(pause.pause_screen.modulate.a))
	check("navigation_contains_concept_sections",
		["resume","map","events","cars","upgrades","settings","quit","more"].all(
			func(name: String) -> bool: return dash.nav_buttons.has(name)))
	check("events_selected_with_three_column_layout",
		dash.section=="events" and
		dash.get_node("Navigation").position.x < dash.content.position.x and
		dash.content.position.x < dash.get_node("DriverCard").position.x and
		dash.get_node("AreaMapCard").position.y > dash.get_node("CurrentCarCard").position.y)
	check("actual_driver_cash_and_xp",
		dash.driver_level.text.contains(str(game.vehicle_ownership.player_level())) and
		dash.driver_balance.text.contains(dash._money(int(game.vehicle_ownership.balance))) and
		is_equal_approx(float(dash.driver_xp.value),
			float(load("res://scripts/vehicle/race_progression.gd").player_level_progress(
				game.vehicle_ownership.player_xp))))
	check("current_car_uses_live_vehicle_stats",
		dash.car_name.text == str(load("res://scripts/vehicle/player_vehicle_catalog.gd").find_by_id(
			str(game.vehicle_ownership.active_id)).display_name) and
		dash.car_power.text == "%.0f HP" % (game.vehicle.config.engine_power_kw*1.341022) and
		dash.car_level.text.contains("CAR LV"))
	check("pause_map_uses_dedicated_high_resolution_world_render",
		dash.detail_render != null and dash.detail_view != null and
		dash.detail_render.size == Vector2i(960,880) and
		dash.detail_view.get_viewport() == dash.detail_render and
		dash.detail_view.ink.mirror_enabled and
		dash.detail_render.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	check("pause_map_scales_geography_and_icons_consistently",
		is_equal_approx(
			dash.detail_view.pixels_per_m / hud.mini_view.pixels_per_m,
			960.0 / 244.0) and
		is_equal_approx(float(dash.detail_view.get_meta("pause_render_density", 1.0)), 2.0) and
		is_equal_approx(float(dash.detail_view.ink.label_scale), 2.0) and
		is_equal_approx(dash.detail_view.cursor.scale.x, 2.0))
	check("pause_map_race_guidance_matches_normal_atlas",
		dash.detail_view.race_overlay.get("navigation") == hud._active_race_navigation())
	check("map_previews_crop_without_stretching_low_resolution_minimap",
		dash.map_image.texture == dash.detail_render.get_texture() and
		dash.map_image.texture != hud.mini_render.get_texture() and
		dash.map_image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED and
		dash.map_image.clip_contents)
	var driver_card: Control = dash.get_node("DriverCard")
	var car_card: Control = dash.get_node("CurrentCarCard")
	var area_card: Control = dash.get_node("AreaMapCard")
	check("right_hand_cards_have_nonoverlapping_vertical_bounds",
		driver_card.position.y + driver_card.size.y < car_card.position.y and
		car_card.position.y + car_card.size.y < area_card.position.y and
		area_card.position.y + area_card.size.y <= 747)
	var cash_caption: Control = driver_card.get_node("CashCaption")
	print("PAUSE BOUNDS driverXP=",dash.driver_xp.get_rect(),
		" cash=",dash.driver_balance.get_rect(),
		" cashLabel=",cash_caption.get_rect(),
		" district=",dash.driver_district.get_rect(),
		" mapTexture=",dash.map_image.get_rect(),
		" mapStatus=",dash.map_status.get_rect())
	check("driver_cash_xp_and_district_do_not_overlap",
		not dash.driver_xp.get_rect().intersects(dash.driver_balance.get_rect()) and
		not dash.driver_xp.get_rect().intersects(cash_caption.get_rect()) and
		not dash.driver_balance.get_rect().intersects(dash.driver_district.get_rect()) and
		dash.driver_district.position.y + dash.driver_district.size.y <= driver_card.size.y)
	check("cash_and_footer_have_readable_separate_backing",
		dash.get_node("FooterBacking") != null and
		(dash.get_node("FooterBacking") as Panel).size.x > 1300 and
		pause.background.color.a > 0.7)
	check("area_map_label_stays_below_image_and_inside_card",
		dash.map_status.position.y >= dash.map_image.position.y + dash.map_image.size.y and
		dash.map_status.position.y + dash.map_status.size.y < area_card.size.y)
	check("real_events_populate_cards",
		dash.event_rows.size() > 0 and dash.events_list.get_child_count()==dash.event_rows.size())
	var waypoint_race: Node = null
	for race in get_nodes_in_group("streetbound_race"):
		if bool(race.get("available")):
			waypoint_race=race
			break
	check("at_least_one_real_event_is_available",waypoint_race!=null)
	if waypoint_race!=null and dash.event_rows.size()>0:
		var selected_race=dash._available_events()[0]
		dash.event_rows[0].pressed.emit()
		var waypoint = hud.waypoints
		check("event_card_sets_real_driving_waypoint",
			waypoint.active and
			waypoint.destination_m.distance_to(selected_race.start_m)<.01 and
			waypoint.destination_name==str(selected_race.race_title) and
			dash.section=="map" and paused)
	var description: Label = dash.content.get_node("DestinationHelp")
	var preview: TextureRect = dash.content.get_node("InteractiveAreaPreview")
	check("map_page_crops_high_res_preview_without_distortion",
		preview.texture == dash.detail_render.get_texture() and
		preview.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED and
		preview.clip_contents and
		preview.get_rect().end.x < dash.content.size.x and
		preview.get_rect().end.y < dash.content.size.y)
	check("navigation_help_no_longer_overflows_into_car_panel",
		description.clip_text and
		description.get_rect().end.x < dash.content.size.x and
		description.get_rect().end.y < dash.content.size.y and
		description.text.contains("Resume"))
	# Use the real roster and placed dealerships, not a manually curated UI list.
	var catalog: Array[Dictionary] = load(
		"res://scripts/vehicle/player_vehicle_catalog.gd").all()
	dash.show_section("cars")
	check("cars_tab_lists_every_catalog_car",
		dash.section=="cars" and dash.car_rows.size()==catalog.size() and
		dash.content.get_node_or_null("CarScroller")!=null and
		dash.content.get_node_or_null("CarsWorkInProgress")==null and
		dash.car_count_label.text=="%d / %d CARS" % [catalog.size(),catalog.size()])
	var ascending := true
	for i in range(1,dash.car_rows.size()):
		var previous: Dictionary=dash.car_rows[i-1].entry
		var current: Dictionary=dash.car_rows[i].entry
		if dash._car_price_less(current,previous):
			ascending=false
			break
	check("car_catalog_sorted_by_actual_price_low_to_high",ascending)
	dash._filter_cars("this car does not exist")
	check("car_browser_search_filters_without_changing_catalog",
		dash.car_count_label.text=="0 / %d CARS" % catalog.size() and
		(dash.car_rows[0].row as Button).visible==false)
	dash._filter_cars("")
	check("car_browser_search_restores_all_vehicles",
		dash.car_count_label.text=="%d / %d CARS" % [catalog.size(),catalog.size()])
	# A newly added entry must appear without any pause-menu source edits.
	var new_car: Dictionary = catalog[0].duplicate()
	new_car["id"]="test-future-catalog-car"
	new_car["display_name"]="Future Catalog Car"
	new_car["price_usd"]=1
	catalog.append(new_car)
	dash.show_section("cars")
	check("new_catalog_car_appears_in_price_order_automatically",
		dash.car_rows.size()==catalog.size() and
		str(dash.car_rows[0].entry.id)=="test-future-catalog-car")
	new_car["dealership_id"]="missing-dealership"
	dash.show_section("cars")
	check("cars_with_no_valid_dealer_stay_visible_but_cannot_route",
		dash.car_rows.size()==catalog.size() and
		str(dash.car_rows[0].entry.id)=="test-future-catalog-car" and
		(dash.car_rows[0].row as Button).disabled)
	catalog.erase(new_car)
	dash.show_section("cars")
	var selected: Dictionary=dash.car_rows[0].entry
	var dealer: Dictionary=game.dealership_world.get_site(str(selected.dealership_id))
	check("each_car_row_shows_live_price_and_actual_dealer",
		dealer.size()>0 and
		(dash.car_rows[0].row as Button).get_node("CarPrice").text==
			"$"+dash._money(int(selected.price_usd)) and
		(dash.car_rows[0].row as Button).get_node("CarDealer").text==str(dealer.name))
	(dash.car_rows[0].row as Button).pressed.emit()
	var car_destination: Vector2=Vector2(
		float(dealer.parking_m[0]),float(dealer.parking_m[1]))
	check("select_car_sets_road_routed_waypoint_to_its_real_dealership",
		hud.waypoints.active and
		hud.waypoints.destination_m.distance_to(car_destination)<0.01 and
		hud.waypoints.destination_name==str(dealer.name) and
		dash.section=="map" and paused)
	dash.show_section("events")
	dash._set_event_filter("challenges")
	check("unimplemented_challenges_are_not_fabricated",
		dash.event_rows.is_empty() and dash.events_list.get_node_or_null("NoEvents")!=null)
	dash._set_event_filter("all")
	check("changing_tabs_does_not_lose_real_events",dash.event_rows.size()>0)
	dash._navigate("more")
	var more: Control=dash.content.get_node("MoreRow_0")
	(more.get_node("MoreAction") as Button).pressed.emit()
	check("multiplayer_still_accessible",
		pause.menu_state=="multiplayer" and not dash.visible)
	check("multiplayer_suspends_pause_map_render",
		dash.detail_render.render_target_update_mode == SubViewport.UPDATE_DISABLED and
		dash.detail_view.process_mode == Node.PROCESS_MODE_DISABLED)
	pause.back_to_pause()
	dash.nav_buttons["settings"].pressed.emit()
	check("settings_still_accessible",
		pause.menu_state=="settings" and pause.settings_screen.visible)
	check("settings_suspend_pause_map_render",
		dash.detail_render.render_target_update_mode == SubViewport.UPDATE_DISABLED and
		dash.detail_view.process_mode == Node.PROCESS_MODE_DISABLED)
	pause.back_to_pause()
	dash.show_section("upgrades")
	var overlay=game.quick_upgrades
	var open_btn: Button=dash.content.get_node("UpgradeInfo/LaunchUpgrades")
	check("upgrades_use_existing_real_overlay",not open_btn.disabled)
	if not open_btn.disabled:
		open_btn.pressed.emit()
		check("upgrades_open_without_two_pauses",
			paused and not pause.overlay.visible and overlay.overlay.visible)
		overlay.close_menu()
	pause.pause_game()
	dash.nav_buttons["resume"].pressed.emit()
	check("resume_from_navigation_unpauses",
		not paused and not pause.overlay.visible and
		dash.detail_render.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	game.queue_free()
	paused=false
	print("PAUSE HUB LAYOUT: ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
