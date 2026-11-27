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
const Grid=preload("res://scripts/world/race_start_grid.gd")
const VehicleScene=preload("res://scenes/vehicle.tscn")
const RivalDriver=preload("res://scripts/world/race_ai_driver.gd")
const Catalog=preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const OwnershipModel=preload("res://scripts/vehicle/vehicle_ownership.gd")
const EventRules=preload("res://scripts/world/authored_event_rules.gd")
var definition: Dictionary={}
var world: Node2D
var player: VehicleController2D
var economy: OwnershipModel
var world_id: String="morrow-coast"
var _run_id:=""
var police: Node2D
var awaiting_escape:=false
var escape_remaining:=0.0
var staged_car_id:=""
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
var _grid_start_m:=Vector2.ZERO
var rivals: Array[VehicleController2D]=[]
var rival_drivers: Array[Node]=[]
var rival_progress: Array[Dictionary]=[]
func _ready() -> void:
	if not is_instance_valid(world) or not is_instance_valid(player):return
	if not Definition.valid(definition,float(world.data.size[0]),float(world.data.size[1])):return
	name=str(definition.id);race_title=str(definition.name)
	world_id=str(world.data.get("editor_world_id","morrow-coast"))
	start_radius_m=float(definition.get("start_radius",8))
	var kind: String=str(definition.get("race_kind","circuit" if definition.mode=="circuit" else ("time_trial" if definition.get("enemy_starts",[]).is_empty() else "point_to_point")))
	var type_label: String=str({"circuit":"Circuit","point_to_point":"Point to Point","time_trial":"Time Trial"}.get(kind,"Street Race"))
	if int(definition.get("race_heat",0))>0:type_label="Underground "+type_label
	race_type=type_label+(" · SOLO" if definition.get("enemy_starts",[]).is_empty() else " · %d AI Rivals"%definition.enemy_starts.size())
	for p in definition.points:checkpoints.append(Vector2(p.x,p.y))
	start_m=checkpoints[0];finish_m=start_m if definition.mode=="circuit" else checkpoints[-1]
	heading=(checkpoints[1]-start_m).normalized()
	_grid_start_m=Grid.point(Grid.player_slot(definition))
	navigation=Navigation.new();navigation.setup(checkpoints,definition.mode=="circuit")
	world_guidance=Guidance.new();add_child(world_guidance)
	var layer:=CanvasLayer.new();layer.layer=7;add_child(layer)
	status_strip=Status.new();layer.add_child(status_strip)
	status_strip.call("configure_event",self,{
		"title":race_title,"type":race_type,"format":"Time Trial" if definition.get("enemy_starts",[]).is_empty() else "Grid Race",
		"distance_m":float(navigation.get("length_m"))*float(definition.get("laps",1)),
		"route":navigation.get("points_m"),"closed":definition.mode=="circuit",
		"lap":definition.mode=="circuit",
		"entry":"FREE" if int(definition.get("entry_fee",0))==0 else OwnershipModel.dollars(int(definition.entry_fee)),"rewards":_reward_summary(),
		"description":"Finish every checkpoint in order. Win against the AI to claim rewards." if not definition.get("enemy_starts",[]).is_empty() else "Complete the mapped checkpoints to claim time trial rewards."
	})
	player.vehicle_reset.connect(_on_vehicle_reset)
	available=true;z_index=6;add_to_group("streetbound_race");_refresh();queue_redraw()
func _exit_tree() -> void:
	if is_instance_valid(player) and state in ["countdown","running"]:player.remove_from_group("race_participant")
	_clear_rivals()
func _lock_reason() -> String:
	if int(definition.get("race_heat",0))>0 and not is_instance_valid(police):return "SINGLE-PLAYER UNDERGROUND CAREER ONLY"
	if int(definition.get("entry_fee",0))>0 and (not is_instance_valid(economy) or economy.balance<int(definition.entry_fee)):return "ENTRY FEE "+OwnershipModel.dollars(int(definition.entry_fee))
	return EventRules.lock_reason(definition,economy,world_id)

