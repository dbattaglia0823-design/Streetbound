extends Node2D
## Static sprite silhouettes, projected consistently away from northwest light.
## No dynamic lights or per-frame occluder rebuilding.
const Art = preload("res://scripts/world/coast_art.gd")
var prop_list: Array[Dictionary] = []
var origin_m := Vector2.ZERO

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _draw() -> void:
	for prop in prop_list:
		var sprite: Texture2D = Art.sprite(prop.kind,int(prop.seed))
		if sprite==null: continue
		var size := Vector2(float(prop.size[0]),float(prop.size[1]))*20
		var center := (Vector2(float(prop.p[0]),float(prop.p[1]))-origin_m)*20
		var vegetation: bool = prop.kind in ["tree","pine","palm"]
		var height := size.y*.65 if vegetation else size.y*.22
		if prop.kind=="rock": height=size.y*.3
		var projection := Vector2(.65,.76)*height
		for softness in [1.10,1.0]:
			draw_set_transform(center+projection,float(prop.angle),Vector2.ONE*softness)
			draw_texture_rect(sprite,Rect2(-size*.5,size),false,Color(.12,.18,.20,.10 if softness>1 else .17))
	draw_set_transform(Vector2.ZERO)
