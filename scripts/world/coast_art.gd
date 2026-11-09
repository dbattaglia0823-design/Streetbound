extends RefCounted
## Shared atlas regions. Sprites fit the existing metre-scaled footprints;
## artwork never defines collision or road placement.
const AtlasSource = preload("res://assets/scenery/morrow-atlas-v1.png")
const REGIONS = [Rect2(103,28,261,391),Rect2(532,14,273,409),Rect2(968,26,278,396),Rect2(1411,21,281,396),Rect2(26,477,397,380),Rect2(472,467,388,389),Rect2(910,467,406,387),Rect2(1366,500,361,323)]
static var textures: Dictionary = {}

static func sprite(kind: String, seed_value: int) -> Texture2D:
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
