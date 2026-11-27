extends RefCounted
## Presentation-only contact metadata. No save changes or reward authority.
const Rules = preload("res://scripts/world/driving_contract_rules.gd")
const PERSONAS := {
	"racing": {"role":"RACING PROMOTER","greeting":"Show me what you can do on the track. Good drivers get introductions.","bio":"Organizes underground races and connects proven drivers with higher-paying jobs.","accent":Color("#e9a86e")},
	"street": {
		"role": "STREET FIXER",
		"greeting": "I know the roads, and I know who needs a good driver.",
		"bio": "Fast jobs. Discreet introductions. A reputation is earned behind the wheel.",
		"accent": Color("#f3a65b")
	},
	"business": {
		"role": "CONTRACT BROKER",
		"greeting": "I value punctuality. The details are in the brief.",
		"bio": "Well-organized work, demanding clients and worthwhile payouts.",
		"accent": Color("#78c9c2")
	},
	"mechanic": {
		"role": "GARAGE CONNECTION",
		"greeting": "Keep your motor running and I will keep the jobs coming.",
		"bio": "Parts runs, special deliveries and favors for the automotive underground.",
		"accent": Color("#e2ba72")
	},
	"casual": {
		"role": "LOCAL INSIDER",
		"greeting": "You look like someone who knows how to get around town.",
		"bio": "Neighborhood tips, short runs and connections to bigger opportunities.",
		"accent": Color("#a8cf8d")
	}
}
const KIND_DESCRIPTIONS := {
	"courier": "Pick up the package and deliver it before the deadline. Stay behind the wheel.",
	"smuggling": "Transport restricted cargo and lose police attention before the drop-off.",
	"getaway": "Keep the vehicle moving, escape the pursuit and reach the designated safe point.",
	"robbery": "Drive to the target, wait in the car for the crew, evade police and reach the getaway point."
}

static func _with_fallback(properties: Dictionary, field: String, fallback: String) -> String:
	var value := str(properties.get(field, "")).strip_edges()
	return fallback if value.is_empty() else value

static func identity(contact: Dictionary) -> Dictionary:
	var properties: Dictionary = contact.get("properties", {})
	var style := str(properties.get("contact_style", "street"))
	var preset: Dictionary = PERSONAS.get(style, PERSONAS["street"])
	return {
		"name": str(contact.get("name", "UNKNOWN CONTACT")).strip_edges(),
		"role": _with_fallback(properties, "contact_role", str(preset["role"])),
		"greeting": _with_fallback(properties, "contact_greeting", str(preset["greeting"])),
		"bio": _with_fallback(properties, "contact_bio", str(preset["bio"])),
		"accent": preset["accent"],
		"style": style
	}

static func description(offer: Dictionary) -> String:
	var custom := str(offer.get("description", "")).strip_edges()
	if not custom.is_empty():
		return custom
	return str(KIND_DESCRIPTIONS.get(str(offer.get("kind","")), "Complete the driving objective."))

static func event_key(world_id: String, contact: Dictionary, offer: Dictionary) -> String:
	return world_id + "::" + str(contact.get("id","")) + "_" + str(offer.get("id",""))

static func completions(history: Dictionary, world_id: String,
		contact: Dictionary, offer: Dictionary) -> int:
	return maxi(0, int(history.get(event_key(world_id,contact,offer), 0)))

static func offer_state(completed: int, repeatable: bool, lock_reason: String) -> String:
	if completed > 0 and not repeatable:
		return "COMPLETED"
	if lock_reason.begins_with("COOLDOWN ") or lock_reason.begins_with("ROTATES IN "):
		return lock_reason
	if not lock_reason.is_empty():
		return "LOCKED"
	if completed > 0:
		return "REPEATABLE / %d COMPLETE" % completed
	return "AVAILABLE"

static func can_accept(completed: int, repeatable: bool, lock_reason: String) -> bool:
	return lock_reason.is_empty() and (completed == 0 or repeatable)
