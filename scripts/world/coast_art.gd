extends RefCounted
## Shared atlas regions. Sprites fit the existing metre-scaled footprints;
## artwork never defines collision or road placement.
const AtlasSource = preload("res://assets/scenery/morrow-atlas-v1.png")
const REGIONS = [Rect2(103,28,261,391),Rect2(532,14,273,409),Rect2(968,26,278,396),Rect2(1411,21,281,396),Rect2(26,477,397,380),Rect2(472,467,388,389),Rect2(910,467,406,387),Rect2(1366,500,361,323)]
# All ten supplied city-building sprites and ten showroom/dealership variants
# are used across authored, generated and destination structures. Preloading
# ensures every resource is included in exported builds and cached once.
const BUILDING_ART = [
    preload("res://assets/Buildings/ChatGPT Image Nov 8, 2026, 10_00_32 PM-1.png"),
    preload("res://assets/Buildings/ChatGPT Image Nov 8, 2026, 10_00_34 PM-2.png"),
    preload("res://assets/Buildings/ChatGPT Image Nov 8, 2026, 10_00_35 PM-3.png"),
    preload("res://assets/Buildings/ChatGPT Image Nov 8, 2026, 10_00_38 PM-4.png"),
    preload("res://assets/Buildings/ChatGPT Image Nov 8, 2026, 10_00_39 PM-5.png"),
    preload("res://assets/Buildings/ChatGPT Image Nov 8, 2026, 10_00_41 PM-6.png"),
    preload("res://assets/Buildings/ChatGPT Image Nov 8, 2026, 10_00_42 PM-7.png"),
    preload("res://assets/Buildings/ChatGPT Image Nov 8, 2026, 10_00_44 PM-8.png"),
    preload("res://assets/Buildings/ChatGPT Image Nov 8, 2026, 10_00_46 PM-9.png"),
    preload("res://assets/Buildings/ChatGPT Image Nov 8, 2026, 10_00_48 PM-10.png")
]
const DEALER_ART = [
    preload("res://assets/Buildings/Dealerships/01_junk_car_dealership.png"),
    preload("res://assets/Buildings/Dealerships/02_budget_used_car_dealership.png"),
    preload("res://assets/Buildings/Dealerships/03_used_car_dealership.png"),
    preload("res://assets/Buildings/Dealerships/04_modern_dealership.png"),
    preload("res://assets/Buildings/Dealerships/05_modern_showroom_dealership.png"),
    preload("res://assets/Buildings/Dealerships/06_premium_dealership.png"),
    preload("res://assets/Buildings/Dealerships/07_luxury_dealership.png"),
    preload("res://assets/Buildings/Dealerships/08_exotic_dealership.png"),
    preload("res://assets/Buildings/Dealerships/09_offroad_dealership_service.png"),
    preload("res://assets/Buildings/Dealerships/10_offroad_dealership_showroom.png")
]

static var textures: Dictionary = {}

static func sprite(kind: String, seed_value: int) -> Texture2D:
	# Cycle independently through the complete supplied collections while
	# preserving variant choices across chunk loads and world rebuilds.
	if kind in ["shop","building","warehouse","workshop","fuel","garage"]:
		return BUILDING_ART[posmod(seed_value, BUILDING_ART.size())]
	if kind == "showroom":
		return DEALER_ART[posmod(seed_value, DEALER_ART.size())]
	var index := -1
	match kind:
		"house","lodge": index = 0 if seed_value%3!=0 else 1
		"coastal_house": index = 1
		"shop","cafe": index = 2
		"garage","workshop","warehouse","showroom","fuel","building": index = 3
		"tree": index = 4
		"pine": index = 5
		"palm": index = 6
		"rock": index = 7
	if index<0:
		return null
	if not textures.has(index):
		var atlas := AtlasTexture.new()
		atlas.atlas = AtlasSource
		atlas.region = REGIONS[index]
		atlas.filter_clip = true
		textures[index] = atlas
	return textures[index]
