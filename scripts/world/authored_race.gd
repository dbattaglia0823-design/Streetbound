extends Node2D
## Ordered checkpoint time trials authored in the map editor. Detours never
## cancel a run; only reaching every gate in order can complete it.
const PPM=20.0
const Definition=preload("res://scripts/world/authored_race_definition.gd")
const StartArea=preload("res://scripts/world/race_start_area.gd")
const Navigation=preload("res://scripts/world/race_navigation.gd")
const Guidance=preload("res://scripts/world/race_guidance.gd")
const Status=preload("res://scripts/ui/race_status_strip.gd")
const Planner=preload("res://scripts/world/road_route_planner.gd")
var definition: Dictionary={}
var world: Node2D
var player: VehicleController2D
var network: RefCounted
var state:="idle"
var available:=false
var race_title:="Editor race"
var race_type:="Sprint · Time Trial"
var start_m:=Vector2.ZERO
var finish_m:=Vector2.ZERO
var heading:=Vector2.UP
var start_radius_m:=8.0
var navigation: RefCounted
var world_guidance: Node2D
var status_strip: Control
var checkpoints:=PackedVector2Array()
var next_checkpoint:=1
var lap:=1
var elapsed:=0.0
var countdown:=0.0
var status_timer:=0.0
var result:=""
var _previous_m:=Vector2.ZERO
var _gate_armed:=true
var _draw_clock:=0.0
func _ready() -> void:
	if not is_instance_valid(world) or not is_instance_valid(player):return
	if not Definition.valid(definition,float(world.data.size[0]),float(world.data.size[1])):return
	name=str(definition.id);race_title=str(definition.name)
	start_radius_m=float(definition.get("start_radius",8))
	race_type=("Circuit" if definition.mode=="circuit" else "Sprint")+" · Time Trial"
	for p in definition.points:checkpoints.append(Vector2(p.x,p.y))
	start_m=checkpoints[0];finish_m=start_m if definition.mode=="circuit" else checkpoints[-1]
	heading=(checkpoints[1]-start_m).normalized()
	navigation=Navigation.new();navigation.setup(checkpoints,definition.mode=="circuit")
	world_guidance=Guidance.new();add_child(world_guidance)
	var layer:=CanvasLayer.new();layer.layer=7;add_child(layer)
	status_strip=Status.new();layer.add_child(status_strip)
	available=true;z_index=6;add_to_group("streetbound_race");_refresh();queue_redraw()
func _exit_tree() -> void:
	if is_instance_valid(player) and state in ["countdown","running"]:player.remove_from_group("race_participant")
func can_stage() -> bool:
	return available and state=="idle" and not StartArea.busy(self) and is_instance_valid(player) and player.global_position.distance_to(start_m*PPM)<=float(definition.get("start_radius",8))*PPM and StartArea.can_stage_at_speed(player.linear_velocity.length()) and Vector2.UP.rotated(player.rotation).dot(heading)>=.35
func start_race() -> bool:
	if not can_stage() or get_tree().paused:return false
	StartArea.settle_for_countdown(player)
	_prepare_guidance()
	state="countdown";countdown=3;elapsed=0;next_checkpoint=1;lap=1;result="";_gate_armed=true
	_previous_m=player.global_position/PPM;player.add_to_group("race_participant");_refresh();return true
func _prepare_guidance() -> void:
	if network==null:return
	var planner=Planner.new();planner.setup(network,world.data)
	var route:=PackedVector2Array()
	var count:=checkpoints.size() if definition.mode=="circuit" else checkpoints.size()-1
	for i in count:
		var a:=checkpoints[i];var b:=checkpoints[(i+1)%checkpoints.size()]
		var planned: Dictionary=planner.plan(a,b,(b-a).normalized())
		var part: PackedVector2Array=planned.get("points_m",PackedVector2Array([a,b]))
		for p in part:
			if route.is_empty() or route[-1].distance_to(p)>.1:route.append(p)
	navigation.setup(route,definition.mode=="circuit")
