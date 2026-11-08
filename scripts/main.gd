extends Node2D

@onready var world: GDTRacingWorld = $World
@onready var car: StreetboundCar = $Car
@onready var speed_label: Label = $HUD/Panel/VBox/SpeedLabel
@onready var help_label: Label = $HUD/Panel/VBox/HelpLabel

var _hud_elapsed: float = 0.0

func _ready() -> void:
    if not world.load_world("res://worlds/atlas-coast.world.json"):
        push_error("Atlas Coast world could not be loaded")
    var start := Vector2(3480.0,10400.0)
    var spawns: Array = world.get_markers("player_spawn")
    if not spawns.is_empty():
        var marker: Dictionary = spawns[0]
        start = Vector2(float(marker.get("x",3480)),float(marker.get("y",10400)))
    car.reset_vehicle(start)
    car.set_world_query(world)
    var camera: Camera2D = car.get_node("Camera2D")
    camera.limit_left = 0
    camera.limit_top = 0
    camera.limit_right = int(world.get_world_size().x)
    camera.limit_bottom = int(world.get_world_size().y)
    help_label.text = "W/Up accelerate | S/Down brake/reverse | A/D steer | Space drift | R reset | F3 markers"
    _update_hud()

func _physics_process(delta: float) -> void:
    _hud_elapsed += delta
    if _hud_elapsed >= 0.12:
        _hud_elapsed = 0.0
        _update_hud()

func _update_hud() -> void:
    var signed_speed: float = car.get_forward_speed_kph()
    var direction: String = "REV" if signed_speed < -1.0 else ("DRIVE" if signed_speed > 1.0 else "IDLE")
    speed_label.text = "%03d km/h | %s | %s | steering %.0f°" % [
        roundi(car.get_speed_kph()),direction,car.surface.to_upper(),rad_to_deg(car.steer_angle)
    ]

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if event.keycode == KEY_R:
        car.reset_to_spawn()
    elif event.keycode == KEY_F3:
        world.draw_markers = not world.draw_markers
        world.queue_redraw()
