extends SceneTree
## Deterministic impairment profiles for the existing 30Hz snapshot buffer.
## These are SYNTHETIC arrival schedules, not measured WAN performance.
const Buffer = preload("res://scripts/network/remote_snapshot_buffer.gd")
const Session = preload("res://scripts/network/online_session.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		failures.append(label)

func _state(distance: float) -> Array:
	return [Vector2(distance, 0.0), 0.0, Vector2(180.0, 0.0),
		0.0, 180.0, 0.0]

func _simulate(rtt_ms: int, jitter_ms: int, drop_every: int) -> Dictionary:
	var packets: Array[Dictionary] = []
	var count := 0
	for sequence in 75:
		var sent_at := sequence * 33
		if sequence > 0 and sequence % drop_every == 0:
			continue
		var jitter: int = (sequence % 5 - 2) * jitter_ms / 2
		packets.append({
			"arrival": sent_at + rtt_ms / 2 + jitter,
			"sequence": sequence,
			"state": _state(float(sent_at) * 0.18)})
	var history: Array = []
	var last_sequence := -1
	var samples := 0
	var highest_history := 0
	var bounded := true
	for now_ms in range(0, 3100, 16):
		for packet in packets:
			if int(packet["arrival"]) > now_ms or \
					int(packet["sequence"]) <= last_sequence:
				continue
			# Delivery order can shuffle under jitter; emulate the real RPC's
			# strictly increasing snapshot sequence validation.
			last_sequence = int(packet["sequence"])
			Buffer.add_snapshot(history, now_ms, packet["state"])
			highest_history = maxi(highest_history, history.size())
		if history.is_empty():
			continue
		var delay := Buffer.interpolation_delay_ms(33.33, float(jitter_ms))
		var sample: Array = Buffer.sample(history, now_ms, delay)
		if sample.size() != 6:
			bounded = false
			continue
		samples += 1
		var latest: Array = (history.back() as Dictionary)["state"]
		var rendered: Vector2 = sample[0]
		# Simulation is strictly moving forward. Reordering, high RTT and
		# dropped packets must never extrapolate beyond the 60ms safety cap.
		var forward_cap: float = (latest[0] as Vector2).x + 180.0 * \
			float(Buffer.MAX_EXTRAPOLATE_MS) / 1000.0 + 0.01
		if not is_finite(rendered.x) or rendered.x > forward_cap or \
				rendered.x < -0.01:
			bounded = false
	return {
		"bounded": bounded and samples > 50,
		"received": last_sequence + 1,
		"max_history": highest_history,
		"samples": samples}

func _run() -> void:
	check("host_grace_exceeds_total_guest_reconnect_window",
		Session.RECONNECT_GRACE_MS > Session.CLIENT_RECONNECT_WINDOW_MS)
	check("guest_retries_at_least_three_times_before_timeout",
		Session.CLIENT_RECONNECT_WINDOW_MS / Session.RECONNECT_RETRY_MS >= 3)
	for profile in [
			{"rtt": 30, "jitter": 8, "loss": 19},
			{"rtt": 80, "jitter": 25, "loss": 8},
			{"rtt": 150, "jitter": 50, "loss": 5}]:
		var result: Dictionary = _simulate(
			profile.rtt, profile.jitter, profile.loss)
		var identity := "%dms_RTT_%dms_jitter_every_%d_lost" % [
			profile.rtt, profile.jitter, profile.loss]
		check(identity + "_never_visual_extrapolates_without_cap",
			result.bounded)
		check(identity + "_buffer_does_not_grow_forever",
			result.max_history <= Buffer.MAX_HISTORY)
	print("RECONNECT IMPAIRMENT PROFILE: %s" % (
		"PASS" if failures.is_empty() else "FAIL " + str(failures)))
	quit(0 if failures.is_empty() else 1)
