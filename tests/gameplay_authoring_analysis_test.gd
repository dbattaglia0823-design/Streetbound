extends SceneTree
const Controls=preload("res://scripts/world/authored_gameplay_controls.gd")
const Analysis=preload("res://scripts/dev/gameplay_authoring_analysis.gd")

func _initialize() -> void:
	var doc: Dictionary={"world":{"width":1200,"height":1200},"roads":[{"points":[{"x":100,"y":100},{"x":900,"y":100}]}],"props":[{"x":100,"y":100},{"x":100,"y":100,"hidden":true}],"markers":[{"type":"fuel","x":100,"y":100}],"races":[]}
	var audit:=Analysis.analyze(doc,400,300,[{"p":[100,100],"approaches":[{},{}]}])
	var cell: Dictionary=audit.cells[Vector2i.ZERO]
	if cell.props!=1 or cell.junctions!=2 or "fuel" in cell.missing or not "garage" in cell.missing or not "fuel" in audit.cells[Vector2i(2,0)].missing:
		push_error("FAIL gameplay coverage/heatmap counts");quit(1);return
	if not Analysis.checkpoints({},null,0).is_empty():
		push_error("FAIL invalid route accepted");quit(1);return
	var district: Dictionary={"name":"Test","x":0,"y":0,"w":100,"h":100,"density":50,"speed":30,"patrol":0,"response":100,"models":"commercial"}
	doc["customMap"]=true;doc["gameplayZones"]=[district]
	if not Controls.valid(doc) or Controls.zone({"gameplay_zones":[district]},Vector2(5,5))!=district or not Controls.zone({"gameplay_zones":[district]},Vector2(101,5)).is_empty():
		push_error("FAIL district validation and lookup");quit(1);return
	if not Controls.green(1,0,3) or Controls.green(9,0,3) or not Controls.green(11,1,3) or Controls.model_for(0,10,"commercial")!=6:
		push_error("FAIL signal phases or model groups");quit(1);return
	print("GAMEPLAY AUTHORING ANALYSIS: PASS")
	quit()
