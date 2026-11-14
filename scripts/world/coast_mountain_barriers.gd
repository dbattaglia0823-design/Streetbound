extends Node2D
const Geometry=preload("res://scripts/world/mountain_barrier_geometry.gd")
static var editor_hidden: Dictionary={}
var world: Node2D
var origin_m:=Vector2.ZERO
var indices: Array=[]
func _ready() -> void:material=Geometry.shared_material()
func _draw() -> void:
	for index in indices:
		var region: Dictionary=world.data.terrain[int(index)]
		if editor_hidden.has(Geometry.identity(region,int(index))):continue
		Geometry.draw_art(self,region,world.mountain_art_cache,origin_m)
