extends RefCounted
## Project building PNGs are authoritative. Do not procedurally recreate old
## building artwork from the deprecated scenery atlas.
const AtlasSource = preload("res://assets/scenery/morrow-atlas-v1.png")
const REGIONS = [Rect2(103,28,261,391),Rect2(532,14,273,409),Rect2(968,26,278,396),Rect2(1411,21,281,396),Rect2(26,477,397,380),Rect2(472,467,388,389),Rect2(910,467,406,387),Rect2(1366,500,361,323)]
const BUILDING_ART := {
 "house": ["Map Building Assets/Buildings/Rural Building-Houses/House.png","Map Building Assets/Buildings/Rural Building-Houses/House2.png","Map Building Assets/Buildings/Rural Building-Houses/House3.png","Map Building Assets/Buildings/Farm/FarmHouse1.png","Map Building Assets/Buildings/Farm/FarmHouse2.png"],
 "coastal_house": ["Map Building Assets/Buildings/Rural Building-Houses/House.png","Map Building Assets/Buildings/Rural Building-Houses/House2.png","Map Building Assets/Buildings/Rural Building-Houses/House3.png"],
 "lodge": ["Map Building Assets/Buildings/Farm/FarmHouse1.png","Map Building Assets/Buildings/Farm/FarmHouse2.png"],
 "shop": ["Map Building Assets/Buildings/City Buildings/CornerShop.png","Map Building Assets/Buildings/City Buildings/ConnectedBuilding1.png","Map Building Assets/Buildings/City Buildings/ConnectedBuilding2.png","Map Building Assets/Buildings/City Buildings/ConnectedBuilding3.png","Map Building Assets/Buildings/City Buildings/ConnectedBuilding4.png","Map Building Assets/Buildings/City Buildings/ConnectedBuilding5.png"],
 "cafe": ["Map Building Assets/Buildings/City Buildings/CornerShop.png","Map Building Assets/Buildings/City Buildings/Diner.png"],
 "building": ["Map Building Assets/Buildings/City Buildings/Apartment.png","Map Building Assets/Buildings/City Buildings/Apartment2.png","Map Building Assets/Buildings/City Buildings/Office1.png","Map Building Assets/Buildings/City Buildings/Office2.png","Map Building Assets/Buildings/City Buildings/Office3.png","Map Building Assets/Buildings/City Buildings/Large Office.png","Map Building Assets/Buildings/Skyscraper/Skyscraper.png","Map Building Assets/Buildings/Skyscraper/Skyscraper2.png","Map Building Assets/Buildings/City Buildings/ConnectedBuilding1.png","Map Building Assets/Buildings/City Buildings/ConnectedBuilding2.png","Map Building Assets/Buildings/City Buildings/ConnectedBuilding3.png","Map Building Assets/Buildings/City Buildings/ConnectedBuilding4.png","Map Building Assets/Buildings/City Buildings/ConnectedBuilding5.png"],
 "office": ["Map Building Assets/Buildings/City Buildings/Office1.png","Map Building Assets/Buildings/City Buildings/Office2.png","Map Building Assets/Buildings/City Buildings/Office3.png","Map Building Assets/Buildings/City Buildings/Large Office.png"],
 "hotel": ["Map Building Assets/Buildings/City Buildings/Hotel.png","Map Building Assets/Buildings/City Buildings/Apartment.png"],
 "warehouse": ["Map Building Assets/Buildings/City Buildings/Warehouse.png","Map Building Assets/Buildings/Farm/Barn1.png","Map Building Assets/Buildings/Farm/Barn2.png"],
 "garage": ["Map Building Assets/Buildings/Garages/Service Garage.png","Map Building Assets/Buildings/City Buildings/Warehouse.png"],
 "workshop": ["Map Building Assets/Buildings/Garages/Service Garage.png","Map Building Assets/Buildings/City Buildings/Warehouse.png"],
 "showroom": ["Map Building Assets/Buildings/City Buildings/Office1.png","Map Building Assets/Buildings/City Buildings/Office2.png","Map Building Assets/Buildings/City Buildings/Large Office.png"],
 "fuel": ["Map Building Assets/Buildings/Garages/Service Garage.png","Map Building Assets/Buildings/City Buildings/CornerShop.png"]
}
static var textures: Dictionary = {}
static var project_textures: Dictionary = {}
static var project_sources: Dictionary = {}

static func project_sprite(relative: String, region: Array = []) -> Texture2D:
 if not (relative.begins_with("Buildings/") or relative.begins_with("Map Building Assets/")) or ".." in relative or "\\" in relative or ":" in relative:
  return null
 var key := relative + (":" + str(region) if region.size() == 4 else "")
 if project_textures.has(key):return project_textures[key]
 var path := "res://assets/"+relative
 if not ResourceLoader.exists(path,"Texture2D") and not FileAccess.file_exists(path) and relative.begins_with("Buildings/"):
  # Preserve references saved before Buildings moved under Map Building Assets.
  path = "res://assets/Map Building Assets/"+relative
 if project_sources.has(path):
  var cached := _region_texture(project_sources[path],region)
  project_textures[key]=cached
  return cached
 if ResourceLoader.exists(path,"Texture2D"):
  var imported := load(path) as Texture2D
  if imported!=null:
   project_sources[path]=imported
   var selected := _region_texture(imported,region)
   project_textures[key]=selected
   return selected
 if not FileAccess.file_exists(path):return null
 var image := Image.new()
 var result: Error = ERR_FILE_UNRECOGNIZED
 match path.get_extension().to_lower():
  "png":result=image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
  "webp":result=image.load_webp_from_buffer(FileAccess.get_file_as_bytes(path))
  "svg":result=image.load_svg_from_string(FileAccess.get_file_as_string(path))
 if result!=OK:return null
 var texture := ImageTexture.create_from_image(image)
 project_sources[path]=texture
 var selected := _region_texture(texture,region)
 project_textures[key]=selected
 return selected

static func _region_texture(texture: Texture2D, region: Array) -> Texture2D:
 if region.is_empty():return texture
 if region.size()!=4:return null
 var x := int(region[0])
 var y := int(region[1])
 var w := int(region[2])
 var h := int(region[3])
 if x<0 or y<0 or w<1 or h<1 or x+w>texture.get_width() or y+h>texture.get_height():return null
 var crop := AtlasTexture.new()
 crop.atlas=texture
 crop.region=Rect2(x,y,w,h)
 crop.filter_clip=true
 return crop

static func sprite(kind: String, seed_value: int) -> Texture2D:
 if BUILDING_ART.has(kind):
  var available: Array = BUILDING_ART[kind]
  if available.is_empty():return null
  var index: int = posmod(seed_value,available.size())
  # Never use the deprecated procedural-building atlas if artwork is absent.
  return project_sprite(str(available[index]))
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
