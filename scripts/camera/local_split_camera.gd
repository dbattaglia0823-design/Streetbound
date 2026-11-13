extends Camera2D
## Per-viewport camera for two local players in the SAME World2D. Input is
## deliberately handled by the split-screen manager, not by this camera.
var target: VehicleController2D
var max_follow_distance := 700.0
var follow_response := 6.0

func _ready() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	enabled = true
	if is_instance_valid(target):
		global_position = target.global_position
		make_current()

func _physics_process(dt: float) -> void:
	if not is_instance_valid(target):
		return
	var lead := target.linear_velocity * 3.0
	var desired := target.global_position + lead
	global_position = global_position.lerp(desired,1.0-exp(-follow_response*dt))
	var to_car := global_position-target.global_position
	if to_car.length()>max_follow_distance:
		global_position = target.global_position+to_car.limit_length(max_follow_distance)
