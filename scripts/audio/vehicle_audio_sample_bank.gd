class_name VehicleAudioSampleBank
extends RefCounted
## Optional imported *cleared/licensed* recordings. Prefer exact car files,
## then engine family. No recordings are bundled by this resolver itself.
const ROOT := "res://assets/audio/engines"
const EXTENSIONS := [".ogg",".wav",".mp3"]


static func _safe(token: String) -> bool:
	if token.is_empty() or token.length() > 80:
		return false
	for i in token.length():
		var code := token.unicode_at(i)
		if not ((code >= 97 and code <= 122) or \
			(code >= 48 and code <= 57) or code == 45 or code == 95):
			return false
	return true


static func path_for(profile_id: String, slot: String, extension := ".ogg") -> String:
	if not _safe(profile_id) or not _safe(slot) or \
		not EXTENSIONS.has(extension):
		return ""
	return "%s/%s/%s%s" % [ROOT,profile_id,slot,extension]


static func resolve(model_id: String, family: String, slot: String,
		explicit: AudioStream = null) -> AudioStream:
	# Explicit designer override always wins; do not probe disk repeatedly
	# in _process. Only called when equipping or updating a vehicle.
	if explicit != null:
		return explicit
	for key in [model_id,family]:
		if not _safe(key) or not _safe(slot):
			continue
		for ext in EXTENSIONS:
			var path := path_for(key,slot,ext)
			if not path.is_empty() and ResourceLoader.exists(path,"AudioStream"):
				var candidate := ResourceLoader.load(path) as AudioStream
				if candidate != null:
					return candidate
	return null
