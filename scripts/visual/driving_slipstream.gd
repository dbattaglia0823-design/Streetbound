extends Node2D
## Lightweight slipstream lines only around a real drafting pair. All lines
## are locally drawn: no shaders, materials, particles, physics or persistent
## world trails. Traffic and remote players use exactly the same visual rule.
const Drafting = preload("res://scripts/vehicle/drafting_aerodynamics.gd")
const WAKE_LINES := 7
var vehicle: Node2D
var wake_intensity := 0.0
var following_intensity := 0.0
var _refresh_in := 0.0
var _measured_wake := 0.0

func _ready() -> void:
	vehicle = get_parent() as Node2D
	z_index = -1

func _process(delta: float) -> void:
	if not is_instance_valid(vehicle):
		return
	var dt := clampf(delta,0.0,.05)
	_refresh_in -= dt
	if _refresh_in <= 0.0:
		_refresh_in = Drafting.SAMPLE_SECONDS
		var world: Node = null
		var speed := 0.0
		var velocity := Vector2.ZERO
		if vehicle is VehicleController2D:
			var car := vehicle as VehicleController2D
			world = car.surface_provider
			velocity = car.linear_velocity
			speed = velocity.dot(Vector2.UP.rotated(car.rotation))
		elif vehicle.is_in_group("traffic_vehicle"):
			if vehicle.get_parent() != null:
				world = vehicle.get_parent().get_parent()
			speed = float(vehicle.get("motion_speed_mps"))
			velocity = Vector2.UP.rotated(vehicle.rotation)*speed
		_measured_wake = Drafting.wake_strength(vehicle,world,velocity) \
			if speed >= Drafting.START_SPEED_MPS else 0.0
	var following := 0.0
	if vehicle is VehicleController2D:
		following = (vehicle as VehicleController2D).draft_strength
	var target := _measured_wake
	var easing := 1.0-exp(-8.0*dt)
	var previous := wake_intensity
	wake_intensity = lerpf(wake_intensity,target,easing)
	following_intensity = lerpf(following_intensity,following,easing)
	if maxf(previous,wake_intensity)>0.015 or following_intensity>0.015:
		queue_redraw()

func _draw() -> void:
	# The leading car paints subtle flow lines behind its rear bumper,
	# while the follower sees shorter airflow streaks near its front fenders.
	if wake_intensity > .035:
		var alpha := minf(.40,wake_intensity*.31)
		for i in WAKE_LINES:
			var side := (float(i)-3.0)/3.0
			var start := Vector2(side*16.0,36.0)
			var dist := 160.0 + 260.0*wake_intensity
			var bending := side*(10.0+14.0*wake_intensity)
			var bend := Vector2(side*27.0+bending*.3,36.0+dist*.52)
			var end := Vector2(side*42.0+bending,36.0+dist)
			var tint := Color(.58,.83,1.0,alpha*(.56 if i%2==0 else .37))
			draw_polyline(PackedVector2Array([start,bend,end]),tint,
				1.3 if i%2==0 else .9,true)
	if following_intensity > .08:
		var alpha := minf(.32,following_intensity*.25)
		for side in [-1.0,1.0]:
			var start := Vector2(side*27.0,-29.0)
			var end := Vector2(side*38.0,27.0)
			draw_line(start,end,Color(.8,.95,1.0,alpha),1.8,true)
			draw_line(start+Vector2(side*5.0,4.0),end+Vector2(side*6.0,4.0),
				Color(.43,.75,.99,alpha*.54),1.0,true)
