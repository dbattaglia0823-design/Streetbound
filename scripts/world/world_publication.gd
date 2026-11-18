extends RefCounted
## Production world selection is a checked-in, exportable manifest. User map
## drafts and temporary Test Drive archives never affect normal gameplay.
const MANIFEST="res://worlds/active-world.json"
const MORROW="res://worlds/morrow-coast.world.json"
const PUBLISHED_PREFIX="res://worlds/published/"

static func default_world() -> Dictionary:
	return {"format":"streetbound.active-world","version":1,"mode":"morrow",
		"id":"morrow-coast","name":"Morrow Coast","archive":MORROW,
		"published":false}

static func is_published_archive_path(path: String) -> bool:
	if not path.begins_with(PUBLISHED_PREFIX):return false
	var name: String=path.trim_prefix(PUBLISHED_PREFIX)
	if name.contains("/") or name.contains("\\") or not name.begins_with("world-") or \
			not name.ends_with(".world.json"):return false
	var digest: String=name.trim_prefix("world-").trim_suffix(".world.json")
	if digest.length()!=20:return false
	for digit in digest:
		if not "0123456789abcdef".contains(digit):return false
	return true

static func resolve_manifest(value: Variant) -> Dictionary:
	var fallback:=default_world()
	if not value is Dictionary:return fallback
	if value.get("format","")!="streetbound.active-world" or int(value.get("version",0))!=1:
		return fallback
	if value.get("mode","morrow")=="morrow":return fallback
	if value.get("mode","")!="published":return fallback
	var archive: String=str(value.get("archive",""))
	var source: String=str(value.get("source",""))
	if not is_published_archive_path(archive):return fallback
	var digest: String=archive.get_file().trim_prefix("world-")
	var expected: String=PUBLISHED_PREFIX+"source-"+digest
	if source!=expected:return fallback
	var identity: String=str(value.get("id",""))
	if not identity.ends_with(".world.json") or identity.get_file()!=identity or \
			identity.length()>100 or identity.is_empty():return fallback
	if not FileAccess.file_exists(archive) or not FileAccess.file_exists(source):return fallback
	return {"format":"streetbound.active-world","version":1,"mode":"published",
		"id":identity,"name":str(value.get("name","Published Map")).left(60),
		"archive":archive,"source":source,"published":true}

static func current() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST):return default_world()
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return resolve_manifest(parsed)
