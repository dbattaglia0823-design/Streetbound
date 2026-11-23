extends Node2D
## Screen-independent, world-space crash sparks, small debris and impact dust.
## No effect is emitted below 15 mph or for a light sliding contact. The
## vehicle controller owns collision physics; this node only draws feedback.
const MIN_TRAVEL_SPEED_MPS := 6.7 # Approximately 15 mph.
const MIN_CLOSING_SPEED_MPS := 2.2
const MIN_SCRAPE_SPEED_MPS := 11.0
const IMPACT_COOLDOWN_SECONDS := 0.20
const MAX_PARTICLES := 160
const MAX_FLASHES := 5
const PPM := 20.0

var vehicle: VehicleController2D
var particles: Array[Dictionary] = []
var flashes: Array[Dictionary] = []
var emitted_bursts := 0
var _cooldown := 0.0
var _last_vehicle_position := Vector2.ZERO
var _rng := RandomNumberGenerator.new()

## Pure calculation for the speed gate and scalable effect budgets.
static func impact_profile(travel_speed_mps: float, closing_speed_mps: float) -> Dictionary:
	if not is_finite(travel_speed_mps) or not is_finite(closing_speed_mps) or \
			travel_speed_mps < MIN_TRAVEL_SPEED_MPS or closing_speed_mps < 0.35:
		return {}
	# A fast shallow contact against guardrails creates small sparks without
	# pretending that it broke glass or caused a frontal collision.
	if closing_speed_mps < MIN_CLOSING_SPEED_MPS:
		if travel_speed_mps < MIN_SCRAPE_SPEED_MPS:
			return {}
		return {"energy":0.12,"sparks":5,"debris":0,"dust":0,
			"glass":0,"plastic":0,"flash_radius":5.0,"scrape":true}
	var travel_weight := smoothstep(MIN_TRAVEL_SPEED_MPS, 32.0, travel_speed_mps)
	var hit_weight := smoothstep(MIN_CLOSING_SPEED_MPS, 19.0, closing_speed_mps)
	var energy := clampf(travel_weight * 0.48 + hit_weight * 0.52, 0.0, 1.0)
	return {
		"energy": energy,
		"sparks": mini(36, roundi(3.0 + energy * 33.0)),
		"debris": mini(14, roundi(1.0 + energy * 13.0)),
		"dust": mini(8, roundi(1.0 + energy * 7.0)),
		"glass": clampi(roundi((energy-.45)*9.0),0,6) if closing_speed_mps > 11.0 else 0,
		"plastic": clampi(roundi((energy-.3)*8.0),0,6) if closing_speed_mps > 8.0 else 0,
		"flash_radius": 9.0 + 27.0 * energy,
		"scrape":false
	}

func _ready() -> void:
	vehicle = get_parent() as VehicleController2D
	# Keep particles at the point of impact as the car drives away. Top-level
	# coordinates share the world camera but no longer inherit car rotation.
	top_level = true
	position = Vector2.ZERO
	z_index = 12
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.seed = 40517
	if is_instance_valid(vehicle):
		_last_vehicle_position = vehicle.global_position
		vehicle.crash_contact.connect(_on_crash_contact)
		vehicle.vehicle_reset.connect(clear_effects)
	set_process(false)

func clear_effects() -> void:
	particles.clear()
	flashes.clear()
	_cooldown = 0.0
	if is_instance_valid(vehicle):
		_last_vehicle_position = vehicle.global_position
	set_process(false)
	queue_redraw()

func _on_crash_contact(closing_speed_mps: float, contact_point: Vector2,
		normal: Vector2, pre_impact_velocity_mps: Vector2) -> void:
	var profile: Dictionary = impact_profile(pre_impact_velocity_mps.length(), closing_speed_mps)
	if profile.is_empty() or _cooldown > 0.0 or not contact_point.is_finite():
		return
	var away: Vector2 = normal.normalized()
	if away.length_squared() < 0.01:
		away = Vector2.UP
	var energy: float = float(profile.energy)
	_cooldown = 0.10 if bool(profile.get("scrape",false)) else IMPACT_COOLDOWN_SECONDS
	emitted_bursts += 1
	# Render a brief contact flash, a little grey body/dust debris, followed
	# by high-velocity gold/white sparks spreading away from the struck wall.
	flashes.append({"point":contact_point,"age":0.0,
		"life":0.075 + 0.09 * energy,"radius":float(profile.flash_radius),
		"energy":energy})
	while flashes.size() > MAX_FLASHES:
		flashes.remove_at(0)
	for i in int(profile.dust):
		_add_particle("dust",contact_point,away,pre_impact_velocity_mps,energy)
	for i in int(profile.debris):
		_add_particle("debris",contact_point,away,pre_impact_velocity_mps,energy)
	for i in int(profile.glass):
		_add_particle("glass",contact_point,away,pre_impact_velocity_mps,energy)
	for i in int(profile.plastic):
		_add_particle("plastic",contact_point,away,pre_impact_velocity_mps,energy)
	for i in int(profile.sparks):
		_add_particle("spark",contact_point,away,pre_impact_velocity_mps,energy)
	while particles.size() > MAX_PARTICLES:
		particles.remove_at(0)
	set_process(true)
	queue_redraw()

