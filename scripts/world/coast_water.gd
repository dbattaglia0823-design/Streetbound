extends Node2D
## Lightweight GPU-animated translucent waves with world-continuous sampling.
## Geometry follows the clipped playable-world polygons, not a rectangular tile.
const PPM := 20.0
var wet_polys: Array[Dictionary] = []
var origin_m := Vector2.ZERO

func _ready() -> void:
    var material_instance := ShaderMaterial.new()
    material_instance.shader = preload("res://scripts/world/coast_water.gdshader")
    material_instance.set_shader_parameter("chunk_origin_px",origin_m*PPM)
    material = material_instance
    queue_redraw()

func _draw() -> void:
    for terrain in wet_polys:
        if terrain.points.size() >= 3:
            draw_colored_polygon(terrain.points,Color.WHITE)
