extends RefCounted
## Project building PNGs are authoritative. Do not procedurally recreate old
## building artwork from the deprecated scenery atlas.
const AtlasSource = preload("res://assets/scenery/morrow-atlas-v1.png")
const REGIONS = [Rect2(103,28,261,391),Rect2(532,14,273,409),Rect2(968,26,278,396),Rect2(1411,21,281,396),Rect2(26,477,397,380),Rect2(472,467,388,389),Rect2(910,467,406,387),Rect2(1366,500,361,323)]
const BUILDING_ART := {
 "house": ["House.png","House2.png","House3.png","FarmHouse1.png","FarmHouse2.png"],
 "coastal_house": ["House.png","House2.png","House3.png"],
 "lodge": ["FarmHouse1.png","FarmHouse2.png"],
 "shop": ["CornerShop.png","ConnectedBuilding1.png","ConnectedBuilding2.png","ConnectedBuilding3.png","ConnectedBuilding4.png","ConnectedBuilding5.png"],
 "cafe": ["CornerShop.png","Diner.png"],
 "building": ["Apartment.png","Apartment2.png","Office1.png","Office2.png","Office3.png","Large Office.png","Skyscraper.png","Skyscraper2.png","ConnectedBuilding1.png","ConnectedBuilding2.png","ConnectedBuilding3.png","ConnectedBuilding4.png","ConnectedBuilding5.png"],
 "office": ["Office1.png","Office2.png","Office3.png","Large Office.png"],
 "hotel": ["Hotel.png","Apartment.png"],
 "warehouse": ["Warehouse.png","Barn1.png","Barn2.png"],
 "garage": ["Service Garage.png","Warehouse.png"],
 "workshop": ["Service Garage.png","Warehouse.png"],
 "showroom": ["Office1.png","Office2.png","Large Office.png"],
 "fuel": ["Service Garage.png","CornerShop.png"]
}
static var textures: Dictionary = {}
static var project_textures: Dictionary = {}

static func project_sprite(relative: String) -> Texture2D:
 if not relative.begins_with("Buildings/") or ".." in relative or "\\" in relative or ":" in relative:
  return null
 if project_textures.has(relative):return project_textures[relative]
 var path := "res://assets/"+relative
 if ResourceLoader.exists(path,"Texture2D"):
  var imported := load(path) as Texture2D
  if imported!=null:
   project_textures[relative]=imported
   return imported
 if not FileAccess.file_exists(path):return null
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
 if BUILDING_ART.has(kind):
  var available: Array = BUILDING_ART[kind]
  if available.is_empty():return null
  var index: int = posmod(seed_value,available.size())
  # Never use the deprecated procedural-building atlas if artwork is absent.
  return project_sprite("Buildings/"+str(available[index]))
 var index := -1
 match kind:
  "tree":index=4
  "pine":index=5
  "palm":index=6
  "rock":index=7
 if index<0:return null
 if not textures.has(index):
  var atlas := AtlasTexture.new()
  atlas.atlas = AtlasSource
  atlas.region = REGIONS[index]
  atlas.filter_clip = true
  textures[index] = atlas
 return textures[index]
