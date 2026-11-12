extends Node2D
## One cached shadow canvas per streamed chunk, consistent northwest light.
## Procedural buildings, trees and gardens cast depth as well as atlas sprites.
const Art = preload("res://scripts/world/coast_art.gd")
const DowntownPilot = preload("res://scripts/world/downtown_block_pilot.gd")
var prop_list: Array[Dictionary] = []
var origin_m := Vector2.ZERO

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _draw() -> void:
	for prop in prop_list:
		var kind: String = str(prop.kind)
		if kind in ["lot","forecourt","field","start_line","finish_line"]:
			continue
		var size := Vector2(float(prop.size[0]),float(prop.size[1])) * 20.0
		var center := (Vector2(float(prop.p[0]),float(prop.p[1]))-origin_m) * 20.0
		var vegetation := kind in ["tree","pine","palm","garden","planter","island"]
		var structural := kind in ["house","coastal_house","lodge","building","shop",
			"warehouse","garage","workshop","showroom","fuel","cafe",
			"office","hotel"]
		if not (vegetation or structural or kind == "rock" or kind == "parked_car"):
			continue
		var projection := Vector2(.58,.68) * (size.y*.38 if vegetation else size.y*.18)
		var angle := float(prop.angle)
		# Keep projected building silhouettes consistent with the custom art.
		# Otherwise the old workshop atlas casts a mismatched shadow beside
		# the new office/hotel/retail roofs in the selected block.
		var artwork: Texture2D = DowntownPilot.sprite(
			int(prop.downtown_pilot_style)) if prop.has("downtown_pilot_style") else \
			Art.sprite(kind, int(prop.seed))
		draw_set_transform(center+projection,angle)
		if artwork != null:
			# The same atlas silhouette grounds the actual textured roof.
			draw_texture_rect(artwork,Rect2(-size*.5,size),false,Color(.10,.14,.17,.17))
		else:
			# Procedural roofs and planters also cast a shadow. Two very
			# restrained passes provide penumbra without dynamic lighting.
			for softness in [1.10,1.0]:
				var rect := Rect2(-size*.5*softness,size*softness)
				draw_rect(rect,Color(.10,.14,.16,.065 if softness>1.0 else .105),true)
			if vegetation:
				draw_circle(Vector2.ZERO,minf(size.x,size.y)*.44,Color(.12,.18,.14,.11))
	draw_set_transform(Vector2.ZERO)
