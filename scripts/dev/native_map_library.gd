extends RefCounted
const ROOT="user://streetbound-maps/"
static func folder() -> String:
	return OS.get_environment("STREETBOUND_MAP_LIBRARY") if OS.has_environment("STREETBOUND_MAP_LIBRARY") else ROOT
static func list_maps() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder()))
	var dir:=DirAccess.open(folder())
	if dir==null:return result
	for name in dir.get_files():
		if not name.ends_with(".world.json"):continue
		var doc=JSON.parse_string(FileAccess.get_file_as_string(folder().path_join(name)))
		if doc is Dictionary and doc.get("customMap",false):result.append({"file":name,"name":str(doc.get("name",name))})
	result.sort_custom(func(a,b):return a.name.naturalnocasecmp_to(b.name)<0)
	return result
static func create(name: String,width: int,height: int,biome: String) -> Dictionary:
	return {"format":"gdt.racing-world","version":2,"customMap":true,"name":name.strip_edges().left(60),
		"world":{"width":width,"height":height,"seed":1847,"base":biome},"roads":[],"regions":[],"props":[],"markers":[],"assets":[],"morrowSourceRoadCount":0,"morrowSourcePoiCount":0}
static func save(doc: Dictionary,file: String="") -> String:
	if not doc.get("customMap",false):return ""
	if file.is_empty():file="map-%s-%s.world.json"%[str(Time.get_unix_time_from_system()).replace(".","-"),str(randi())]
	if file.get_file()!=file or not file.ends_with(".world.json"):return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder()))
	var path:=folder().path_join(file);var temporary:=path+".tmp"
	var stream:=FileAccess.open(temporary,FileAccess.WRITE)
	if stream==null:return ""
	stream.store_string(JSON.stringify(doc,"\t"));stream.flush();stream.close()
	# Replace only after the complete JSON has reached disk.
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path))!=OK:return ""
	return file
static func load_map(file: String) -> Dictionary:
	if file.get_file()!=file:return {}
	var value=JSON.parse_string(FileAccess.get_file_as_string(folder().path_join(file)))
	return value if value is Dictionary else {}