func can_stage() -> bool:
	return available and state=="idle" and _lock_reason().is_empty() and not StartArea.busy(self) and is_instance_valid(player) and player.global_position.distance_to(start_m*PPM)<=float(definition.get("start_radius",8))*PPM and StartArea.can_stage_at_speed(player.linear_velocity.length()) and Vector2.UP.rotated(player.rotation).dot(heading)>=.35
func start_race() -> bool:
	if not can_stage() or get_tree().paused:return false
	_prepare_guidance()
	if not _spawn_rivals():return false
	if int(definition.get("entry_fee",0))>0 and not economy.pay_race_entry(definition):
		_clear_rivals();return false
	awaiting_escape=false;escape_remaining=0.0
	staged_car_id=str(economy.active_id) if is_instance_valid(economy) else ""
	Grid.teleport(player,Grid.player_slot(definition))
	_grid_start_m=player.global_position/PPM
	_run_id="authored-%s-%s-%d"%[str(definition.id),str(economy.active_id) if is_instance_valid(economy) else "guest",Time.get_ticks_usec()]
	state="countdown";countdown=3;elapsed=0;next_checkpoint=1;lap=1;result="";_gate_armed=true
	_previous_m=player.global_position/PPM;player.add_to_group("race_participant");_refresh();return true

func _spawn_rivals() -> bool:
	_clear_rivals()
	if definition.get("enemy_starts",[]).is_empty():return true
	# Shuffle once per race; cycle only when more rivals than catalog choices.
	var pool: Array=definition.get("opponent_pool",[]).duplicate()
	pool.shuffle()
	for i in definition.enemy_starts.size():
		var enemy: VehicleController2D=VehicleScene.instantiate() as VehicleController2D
		if enemy==null:
			_clear_rivals()
			return false
		enemy.name="MapRaceAI%d"%(i+1)
		enemy.external_input=true
		enemy.surface_provider=world
		enemy.config=player.config.duplicate(true)
		enemy.collision_layer=1
		enemy.collision_mask=3
		enemy.z_index=8
		enemy.add_to_group("race_opponent")
		enemy.add_to_group("race_participant")
		add_child(enemy)
		var catalog_vehicle: Dictionary=Catalog.find_by_id(str(pool[i%pool.size()])) if not pool.is_empty() else {}
		if not catalog_vehicle.is_empty():
			# Match the chosen catalog model's actual physics, visual, and collision size.
			if not Catalog.select(enemy,catalog_vehicle):
				_clear_rivals()
				enemy.queue_free()
				return false
		else:
			# Unconfigured legacy races still clone the player's vehicle.
			var player_wheels:=player.get_node_or_null("Art/Wheels")
			var enemy_wheels:=enemy.get_node_or_null("Art/Wheels")
			if player_wheels!=null and enemy_wheels!=null:
				var appearance: Resource=player_wheels.get("appearance") as Resource
				if appearance!=null:enemy_wheels.call("apply_appearance",appearance.duplicate(true))
			var source_shape:=player.get_node_or_null("CollisionShape2D") as CollisionShape2D
			var target_shape:=enemy.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if source_shape!=null and target_shape!=null and source_shape.shape!=null:
				target_shape.shape=source_shape.shape.duplicate(true)
			var sprite:=enemy.get_node_or_null("Art/Sprite") as Sprite2D
			if sprite!=null:sprite.modulate=Color.from_hsv(fmod(0.6+float(i)*.17,1.0),.34,1.0)
		Grid.teleport(enemy,definition.enemy_starts[i])
		var driver:=Node.new()
		driver.name="MapRaceAIDriver%d"%(i+1)
		driver.set_script(RivalDriver)
		add_child(driver)
		driver.call("setup_navigation",enemy,navigation)
		# Difficulty alters legal AI input and reaction, never physics,
		# grip, engine power or vehicle speed beyond the same car stats.
		var difficulty: String=str(definition.get("difficulty","amateur"))
		var profile: Dictionary={
			"rookie":{"reaction":.95,"throttle":.78},
			"amateur":{"reaction":.55,"throttle":.87},
			"pro":{"reaction":.35,"throttle":.94},
			"elite":{"reaction":.20,"throttle":1.0}
		}.get(difficulty,{"reaction":.55,"throttle":.87})
		driver.set("reaction_seconds",float(profile.reaction)+float(i)*.1)
		driver.set("throttle_limit",float(profile.throttle))
		rivals.append(enemy)
		rival_drivers.append(driver)
		rival_progress.append({"next":1,"lap":1,"armed":true,
			"previous":enemy.global_position/Grid.PPM,"finished":-1.0})
	return true

