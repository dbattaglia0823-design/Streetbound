extends SceneTree
const Fuel = preload("res://scripts/vehicle/vehicle_fuel.gd")
const Gauge = preload("res://scripts/ui/vehicle_resource_gauges.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(name: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		failures.append(name)

func run() -> void:
	var fuel := Fuel.new()
	fuel.configure("sport", 1450.0, 300.0, false)
	check("fuel_starts_full", is_equal_approx(fuel.fraction(), 1.0))
	check("no_negative_consumption", fuel.consume(-1.0, 30.0, 1.0) == 0.0)
	check("no_nan_consumption", fuel.consume(1.0, INF, 0.5) == 0.0)
	check("stationary_consumes_idle_fuel", fuel.consume(360.0, 0.0, 0.0) > 0.0)
	var before := fuel.remaining
	check("motion_consumes_fuel", fuel.consume(60.0, 30.0, 1.0) > 0.0 and fuel.remaining < before)
	var regular_rate := fuel.consume(30.0, 20.0, 0.2)
	fuel.refill()
	var aggressive_rate := fuel.consume(30.0, 20.0, 1.0)
	check("throttle_affects_consumption", aggressive_rate > regular_rate)
	check("refill_has_cost", fuel.refill_cost() > 0)
	fuel.remaining = 0.05
	fuel.consume(300.0, 100.0, 1.0)
	check("fuel_clamped_at_zero", fuel.remaining == 0.0 and fuel.empty())
	check("cannot_consume_more_than_remaining", fuel.consume(1.0, 100.0, 1.0) == 0.0)
	fuel.refill()
	check("refill_restores_tank", is_equal_approx(fuel.fraction(), 1.0))
	var ev := Fuel.new()
	ev.configure("sport", 1700.0, 280.0, true)
	check("electric_energy_supported", ev.electric and ev.capacity == 75.0)
	var gauge: Control = Gauge.new()
	root.add_child(gauge)
	await process_frame
	gauge.call("update_levels", 0.25, 0.6, false)
	check("gauge_engine_fraction", is_equal_approx(float(gauge.get("engine_fraction")), 0.25))
	check("gauge_fuel_fraction", is_equal_approx(float(gauge.get("fuel_fraction")), 0.6))
	check("gauge_has_size", gauge.size.x >= 130.0)
	gauge.queue_free()
	print("FUEL/RESOURCE HUD: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)
