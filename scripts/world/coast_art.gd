extends RefCounted
## Shared atlas regions. Sprites fit the existing metre-scaled footprints;
## artwork never defines collision or road placement.
const AtlasSource = preload("res://assets/scenery/morrow-atlas-v1.png")
const REGIONS = [Rect2(103,28,261,391),Rect2(532,14,273,409),Rect2(968,26,278,396),Rect2(1411,21,281,396),Rect2(26,477,397,380),Rect2(472,467,388,389),Rect2(910,467,406,387),Rect2(1366,500,361,323)]
static var textures: Dictionary = {}
static var project_textures: Dictionary = {}

static func project_sprite(relative: String) -> Texture2D:
	if not relative.begins_with("Buildings/") or ".." in relative or "\\" in relative or ":" in relative:
		return null
	if project_textures.has(relative):return project_textures[relative]
	var path := "res://assets/"+relative
	if ResourceLoader.exists(path,"Texture2D") and (FileAccess.file_exists(path+".import") or OS.has_feature("template")):
		var imported := load(path) as Texture2D
		if imported!=null:
			project_textures[relative]=imported
			return imported
	if not FileAccess.file_exists(path):return null
	# Decode source files directly, including art added since the last import.
	var image := Image.new()
	var result: Error = ERR_FILE_UNRECOGNIZED
	match path.get_extension().to_lower():
		"png":result=image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		"webp":result=image.load_webp_from_buffer(FileAccess.get_file_as_bytes(path))
		"svg":result=image.load_svg_from_string(FileAccess.get_file_as_string(path))
	if result!=OK:return null
	var texture := ImageTexture.create_from_image(image)
	project_textures[relative]=texture
	return texture

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
