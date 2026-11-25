extends SceneTree
const Kerbs=preload("res://scripts/world/track_kerbs.gd")
var failures:Array[String]=[]
func _initialize() -> void:
	call_deferred("run")
func check(label: String,passed: bool) -> void:
	print("%s %s"%["PASS" if passed else "FAIL",label])
	if not passed:failures.append(label)
func run() -> void:
	check("baked_track_recognized",Kerbs.is_track({"kind":"track","surface":"ASPHALT"}))
	check("authored_track_recognized",Kerbs.is_track({"roadClass":"track","surface":"asphalt"}))
	check("legacy_racing_surface_recognized",Kerbs.is_track({"roadClass":"city","surface":"track"}))
	check("normal_street_has_no_kerbs",not Kerbs.is_track({"kind":"local","surface":"ASPHALT"}))
	var path:=PackedVector2Array([Vector2.ZERO,Vector2(180,0)])
	var pieces:=Kerbs.stripes(path)
	check("alternating_three_metre_stripes",pieces.size()==3 and pieces[0].red and not pieces[1].red and pieces[2].red)
	var seam:=Kerbs.stripes(PackedVector2Array([Vector2(90,0),Vector2(180,0)]),90.0)
	check("chunk_seam_retains_global_stripe_phase",seam.size()==2 and not seam[0].red and seam[1].red and is_equal_approx(float(seam[0].to),1.0/3.0))
	var curve:=Kerbs.stripes(PackedVector2Array([Vector2.ZERO,Vector2(30,0),Vector2(30,90)]))
	check("curve_continues_stripe_through_vertices",curve.size()==3 and curve[0].red and curve[1].red and not curve[2].red)
	print("TRACK KERBS: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
