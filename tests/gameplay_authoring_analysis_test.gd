extends SceneTree
const Analysis=preload("res://scripts/dev/gameplay_authoring_analysis.gd")

func _initialize() -> void:
	var doc: Dictionary={"world":{"width":1200,"height":1200},"roads":[{"points":[{"x":100,"y":100},{"x":900,"y":100}]}],"props":[{"x":100,"y":100},{"x":100,"y":100,"hidden":true}],"markers":[{"type":"fuel","x":100,"y":100}],"races":[]}
	var audit:=Analysis.analyze(doc,400,300,[{"p":[100,100],"approaches":[{},{}]}])
	var cell: Dictionary=audit.cells[Vector2i.ZERO]
	if cell.props!=1 or cell.junctions!=2 or "fuel" in cell.missing or not "garage" in cell.missing or not "fuel" in audit.cells[Vector2i(2,0)].missing:
		push_error("FAIL gameplay coverage/heatmap counts");quit(1);return
	if not Analysis.checkpoints({},null,0).is_empty():
		push_error("FAIL invalid route accepted");quit(1);return
	print("GAMEPLAY AUTHORING ANALYSIS: PASS")
	quit()
