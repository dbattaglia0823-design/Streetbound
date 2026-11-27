extends SceneTree
const Library=preload("res://scripts/dev/native_map_library.gd")
const Publication=preload("res://scripts/world/world_publication.gd")
const Compare=preload("res://scripts/dev/map_release_comparison.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr("FAIL ",label)
func _initialize() -> void:
	var folder: String="user://release-test-%d"%Time.get_ticks_usec()
	OS.set_environment("STREETBOUND_MAP_LIBRARY",folder)
	var doc:=Library.create("Before",1200,1200,"grass")
	var file:=Library.save(doc,"release-test.world.json")
	check(not file.is_empty() and Library.backups(file).is_empty(),"first save")
	check(Library.save(doc,file)==file and Library.backups(file).is_empty(),"unchanged save does not duplicate")
	var original:=doc.duplicate(true)
	doc.name="After"
	check(Library.save(doc,file)==file and Library.backups(file).size()==1,"changed save backs up previous bytes")
	var backup:=Library.load_backup(file,Library.backups(file)[0])
	check(backup==original,"exact previous source")
	for i in 15:
		doc.name="Version %d"%i
		check(Library.save(doc,file)==file,"repeated save")
	check(Library.backups(file).size()==Library.BACKUP_LIMIT,"bounded history")
	check(Library.load_backup(file,"../bad.json").is_empty(),"unsafe backup path refused")
	var a: Dictionary={"roads":[{"id":"a","width":12},{"id":"b","width":10}]}
	var b: Dictionary={"roads":[{"id":"a","width":14},{"id":"c","width":10}]}
	var delta:=Compare.compare(a,b)
	check(delta.entities.roads.added==["c"] and delta.entities.roads.removed==["b"] and delta.entities.roads.changed==["a"],"stable ID comparison")
	var identity: Dictionary={"id":"release-test.world.json","sha256":"a".repeat(64)}
	check(Publication.same_network_identity(identity,identity),"identical multiplayer world")
	check(not Publication.same_network_identity(identity,{"id":identity.id,"sha256":"b".repeat(64)}),"changed archive refused")
	if failures==0:print("MAP RELEASE: PASS")
	quit(0 if failures==0 else 1)
