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
	var file := FileAccess.get_file_as_string("res://scripts/world/coast_roads.gd")
	check("road_wear_is_cached_in_asphalt_stage",
		file.contains("_road_wear(path, r, width, float(batch.phase))"))
	check("gravel_and_race_surfaces_remain_unchanged",
		file.contains('str(road.surface) in ["GRAVEL","DIRT"]') and
		file.contains('str(road.kind) == "track"'))
	check("faded_markings_remain_stationed",file.contains("dash_index"))
	print("MORROW ROAD WEAR: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
