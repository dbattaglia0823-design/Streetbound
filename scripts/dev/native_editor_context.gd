extends RefCounted
## Presentation-only context rules. Never modify the draft, layer flags or tool values.
static func resolve(tool: String, category: String="", prop_kind: String="", selection_count: int=0) -> Dictionary:
	var selecting:=tool in ["move_prop","anchor","select_box","inspect"]
	var single:=selecting and selection_count<=1
	var scenery:=tool.begins_with("place:") or (single and category=="props" and prop_kind not in ["sidewalk","guardrail"])
	var road:=tool in ["draw_road","place_circle_road"] or (single and category=="roads")
	var terrain:=tool=="draw_terrain" or (single and category=="regions")
	var marker:=tool=="place_marker" or (single and category=="markers")
	var race:=tool in ["draw_race","race_grid","race_checkpoint"] or (single and category=="races")
	var sidewalk:=tool=="draw_sidewalk"
	var guardrail:=tool=="draw_guardrail"
	var snap:=tool in ["draw_road","place_circle_road","draw_terrain","place_marker","place_dealership","draw_sidewalk","draw_guardrail","draw_race","race_grid","race_checkpoint","anchor"] or tool.begins_with("place:") or (tool=="move_prop" and (not category.is_empty() or selection_count>1))
	return {"road":road,"terrain":terrain,"marker":marker,"race":race,
		"sidewalk":sidewalk,"guardrail":guardrail,"assets":tool.begins_with("place:"),
		"building_snap":scenery,"snap":snap,"dealership":tool=="place_dealership",
		"selected_fields":single and not category.is_empty(),
		"selection_actions":selecting and (not category.is_empty() or selection_count>0),
		"shape_actions":tool in ["draw_road","draw_terrain","draw_sidewalk","draw_guardrail","draw_race"],
		"help":str({"pan":"Drag the map to pan; zoom with the wheel.",
		"move_prop":"Click an object to edit it. Drag empty space for multi-select.",
		"select_box":"Drag a rectangle. Shift adds or removes objects.",
		"anchor":"Select a road or path, then drag its points.",
		"draw_road":"Click points, then Finish or Enter.",
		"draw_terrain":"Click polygon vertices, then Finish or Enter.",
		"place_circle_road":"Set radius and click the circle center.",
		"draw_sidewalk":"Set path width and click points; Finish saves.",
		"draw_guardrail":"Set barrier width and click points; Finish saves.",
		"draw_race":"Click start, checkpoints and finish on roads.",
		"race_grid":"Click to position the selected starting slot.",
		"race_checkpoint":"Click a road to place the next checkpoint.",
		"place_marker":"Choose a marker type, then click the map.",
		"place_dealership":"Click a valid lot center."}.get(tool,"Choose artwork, then click to place." if tool.begins_with("place:") else "Select a tool or map object."))}