func _clear_rivals() -> void:
	for driver in rival_drivers:
		if is_instance_valid(driver):
			driver.call("stop")
			driver.queue_free()
	for rival in rivals:
		if is_instance_valid(rival):
			rival.collision_layer=0;rival.collision_mask=0
			rival.hide()
			rival.queue_free()
	rivals.clear();rival_drivers.clear();rival_progress.clear()

func _update_rivals() -> void:
	for i in rivals.size():
		var car: VehicleController2D=rivals[i]
		if not is_instance_valid(car):continue
		var progress: Dictionary=rival_progress[i]
		if float(progress.finished)>=0:continue
		var at:=car.global_position/Grid.PPM
		var previous: Vector2=progress.previous
		var step:=at.distance_to(previous)
		var radius:=float(definition.get("checkpoint_radius",16.0))
		var plausible:=step<=maxf(5.0,car.linear_velocity.length()*.11+4.0)
		var index:=int(progress.next)
		var gate: Vector2=checkpoints[index]
		if at.distance_to(gate)>radius:progress.armed=true
		if bool(progress.armed) and plausible and Geometry2D.get_closest_point_to_segment(gate,previous,at).distance_to(gate)<=radius:
			if index==0 or (definition.mode=="sprint" and index==checkpoints.size()-1):
				if definition.mode=="circuit" and int(progress.lap)<int(definition.get("laps",1)):
					progress.lap=int(progress.lap)+1;progress.next=1
				else:
					progress.finished=elapsed
					if i<rival_drivers.size() and is_instance_valid(rival_drivers[i]):rival_drivers[i].call("stop")
			else:progress.next=(index+1)%checkpoints.size()
			progress.armed=false
		progress.previous=at

func _on_vehicle_reset() -> void:
	if state in ["countdown","running"]:quit_race()

func manages_race_heat() -> bool:
	return true

func _reward_summary() -> String:
	var parts: Array[String]=[]
	if int(definition.get("race_heat",0))>0:parts.append("WANTED %d / ESCAPE TO COLLECT"%int(definition.race_heat))
	parts.append("+%d STREET REP"%maxi(5,int(definition.get("underground_rep_reward",0))))
	if int(definition.get("reward_cash",0))>0:
		parts.append(OwnershipModel.dollars(int(definition.reward_cash)))
	if int(definition.get("reward_player_xp",0))>0:
		parts.append("%d DRIVER XP"%int(definition.reward_player_xp))
	if int(definition.get("reward_car_xp",0))>0:
		parts.append("%d CAR XP"%int(definition.reward_car_xp))
	if int(definition.get("first_win_reward_cash",0))>0 or int(definition.get("first_win_reward_player_xp",0))>0 or int(definition.get("first_win_reward_car_xp",0))>0:
		parts.append("FIRST WIN BONUS")
	return " / ".join(parts) if not parts.is_empty() else "PRACTICE"

