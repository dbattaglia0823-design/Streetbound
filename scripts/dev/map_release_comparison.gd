extends RefCounted
## Stable-ID source comparison, ignoring dictionary key order.
const COLLECTIONS=["roads","regions","props","markers","races","dealerships"]
static func compare(before: Dictionary,after: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key in COLLECTIONS:
		var left: Dictionary={};var right: Dictionary={}
		for row in before.get(key,[]):left[str(row.id)]=row
		for row in after.get(key,[]):right[str(row.id)]=row
		var added: Array[String]=[];var removed: Array[String]=[];var changed: Array[String]=[]
		for id in right:
			if not left.has(id):added.append(id)
			elif left[id]!=right[id]:changed.append(id)
		for id in left:
			if not right.has(id):removed.append(id)
		added.sort();removed.sort();changed.sort()
		result[key]={"added":added,"removed":removed,"changed":changed}
	var other: Array[String]=[]
	var keys: Array=before.keys()+after.keys()
	for key in keys:
		if key not in COLLECTIONS and not other.has(key) and before.get(key)!=after.get(key):other.append(key)
	other.sort()
	return {"entities":result,"other":other}

static func text(before: Dictionary,after: Dictionary) -> String:
	var diff:=compare(before,after)
	var rows: PackedStringArray=[]
	for key in COLLECTIONS:
		var row: Dictionary=diff.entities[key]
		rows.append("%s: +%d / −%d / ~%d"%[key.capitalize(),row.added.size(),row.removed.size(),row.changed.size()])
		for field in ["added","removed","changed"]:
			if not row[field].is_empty():rows.append("  "+field+": "+", ".join(PackedStringArray(row[field].slice(0,12)))+(" …" if row[field].size()>12 else ""))
	rows.append("Other fields: "+", ".join(PackedStringArray(diff.other)))
	return "\n".join(rows)
