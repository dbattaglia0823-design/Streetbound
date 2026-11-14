class_name ToolkitRpmMix
extends RefCounted
## Port of the Game-Dev-Toolkit/REDLINE logarithmic RPM interpolation recipe.
## Only adjacent source bands play; sqrt weights retain perceived loudness.
## This helper has no dependencies on gameplay physics or audio devices.

static func rpm_weights(rpm: float, references: Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(references.size())
	if references.is_empty():
		return result
	if rpm <= float(references[0]):
		result[0] = 1.0
		return result
	var last := references.size() - 1
	if rpm >= float(references[last]):
		result[last] = 1.0
		return result
	for i in last:
		var lo := maxf(1.0, float(references[i]))
		var hi := maxf(lo + 1.0, float(references[i + 1]))
		if rpm > hi:
			continue
		var blend := clampf(log(maxf(1.0, rpm) / lo) / log(hi / lo), 0.0, 1.0)
		result[i] = sqrt(1.0 - blend)
		result[i + 1] = sqrt(blend)
		break
	return result


static func load_weights(throttle: float, normalized_boost: float,
		rpm_fraction: float) -> Vector2:
	# Closed throttle at speed favors engine braking; stationary idle still
	# emits a small loaded pulse instead of fading into silence.
	var load_value := clampf(throttle * 0.75 + normalized_boost * 0.25, 0.0, 1.0)
	if rpm_fraction < 0.10:
		load_value = maxf(load_value, 0.12)
	return Vector2(sqrt(load_value), sqrt(1.0 - load_value))
