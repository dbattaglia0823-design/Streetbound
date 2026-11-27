extends RefCounted
const ROOT="user://streetbound-maps/"
const BACKUP_LIMIT:=12
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
	if not _safe_filename(file):return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder()))
	var path:=folder().path_join(file);var temporary:=path+".tmp"
	var payload:=JSON.stringify(doc,"\t",true,true)
	if FileAccess.file_exists(path):
		var old:=FileAccess.get_file_as_bytes(path)
		if old!=payload.to_utf8_buffer() and not _backup(file,old):return ""
	var stream:=FileAccess.open(temporary,FileAccess.WRITE)
	if stream==null:return ""
	stream.store_string(payload);stream.flush();stream.close()
	if FileAccess.get_sha256(temporary)!=payload.sha256_text():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary));return ""
	# Replace only after the complete JSON has reached disk.
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path))!=OK:return ""
	return file
static func load_map(file: String) -> Dictionary:
	if not _safe_filename(file):return {}
	var value=JSON.parse_string(FileAccess.get_file_as_string(folder().path_join(file)))
	return value if value is Dictionary else {}

static func _safe_filename(file: String) -> bool:
	if file.is_empty() or file.length()>100 or file.get_file()!=file or not file.ends_with(".world.json"):return false
	for character in file:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-".contains(character):return false
	return true

## Move a local custom source and any recovery journals out of the selector.
## Never recursively delete files, touch project resources, or overwrite trash.
static func trash_map(file: String,protected_file: String,expected_sha: String) -> Dictionary:
	if not _safe_filename(file) or file==protected_file:
		return {"ok":false,"error":"This map is protected or has an invalid filename."}
	var source:=folder().path_join(file)
	var doc:=load_map(file)
	if doc.get("customMap",false)!=true or doc.get("format","")!="gdt.racing-world" or int(doc.get("version",0))!=2:
		return {"ok":false,"error":"No valid local custom map exists at this filename."}
	if expected_sha.is_empty() or FileAccess.get_sha256(source)!=expected_sha:
		return {"ok":false,"error":"The saved map changed. Reopen the delete confirmation."}
	var trash:=folder().path_join("deleted-maps").path_join("%s-%d-%d"%[file.sha256_text().left(12),Time.get_ticks_usec(),randi()])
	var absolute:=ProjectSettings.globalize_path(trash)
	if DirAccess.dir_exists_absolute(absolute) or DirAccess.make_dir_recursive_absolute(absolute)!=OK:
		return {"ok":false,"error":"Could not create a recovery folder. Map was kept."}
	var moved: Array[String]=[]
	# Move journals first so they cannot resurrect an old preset when reopened.
	for name in [file+".draft.json",file+".draft.json.tmp",file+".tmp",file]:
		var origin:=ProjectSettings.globalize_path(folder().path_join(name))
		if not FileAccess.file_exists(origin):
			if name!=file:continue
		elif DirAccess.rename_absolute(origin,ProjectSettings.globalize_path(trash.path_join(name)))==OK:
			moved.append(name)
			continue
		var rollback_ok:=true
		for previous in moved:
			if DirAccess.rename_absolute(ProjectSettings.globalize_path(trash.path_join(previous)),ProjectSettings.globalize_path(folder().path_join(previous)))!=OK:
				rollback_ok=false
		if rollback_ok:DirAccess.remove_absolute(absolute)
		return {"ok":false,"error":"Map deletion failed. Map was kept." if rollback_ok else "Map deletion failed; recovery files are retained at "+absolute}
	return {"ok":true,"folder":absolute}

static func backup_folder(file: String) -> String:
	if file.get_file()!=file or not file.ends_with(".world.json"):return ""
	return folder().path_join("automatic-backups").path_join(file.sha256_text().left(32))

static func backups(file: String) -> Array[String]:
	var result: Array[String]=[]
	var root:=backup_folder(file)
	if root.is_empty():return result
	var dir:=DirAccess.open(root)
	if dir==null:return result
	for name in dir.get_files():
		if name.begins_with("save-") and name.ends_with(".json"):result.append(name)
	result.sort();result.reverse()
	return result

static func _backup(file: String,bytes: PackedByteArray) -> bool:
	if bytes.is_empty():return false
	var root:=backup_folder(file)
	if root.is_empty() or DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))!=OK:return false
	var name: String="save-%020d-%d.json"%[int(Time.get_unix_time_from_system()*1000000.0),randi()]
	var path:=root.path_join(name)
	var stream:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if stream==null:return false
	stream.store_buffer(bytes);stream.flush();stream.close()
	var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(bytes)
	if FileAccess.get_sha256(path+".tmp")!=hashing.finish().hex_encode():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".tmp"));return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))!=OK:return false
	var prior:=backups(file)
	for i in range(BACKUP_LIMIT,prior.size()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join(prior[i])))
	return true

static func load_backup(file: String,name: String) -> Dictionary:
	if name.get_file()!=name or not name in backups(file):return {}
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(backup_folder(file).path_join(name)))
	return parsed if parsed is Dictionary and parsed.get("customMap",false) else {}