func quit_race() -> bool:
	if state not in ["countdown","running"]:return false
	state="idle";elapsed=0;countdown=0;result=""
	player.remove_from_group("race_participant")
	world_guidance.set_guidance(navigation,player,false)
	_refresh();queue_redraw();return true
func _finish(message: String) -> void:
	state="results";result=message;status_timer=8
	player.remove_from_group("race_participant")
	world_guidance.set_guidance(navigation,player,false);queue_redraw()
func _physics_process(dt: float) -> void:
	if not available or not is_instance_valid(player) or dt<=0:return
	var at:=player.global_position/PPM
	if state=="countdown":
		if at.distance_to(start_m)>float(definition.get("start_radius",8))+3 or player.linear_velocity.length()>4:
			_finish("FALSE START / RETURN TO GRID")
		else:
			countdown-=dt
			if countdown<=0:state="running";_previous_m=at
	elif state=="running":
		elapsed+=dt
		var gate: Vector2=checkpoints[next_checkpoint]
		var radius:=float(definition.get("checkpoint_radius",16))
		var step:=at.distance_to(_previous_m)
		if step>maxf(5,player.linear_velocity.length()*dt*2+3):_gate_armed=false
		if at.distance_to(gate)>radius:_gate_armed=true
		if _gate_armed and step<=maxf(5,player.linear_velocity.length()*dt*2+3) and Geometry2D.get_closest_point_to_segment(gate,_previous_m,at).distance_to(gate)<=radius:
			if next_checkpoint==0 or (definition.mode=="sprint" and next_checkpoint==checkpoints.size()-1):
				if definition.mode=="circuit" and lap<int(definition.get("laps",1)):lap+=1;next_checkpoint=1
				else:_finish("%s / %.2f SECONDS\nTIME TRIAL COMPLETE / NO REWARDS"%[race_title,elapsed])
			else:next_checkpoint=(next_checkpoint+1)%checkpoints.size()
			_gate_armed=true;queue_redraw()
		_previous_m=at
		var limit:=float(definition.get("time_limit",0))
		if state=="running" and limit>0 and elapsed>limit:_finish("TIME LIMIT REACHED")
	elif state=="results":
		status_timer-=dt
		if status_timer<=0:state="idle";result=""
	world_guidance.set_guidance(navigation,player,state in ["countdown","running"])
	_draw_clock+=dt
	if _draw_clock>=.1:_draw_clock=0;_refresh();queue_redraw()
func _refresh() -> void:
	if not is_instance_valid(status_strip):return
	var nearby: bool=player.global_position.distance_to(start_m*PPM)<30*PPM
	var message:=result
	match state:
		"idle":message="%s / %s\n%s"%[race_title,race_type,"[ F ] START" if can_stage() else "SLOW TO 15 MPH / FACE ROUTE" if not StartArea.can_stage_at_speed(player.linear_velocity.length()) else "ENTER START CIRCLE / FACE ROUTE"]
		"countdown":message="%s\nSTART IN %d"%[race_title,maxi(1,ceili(countdown))]
		"running":message="%s / %.2fs\nLAP %d/%d · NEXT %s · Pause to quit"%[race_title,elapsed,lap,int(definition.get("laps",1)),"FINISH" if next_checkpoint==0 or (definition.mode=="sprint" and next_checkpoint==checkpoints.size()-1) else "CHECKPOINT %d"%next_checkpoint]
	status_strip.set_status(state,nearby,message)
func _draw() -> void:
	if not available:return
	draw_set_transform(start_m*PPM)
	StartArea.draw_zone(self,float(definition.get("start_radius",8)))
	draw_set_transform(Vector2.ZERO)
	if state!="running":return
	var gate: Vector2=checkpoints[next_checkpoint]*PPM
	var radius:=float(definition.get("checkpoint_radius",16))*PPM
	draw_arc(gate,radius,0,TAU,64,Color("#ffcf76"),5,true)
	draw_circle(gate,10,Color("#ffcf76"))
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F and can_stage():
		if start_race():get_viewport().set_input_as_handled()
