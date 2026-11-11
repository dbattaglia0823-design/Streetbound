extends Node2D
## One cached translucent overlay per streaming chunk with water polygons.
## Shader TIME animates in world space; no _process(), animated sprites or
## repeated world-query work. The base terrain remains fully collision-free.
var water_polys: Array[PackedVector2Array] = []

func _ready() -> void:
    var material_instance := ShaderMaterial.new()
    material_instance.shader = preload("res://scripts/world/coast_water.gdshader")
    material = material_instance

func _draw() -> void:
    for poly in water_polys:
        if poly.size() >= 3:
            draw_colored_polygon(poly, Color(0.80, 0.92, 0.88, 0.85))
