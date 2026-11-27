extends SceneTree
## Road-surface wear must follow absolute road stationing, not chunk-local
## coordinates. Re-streaming or splitting a curve cannot duplicate marks.
const Roads = preload("res://scripts/world/coast_roads.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	print(("%s: " % label) + ("PASS" if passed else "FAIL"))
	if not passed:
		failures.append(label)

func run() -> void:
	var entire: PackedFloat32Array = Roads.wear_stations(0.0, 2400.0)
	var front: PackedFloat32Array = Roads.wear_stations(0.0, 960.0)
	var back: PackedFloat32Array = Roads.wear_stations(960.0, 1440.0)
	front.append_array(back)
	check("chunk_split_keeps_global_station_positions",front == entire)
	check("global_spacing_is_bounded",entire.size() == 5 and entire[1] == 480.0)
	check("zero_length_produces_no_marks",Roads.wear_stations(0.0, 0.0).is_empty())
	check("invalid_spacing_produces_no_marks",Roads.wear_stations(0.0, 120.0, 0.0).is_empty())
	check("shifted_segment_starts_at_next_station",
		Roads.wear_stations(510.0, 520.0) == PackedFloat32Array([960.0]))
	var highway := Roads.marking_plan({"kind":"highway","lanes":4,"surface":"ASPHALT"},360.0)
	check("highway_double_yellow_and_two_white_lane_dividers",highway.size()==6 and highway[0].color==Roads.PAINT_YELLOW and highway[1].color==Roads.PAINT_YELLOW and highway[2].color==Roads.PAINT_WHITE and highway[2].dash==60.0 and highway[2].gap==180.0)
	var ramp := Roads.marking_plan({"kind":"onramp","lanes":1,"surface":"ASPHALT"},160.0)
	check("one_way_ramp_has_only_edge_lines",ramp.size()==2 and ramp[0].dash==0.0 and ramp[1].dash==0.0 and ramp[0].offset<0 and ramp[1].offset>0)
	var odd := Roads.marking_plan({"kind":"arterial","lanes":3,"surface":"ASPHALT"},240.0,false)
	check("odd_lane_divider_follows_actual_lane_layout",odd.size()==3 and is_equal_approx(float(odd[0].offset)+3.5,40.0) and is_equal_approx(float(odd[2].offset),-40.0))
	check("loose_and_alley_roads_stay_unpainted",Roads.marking_plan({"kind":"local","surface":"GRAVEL"},200.0).is_empty() and Roads.marking_plan({"kind":"alley","surface":"ASPHALT"},120.0).is_empty())
	var spans := Roads.dash_spans(50.0,250.0,60.0,180.0)
	check("dash_phase_resumes_after_clipped_station",spans.size()==2 and is_equal_approx(float(spans[0].to),.04) and is_equal_approx(float(spans[1].from),.76))
	var file := FileAccess.get_file_as_string("res://scripts/world/coast_roads.gd")
	check("road_wear_is_cached_in_asphalt_stage",
		file.contains("_road_wear(path, r, width, float(batch.phase))"))
	check("gravel_and_race_surfaces_remain_unchanged",
		file.contains('str(road.surface) in ["GRAVEL","DIRT"]') and
		file.contains('str(road.kind) == "track"'))
	check("faded_markings_remain_stationed",file.contains("dash_index"))
	print("MORROW ROAD WEAR: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