func _add_particle(kind: String,point: Vector2,normal: Vector2,
		pre_velocity_mps: Vector2,energy: float) -> void:
	var spread := _rng.randf_range(-1.45,1.45)
	var vector: Vector2 = normal.rotated(spread)
	var momentum := pre_velocity_mps * PPM
	var speed := 0.0
	var life := 0.4
	var width := 2.0
	var tint := Color(1.0,0.65,0.22)
	if kind == "spark":
		speed = _rng.randf_range(110.0,260.0) * (0.6 + energy * 1.1)
		life = _rng.randf_range(0.13,0.32) * (0.75 + energy * 0.45)
		width = _rng.randf_range(1.0,2.4)
		tint = Color(1.0,_rng.randf_range(0.62,0.93),_rng.randf_range(0.20,0.51))
	elif kind == "glass":
		speed = _rng.randf_range(60.0,155.0) * (0.6 + energy)
		life = _rng.randf_range(.32,.70)
		width = _rng.randf_range(1.4,2.9)
		tint = Color(.64,.88,.96)
	elif kind == "plastic":
		speed = _rng.randf_range(28.0,105.0) * (0.6 + energy)
		life = _rng.randf_range(.30,.60)
		width = _rng.randf_range(2.0,3.6)
		tint = Color(.23,.29,.33)
	elif kind == "debris":
		speed = _rng.randf_range(35.0,115.0) * (0.7 + energy)
		life = _rng.randf_range(0.3,0.72)
		width = _rng.randf_range(2.0,4.1)
		tint = Color(_rng.randf_range(.52,.78),_rng.randf_range(.54,.79),_rng.randf_range(.56,.80))
	else:
		speed = _rng.randf_range(15.0,48.0) * (0.6 + energy)
		life = _rng.randf_range(0.4,0.88)
		width = _rng.randf_range(5.0,10.0)
		tint = Color(.59,.60,.58)
	particles.append({
		"kind":kind,
		"point":point + Vector2(_rng.randf_range(-3.0,3.0),_rng.randf_range(-3.0,3.0)),
		"velocity":vector * speed + momentum * (0.06 if kind == "spark" else 0.10),
		"age":0.0,"life":life,"width":width,"tint":tint
	})

func _process(delta: float) -> void:
	var dt := minf(delta,0.05)
	if dt <= 0.0:
		return
	if not is_instance_valid(vehicle):
		clear_effects()
		return
	if vehicle.global_position.distance_to(_last_vehicle_position) > 550.0:
		# Map changes and garage resets must not strand effects at an old spawn.
		clear_effects()
		return
	_last_vehicle_position = vehicle.global_position
	_cooldown = maxf(0.0,_cooldown-dt)
	for i in range(particles.size()-1,-1,-1):
		var item: Dictionary = particles[i]
		item["age"] = float(item["age"]) + dt
		if float(item["age"]) >= float(item["life"]):
			particles.remove_at(i)
			continue
		item["point"] = Vector2(item["point"]) + Vector2(item["velocity"]) * dt
		var friction: float = 2.0 if str(item["kind"]) == "spark" else 4.0
		item["velocity"] = Vector2(item["velocity"]) * exp(-friction*dt)
		particles[i] = item
	for i in range(flashes.size()-1,-1,-1):
		var flash: Dictionary = flashes[i]
		flash["age"] = float(flash["age"]) + dt
		if float(flash["age"]) >= float(flash["life"]):
			flashes.remove_at(i)
		else:
			flashes[i] = flash
	if particles.is_empty() and flashes.is_empty() and _cooldown <= 0.0:
		set_process(false)
	queue_redraw()

func _draw() -> void:
	for flash in flashes:
		var t: float = float(flash["age"])/float(flash["life"])
		var point: Vector2 = flash["point"]
		var radius: float = float(flash["radius"]) * (0.55 + t * 0.9)
		var alpha: float = (1.0-t) * (0.16 + float(flash["energy"]) * 0.26)
		draw_circle(point,radius,Color(1.0,0.60,0.18,alpha))
		draw_circle(point,radius*.35,Color(1.0,0.95,0.76,alpha*.8))
	for item in particles:
		if str(item["kind"]) != "dust":continue
		var t: float = float(item["age"])/float(item["life"])
		var tint: Color = item["tint"]
		tint.a = (1.0-t)*(1.0-t)*0.2
		draw_circle(Vector2(item["point"]),float(item["width"])*(1.0+t*1.8),tint)
	for item in particles:
		if str(item["kind"]) not in ["debris","glass","plastic"]:continue
		var t: float = float(item["age"])/float(item["life"])
		var velocity: Vector2 = item["velocity"]
		var direction := velocity.normalized() if velocity.length_squared() > 0.001 else Vector2.UP
		var tint: Color = item["tint"]
		tint.a = 1.0-t
		var point: Vector2 = item["point"]
		draw_line(point-direction*float(item["width"]),point+direction*float(item["width"]),
			tint,maxf(1.0,float(item["width"])*.72),true)
	for item in particles:
		if str(item["kind"]) != "spark":continue
		var t: float = float(item["age"])/float(item["life"])
		var velocity: Vector2 = item["velocity"]
		var direction := velocity.normalized() if velocity.length_squared() > 0.001 else Vector2.UP
		var point: Vector2 = item["point"]
		var length := (6.0 + velocity.length() * .045) * (1.0-t*.65)
		var width: float = float(item["width"])
		var color: Color = item["tint"]
		color.a = (1.0-t)*(1.0-t)
		draw_line(point-direction*length,point+direction*length*.15,
			Color(1.0,.42,.09,color.a*.18),width*3.2,true)
		draw_line(point-direction*length,point+direction*length*.15,color,width,true)
		draw_circle(point,maxf(.8,width*.53),Color(1.0,.97,.78,color.a))