func _award_finish() -> String:
	if not is_instance_valid(economy):return "REWARDS UNAVAILABLE"
	var awarded: Dictionary=economy.record_authored_race(_run_id,elapsed,definition,
		EventRules.event_key(world_id,str(definition.id)),int(definition.get("race_heat",0))==0 or (is_instance_valid(police) and int(police.get("wanted_level"))==0 and float(police.get("bust_timer"))<=0.0))
	if str(awarded.get("result",""))!="completed":
		return "REWARDS NOT SAVED: "+str(awarded.get("result","unknown"))
	var prefix: String="FIRST WIN  " if bool(awarded.get("first_win",false)) else "REWARDS  "
	var result_text := prefix+OwnershipModel.dollars(int(awarded.get("cash",0)))+" / %d DRIVER XP / %d CAR XP"%[
		int(awarded.get("player_xp",0)),int(awarded.get("car_xp",0))]+(" / +%d STREET REP"%int(awarded.get("underground_rep",0)) if int(awarded.get("underground_rep",0))>0 else "")
	if not str(awarded.get("rank_up","")).is_empty():
		result_text += "\n"+str(awarded["rank_up"])
	return result_text

func _won_course() -> bool:
	for progress in rival_progress:
		if float(progress.finished)>=0 and float(progress.finished)<=elapsed:return false
	return true

func _complete_course() -> void:
	if int(definition.get("race_heat",0))>0 and _won_course() and is_instance_valid(police) and int(police.get("wanted_level"))>0:
		awaiting_escape=true
		escape_remaining=float(definition.get("escape_time_limit",90))
		_clear_rivals()
		world_guidance.set_guidance(navigation,player,false)
		return
	_finish(_finish_message())

func _finish_message() -> String:
	if rivals.is_empty():
		return "%s / %.2f SECONDS\nTIME TRIAL COMPLETE / %s"%[race_title,elapsed,_award_finish()]
	var fastest:=INF
	for progress in rival_progress:
		if float(progress.finished)>=0:fastest=minf(fastest,float(progress.finished))
	if fastest<=elapsed:
		return "RIVAL WINS / %.2fs  ·  YOU %.2fs\nGRID PRACTICE / NO REWARDS"%[fastest,elapsed]
	return "YOU WIN / %.2fs  ·  RIVALS %s\n%s"%[elapsed,"DNF" if fastest==INF else "%.2fs"%fastest,_award_finish()]

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
	state="idle";elapsed=0;countdown=0;result="";awaiting_escape=false
	_clear_rivals()
	player.remove_from_group("race_participant")
	world_guidance.set_guidance(navigation,player,false)
	_refresh();queue_redraw();return true
func _finish(message: String) -> void:
	state="results";result=message;status_timer=8;awaiting_escape=false
	for driver in rival_drivers:
		if is_instance_valid(driver):driver.call("stop")
	player.remove_from_group("race_participant")
	world_guidance.set_guidance(navigation,player,false);queue_redraw()
