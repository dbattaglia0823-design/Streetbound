extends RefCounted
## Project building PNGs are authoritative. Do not procedurally recreate old
## building artwork from the deprecated scenery atlas.
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
static var project_textures: Dictionary = {}

## Map artwork must be a complete, individual file. Never load sheet regions.
static func standalone_path(relative: String) -> String:
 if not (relative.begins_with("Buildings/") or relative.begins_with("Map Building Assets/")) or ".." in relative or "\\" in relative or ":" in relative:
  return ""
 if "sprite sheets" in relative.to_lower() or relative.get_extension().to_lower() not in ["png","webp","svg"]:
  return ""
 var path := "res://assets/"+relative
 if not ResourceLoader.exists(path,"Texture2D") and not FileAccess.file_exists(path) and relative.begins_with("Buildings/"):
  path = "res://assets/Map Building Assets/"+relative
 if FileAccess.file_exists(path.get_basename()+".sheet.json"):return ""
 return path if ResourceLoader.exists(path,"Texture2D") or FileAccess.file_exists(path) else ""

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
  # Never use the deprecated procedural-building atlas if artwork is absent.
  return project_sprite("Buildings/"+str(available[index]))
 # Vegetation and rocks have their own individual artwork.
 var nature: String={"tree":"Oak.svg","pine":"Pine.svg","palm":"Palm.svg","rock":"Rock.svg"}.get(kind,"")
 if nature.is_empty():return null
 return project_sprite("Map Building Assets/Nature/"+nature)
