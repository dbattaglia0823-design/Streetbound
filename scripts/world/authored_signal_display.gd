extends Node2D
## Live lenses use exactly the traffic simulation clock. Draw only streamed
## nearby junctions on the player's physical level, never scan the whole map.
const Controls=preload("res://scripts/world/authored_gameplay_controls.gd")
var flow: Node2D
var world: Node2D

func _ready() -> void:
	z_index=35
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(flow) or not is_instance_valid(world):return
	var player: Node2D=flow.get("player")
	if not is_instance_valid(player):return
	var data: Dictionary=world.get("data")
	var size:=float(data.get("chunk_size",192))
	var center:=Vector2i((player.global_position/20.0/size).floor())
	var seen: Dictionary={}
	for dy in range(-2,3):
		for dx in range(-2,3):
			var cell:=center+Vector2i(dx,dy)
			var chunk: Dictionary=data.chunks.get("%d,%d"%[cell.x,cell.y],{})
			for raw in chunk.get("junctions",[]):
				var id:=int(raw)
				if seen.has(id):continue
				seen[id]=true
				var junction: Dictionary=data.junctions[id]
				var count:=int(junction.get("signal_count",0))
				if count<=0 or int(junction.get("road_layer",0))!=int(player.get("road_layer")):continue
				for arm in junction.get("approaches",[]):
					var direction:=Vector2(float(arm.direction[0]),float(arm.direction[1])).normalized()
					var normal:=Vector2(-direction.y,direction.x)
					var p:=Vector2(float(arm.p[0]),float(arm.p[1]))+direction*1.5-normal*(float(arm.width)*.5+.7)
					var green:=Controls.green(float(flow.get("_simulation_clock")),int(arm.get("signal_slot",-1)),count)
					var lens:=Vector2(0,.65 if green else -.65).rotated(direction.angle())
					draw_circle((p+lens)*20.0,5.0,Color("#35ed79") if green else Color("#ff4545"))