func _physics_process(dt: float) -> void:
	if not available or not is_instance_valid(player) or dt<=0:return
	var at:=player.global_position/PPM
	if state in ["countdown","running"] and is_instance_valid(police):
		if float(police.get("bust_timer"))>0.0 or player.damage_drive_fraction<=0.0 or player.fuel_drive_fraction<=0.0 or (is_instance_valid(economy) and str(economy.active_id)!=staged_car_id):
			_finish("RUN FAILED / VEHICLE DISABLED, CHANGED OR BUSTED")
			return
	if awaiting_escape:
		escape_remaining-=dt
		if not is_instance_valid(police) or escape_remaining<=0.0:
			_finish("ESCAPE FAILED / NO REWARD")
		elif int(police.get("wanted_level"))==0:
			_finish("ESCAPE COMPLETE / "+_award_finish())
		_refresh()
		return
	if state=="countdown":
		if at.distance_to(_grid_start_m)>maxf(10.0,float(definition.get("start_radius",8))+3) or player.linear_velocity.length()>4:
			_finish("FALSE START / RETURN TO GRID")
		else:
			countdown-=dt
			if countdown<=0:
				if int(definition.get("race_heat",0))>0 and (not is_instance_valid(police) or not bool(police.call("start_pursuit",int(definition.race_heat)))):
					_finish("DISPATCH UNAVAILABLE / RUN FAILED");return
				state="running";_previous_m=at
				for driver in rival_drivers:
					if is_instance_valid(driver):driver.call("launch")
	elif state=="running":
		elapsed+=dt
		_update_rivals()
		var gate: Vector2=checkpoints[next_checkpoint]
		var radius:=float(definition.get("checkpoint_radius",16))
		var step:=at.distance_to(_previous_m)
		if step>maxf(5,player.linear_velocity.length()*dt*2+3):_gate_armed=false
		if at.distance_to(gate)>radius:_gate_armed=true
		if _gate_armed and step<=maxf(5,player.linear_velocity.length()*dt*2+3) and Geometry2D.get_closest_point_to_segment(gate,_previous_m,at).distance_to(gate)<=radius:
			if next_checkpoint==0 or (definition.mode=="sprint" and next_checkpoint==checkpoints.size()-1):
				if definition.mode=="circuit" and lap<int(definition.get("laps",1)):lap+=1;next_checkpoint=1
				else:_complete_course()
			else:next_checkpoint=(next_checkpoint+1)%checkpoints.size()
			_gate_armed=true;queue_redraw()
		_previous_m=at
		var limit:=float(definition.get("time_limit",0))
		if state=="running" and not awaiting_escape and limit>0 and elapsed>limit:_finish("TIME LIMIT REACHED")
	elif state=="results":
		status_timer-=dt
		if status_timer<=0:
			_clear_rivals()
			state="idle";result=""
	world_guidance.set_guidance(navigation,player,state in ["countdown","running"] and not awaiting_escape)
	_draw_clock+=dt
	if _draw_clock>=.1:_draw_clock=0;_refresh();queue_redraw()
func _refresh() -> void:
	if not is_instance_valid(status_strip):return
	var nearby: bool=player.global_position.distance_to(start_m*PPM)<30*PPM and StartArea.can_stage_at_speed(player.linear_velocity.length())
	var message:=result
	var restriction: String=_lock_reason()
	if awaiting_escape:
		status_strip.set_status("running",false,"%s / FINISH COMPLETE\nLOSE POLICE / %ds / REWARDS PENDING"%[race_title,ceili(escape_remaining)])
		return
	match state:
		"idle":message="%s / %s\n%s"%[race_title,race_type,"LOCKED: "+restriction if not restriction.is_empty() else "[ F ] START" if can_stage() else "SLOW TO 15 MPH / FACE ROUTE" if not StartArea.can_stage_at_speed(player.linear_velocity.length()) else "ENTER START CIRCLE / FACE ROUTE"]
		"countdown":message="%s\nSTART IN %d"%[race_title,maxi(1,ceili(countdown))]
		"running":message="%s / %.2fs\nLAP %d/%d · NEXT %s · %d AI · Pause to quit"%[race_title,elapsed,lap,int(definition.get("laps",1)),"FINISH" if next_checkpoint==0 or (definition.mode=="sprint" and next_checkpoint==checkpoints.size()-1) else "CHECKPOINT %d"%next_checkpoint,rivals.size()]
	status_strip.set_status(state,nearby,message)
func _draw() -> void:
	if not available:return
	draw_set_transform(start_m*PPM)
	StartArea.draw_zone(self,float(definition.get("start_radius",8)))
	draw_set_transform(Vector2.ZERO)
	if state!="running" or awaiting_escape:return
	var gate: Vector2=checkpoints[next_checkpoint]*PPM
	var radius:=float(definition.get("checkpoint_radius",16))*PPM
	draw_arc(gate,radius,0,TAU,64,Color("#ffcf76"),5,true)
	draw_circle(gate,10,Color("#ffcf76"))
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not event.is_echo() and can_stage():
		if start_race():get_viewport().set_input_as_handled()
