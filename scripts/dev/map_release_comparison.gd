extends RefCounted
## Stable-ID source comparison, ignoring dictionary key order.
const COLLECTIONS=["roads","regions","props","markers","races","dealerships"]
# A JSON round trip may represent integral source values as floats.
static func equal_value(a: Variant,b: Variant) -> bool:
	if typeof(a) in [TYPE_INT,TYPE_FLOAT] and typeof(b) in [TYPE_INT,TYPE_FLOAT]:
		if typeof(a)==TYPE_INT and typeof(b)==TYPE_INT:return a==b
		var left:=float(a);var right:=float(b)
		if left==right:return true
		if not is_finite(left) or not is_finite(right):return false
		# JSON decimal decoding can differ by a few floating-point ULPs.
		return absf(left-right)<=maxf(1.0, maxf(absf(left),absf(right)))*0.00000000000001
	if typeof(a)!=typeof(b):return false
	if a is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not equal_value(a[key],b[key]):return false
		return true
	if a is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not equal_value(a[i],b[i]):return false
		return true
	return a==b

static func compare(before: Dictionary,after: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for key in COLLECTIONS:
		var left: Dictionary={};var right: Dictionary={}
		for row in before.get(key,[]):left[str(row.id)]=row
		for row in after.get(key,[]):right[str(row.id)]=row
		var added: Array[String]=[];var removed: Array[String]=[];var changed: Array[String]=[]
		for id in right:
			if not left.has(id):added.append(id)
			elif not equal_value(left[id],right[id]):changed.append(id)
		for id in left:
			if not right.has(id):removed.append(id)
		added.sort();removed.sort();changed.sort()
		result[key]={"added":added,"removed":removed,"changed":changed}
	var other: Array[String]=[]
	var keys: Array=before.keys()+after.keys()
	for key in keys:
		if key not in COLLECTIONS and not other.has(key) and not equal_value(before.get(key),after.get(key)):other.append(key)
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
