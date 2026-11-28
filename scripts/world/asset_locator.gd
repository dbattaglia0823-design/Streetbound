extends RefCounted
## Exact basename recovery for dynamically referenced assets. No fuzzy matches,
## no cross-project traversal, no automatic choice between duplicate filenames.
const ROOT="res://assets/"
const CACHE_FILE="user://streetbound-asset-locations.cfg"
static var _aliases: Dictionary={}
static var _index: Dictionary={}
static var _scanned:=false
static var _loaded:=false
static var _reported: Dictionary={}

static func _safe(path: String) -> bool:
	if not path.begins_with(ROOT) or "\\" in path or ":" in path.trim_prefix("res://"):return false
	for part in path.trim_prefix(ROOT).split("/"):
		if part in ["",".",".."] or part.begins_with(".") or part.to_lower()=="sprite sheets":return false
	return not FileAccess.file_exists(path.get_basename()+".sheet.json")

static func _exists(path: String,type_hint: String) -> bool:
	return _safe(path) and (ResourceLoader.exists(path,type_hint) or FileAccess.file_exists(path))

static func _allowed(path: String,map_only: bool) -> bool:
	return not map_only or path.begins_with(ROOT+"Buildings/") or path.begins_with(ROOT+"Map Building Assets/")

static func _load_aliases() -> void:
	if _loaded:return
	_loaded=true
	var config:=ConfigFile.new()
	if config.load(CACHE_FILE)==OK:
		var saved: Variant=config.get_value("assets","aliases",{})
		if saved is Dictionary:_aliases=saved

static func _save_aliases() -> void:
	var config:=ConfigFile.new()
	config.set_value("assets","aliases",_aliases)
	config.save(CACHE_FILE)

static func invalidate_index() -> void:
	_index.clear();_scanned=false;_reported.clear()

static func _scan(folder: String) -> void:
	var dir:=DirAccess.open(folder)
	if dir==null:return
	for name in dir.get_directories():
		if name.begins_with(".") or name.to_lower()=="sprite sheets" or dir.is_link(name):continue
		_scan(folder.path_join(name))
	for name in dir.get_files():
		if dir.is_link(name):continue
		# Exported PCKs may expose only the .remap/.import metadata filename.
		var base:=name.trim_suffix(".remap").trim_suffix(".import")
		if base.get_extension().to_lower() not in ["png","webp","svg","jpg","jpeg","wav","ogg","mp3","tres","res","ttf","otf"]:continue
		var path:=folder.path_join(base)
		if not _safe(path):continue
		if not _index.has(base):_index[base]=[]
		if not _index[base].has(path):_index[base].append(path)

static func resolve(path: String,type_hint: String="",map_only: bool=false,report: bool=true) -> String:
	if not _safe(path) or not _allowed(path,map_only):return ""
	if _exists(path,type_hint):return path
	_load_aliases()
	var key:=path+"|"+type_hint+"|"+str(map_only)
	var cached:=str(_aliases.get(key,""))
	if not cached.is_empty() and cached.get_file()==path.get_file() and _allowed(cached,map_only) and _exists(cached,type_hint):return cached
	if not cached.is_empty():
		_aliases.erase(key);invalidate_index()
	if not _scanned:
		_scan(ROOT);_scanned=true
	var matches: Array[String]=[]
	for candidate in _index.get(path.get_file(),[]):
		if _allowed(candidate,map_only) and _exists(candidate,type_hint):matches.append(candidate)
	if matches.size()==1:
		_aliases[key]=matches[0];_save_aliases()
		print("Asset relocated: ",path," -> ",matches[0])
		return matches[0]
	if report and not _reported.has(key):
		_reported[key]=true
		push_warning("Asset recovery failed: "+path+(" (no exact filename match)" if matches.is_empty() else " (multiple exact matches: "+", ".join(matches)+")"))
	return ""
