extends RefCounted
## Only individual map-art textures are loaded; no sheet dependency.
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
const Locator=preload("res://scripts/world/asset_locator.gd")
static var project_textures: Dictionary = {}

## Map artwork must be a complete, individual file. Never load sheet regions.
static func standalone_path(relative: String) -> String:
 if not (relative.begins_with("Buildings/") or relative.begins_with("Map Building Assets/")) or ".." in relative or "\\" in relative or ":" in relative:
  return ""
 if "sprite sheets" in relative.to_lower() or relative.get_extension().to_lower() not in ["png","webp","svg"]:
  return ""
 return Locator.resolve("res://assets/"+relative,"Texture2D",true)

static func project_sprite(relative: String, region: Array = []) -> Texture2D:
 if not region.is_empty():return null
 var path:=standalone_path(relative)
 if path.is_empty():return null
 if project_textures.has(path):return project_textures[path]
 if ResourceLoader.exists(path,"Texture2D"):
  var imported := load(path) as Texture2D
  if imported!=null:
   project_textures[path]=imported
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
 project_textures[path]=texture
 return texture

static func sprite(kind: String, seed_value: int) -> Texture2D:
 if BUILDING_ART.has(kind):
  var available: Array = BUILDING_ART[kind]
  if available.is_empty():return null
  var index: int = posmod(seed_value,available.size())
  return project_sprite(str(available[index]))
 # Vegetation and rocks have their own individual artwork.
 var nature: String={"tree":"Oak.svg","pine":"Pine.svg","palm":"Palm.svg","rock":"Rock.svg"}.get(kind,"")
 if nature.is_empty():return null
 return project_sprite("Map Building Assets/Nature/"+nature)
