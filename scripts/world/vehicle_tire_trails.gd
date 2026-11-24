extends RefCounted
## Shared per-car skid contact sampler. Worlds own one bounded Line2D pool,
## while each racing vehicle owns an independent pair of active track IDs.
const PPM := 20.0
const VIEW_DISTANCE_PX := 6000.0
const Weather = preload("res://scripts/world/weather_conditions.gd")

static func track_id(car: VehicleController2D, primary: VehicleController2D,
		rear_side: int) -> int:
	return rear_side if car == primary else car.get_instance_id() * 2 + rear_side

static func drift_strength(car: VehicleController2D) -> float:
	var slip := car.slip_angle
	if not car.is_physics_processing():
		# Remote friends are interpolated, not simulated locally.
		var forward := Vector2.UP.rotated(car.rotation)
		var right := Vector2.RIGHT.rotated(car.rotation)
		slip=atan2(car.linear_velocity.dot(right),
			maxf(absf(car.linear_velocity.dot(forward)),1.0))
	var slide := smoothstep(.08,.34,absf(slip))
	return maxf(slide,maxf(car.handbrake,
		maxf(car.handbrake_grip_loss,car.wheel_spin*1.8)))

static func sample(marks: TireMarks2D, car: VehicleController2D,
		primary: VehicleController2D, world: Node2D) -> void:
	if not is_instance_valid(car) or car.surface_provider != world:
		return
	var base := track_id(car,primary,0)
	if car.linear_velocity.length() < 3.0:
		marks.reset_tracks(base)
		marks.reset_tracks(base+1)
		return
	var strength := drift_strength(car)
	if strength < .13 and car.surface == "ASPHALT":
		marks.reset_tracks(base)
		marks.reset_tracks(base+1)
		return
	# Fixed visual wheel anchors retain silhouette alignment across the
	# game's vehicle roster and never inherit suspension animation.
	var rig: Node = car.get_node_or_null("Art/Wheels")
	for side in 2:
		var wheel := Vector2(-16.0 if side==0 else 16.0,25.0)
		if is_instance_valid(rig) and rig.has_method("wheel_anchor"):
			wheel=rig.wheel_anchor(2+side)
		var point: Vector2=car.global_position+wheel.rotated(car.rotation)
		var surface: Dictionary=world.surface_at(point)
		var material: String=str(surface.get("name","ASPHALT"))
		# Rain washes rubber contrast out without deleting existing trails.
		var visible_strength := strength * (1.0 - Weather.rain_at(world) * 0.55) \
			if material == "ASPHALT" else strength
		marks.add_mark(point,car.rotation,material=="ASPHALT",base+side,
			material,visible_strength)
