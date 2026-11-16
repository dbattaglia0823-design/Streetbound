extends RefCounted
## Shared metre-space start-grid format used by the editor, bake and race game.
const PPM:=20.0
const MAX_RIVALS:=6
const ROW_M:=8.0
const SIDE_M:=4.5
const MIN_GAP_M:=0.6
const CAR_SIZE_M:=Vector2(2.2,4.6)
const FORMATIONS:=["single_file","side_by_side","staggered"]
const StartArea=preload("res://scripts/world/race_start_area.gd")

static func route_heading(points: Array) -> Vector2:
	if points.size()<2:return Vector2.UP
	var a:=Vector2(float(points[0].get("x",0)),float(points[0].get("y",0)))
	var b:=Vector2(float(points[1].get("x",0)),float(points[1].get("y",0)))
	return (b-a).normalized() if a.distance_to(b)>.01 else Vector2.UP

static func pose(position_m: Vector2,forward: Vector2) -> Dictionary:
	return {"x":position_m.x,"y":position_m.y,"rotation":rad_to_deg(forward.angle()+PI*.5)}

static func point(value: Dictionary) -> Vector2:
	return Vector2(float(value.get("x",0)),float(value.get("y",0)))

static func angle(value: Dictionary) -> float:
	return deg_to_rad(float(value.get("rotation",0.0)))

static func default_player(points: Array) -> Dictionary:
	return pose(point(points[0]),route_heading(points))

static func default_enemy(player: Dictionary,index: int,formation: String) -> Dictionary:
	var forward:=Vector2.UP.rotated(angle(player))
	var right:=forward.orthogonal()
	var position_m:=point(player)
	match formation:
		"side_by_side":
			# First rival is alongside, additional pairs occupy distinct rows.
			var row:=index/2
			position_m+=right*(SIDE_M if index%2==0 else -SIDE_M)
			position_m-=forward*(ROW_M*float(row))
		"staggered":
			var row:=index/2
			position_m+=right*(SIDE_M if index%2==0 else -SIDE_M)
			position_m-=forward*(ROW_M*float(row+1))
		_:
			position_m-=forward*ROW_M*float(index+1)
	return pose(position_m,forward)

static func layout(points: Array,count: int,formation: String,previous: Dictionary={}) -> Dictionary:
	var player: Dictionary=previous.get("player_start",{})
	if player.is_empty():player=default_player(points)
	else:player=player.duplicate(true)
	var enemies: Array=[]
	var old_enemies: Array=previous.get("enemy_starts",[])
	var keep: bool=formation==str(previous.get("formation","single_file"))
	for i in clampi(count,0,MAX_RIVALS):
		enemies.append(old_enemies[i].duplicate(true) if keep and i<old_enemies.size() else default_enemy(player,i,formation))
	return {"player_start":player,"enemy_starts":enemies,"formation":formation}

static func valid_pose(value: Variant,width: float,height: float) -> bool:
	if not value is Dictionary:return false
	for key in ["x","y","rotation"]:
		if not value.has(key) or typeof(value[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value[key])):return false
	return point(value).x>=0 and point(value).y>=0 and point(value).x<=width and point(value).y<=height and absf(float(value.rotation))<=360.0

## SAT test of two vehicle footprints (includes a wall-to-wall gap).
static func separated(a: Dictionary,b: Dictionary) -> bool:
	var pa:=point(a);var pb:=point(b)
	var axis_a:=Vector2.RIGHT.rotated(angle(a));var axis_b:=Vector2.RIGHT.rotated(angle(b))
	var axes: Array[Vector2]=[axis_a,axis_a.orthogonal(),axis_b,axis_b.orthogonal()]
	for axis in axes:
		var half_a:=absf(axis.dot(axis_a))*CAR_SIZE_M.x*.5+absf(axis.dot(axis_a.orthogonal()))*CAR_SIZE_M.y*.5
		var half_b:=absf(axis.dot(axis_b))*CAR_SIZE_M.x*.5+absf(axis.dot(axis_b.orthogonal()))*CAR_SIZE_M.y*.5
		if absf((pb-pa).dot(axis))>=half_a+half_b+MIN_GAP_M:return true
	return false

static func valid_grid(race: Dictionary,width: float,height: float) -> bool:
	var player: Variant=race.get("player_start",{})
	var enemies: Variant=race.get("enemy_starts",[])
	if not enemies is Array or enemies.size()>MAX_RIVALS:return false
	if race.get("formation","single_file") not in FORMATIONS:return false
	# Old saved time trials have neither field, and remain backward compatible.
	if player is Dictionary and player.is_empty() and enemies.is_empty():return true
	if not valid_pose(player,width,height):return false
	var placed: Array[Dictionary]=[player]
	for enemy in enemies:
		if not valid_pose(enemy,width,height):return false
		for earlier in placed:
			if not separated(earlier,enemy):return false
		placed.append(enemy)
	return true

static func player_slot(race: Dictionary) -> Dictionary:
	var current: Dictionary=race.get("player_start",{})
	return current if not current.is_empty() else default_player(race.points)

static func teleport(car: VehicleController2D,slot: Dictionary) -> void:
	StartArea.settle_for_countdown(car)
	car.command=Vector4.ZERO
	car.steering=0.0
	car.wheel_spin=0.0
	car.handbrake=0.0
	car.handbrake_grip_loss=0.0
	car.nitrous_requested=false
	car.nitrous_active=false
	car.global_position=point(slot)*PPM
	car.global_rotation=angle(slot)
	car.reset_physics_interpolation()
