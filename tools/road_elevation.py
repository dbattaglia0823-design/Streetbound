"""Validation for optional World Forge road elevations (metres, 2.5D)."""

import math

LAYER_HEIGHT_M = 6.0
MAX_SLOPE = .12
LAYERS = range(-2, 3)


def set_profile(road, source):
    """Apply an authored profile. Absence and explicit 0-to-0 mean ground."""
    road.pop("elevation", None)
    if "elevation" not in source:
        return
    profile = source["elevation"]
    if not isinstance(profile, dict) or set(profile) != {"start_layer", "end_layer"}:
        raise ValueError("Road elevation needs start_layer and end_layer")
    layers = [profile[k] for k in ("start_layer", "end_layer")]
    # Godot emits integral JSON numbers as floats.
    if any(type(layer) not in (int, float) or layer not in LAYERS for layer in layers):
        raise ValueError("Road layers must be integers from -2 to 2")
    if abs(layers[0] - layers[1]) > 1:
        raise ValueError("A ramp can connect only adjacent road layers")
    if any(layers):
        road["elevation"] = dict(start_layer=int(layers[0]), end_layer=int(layers[1]))


def endpoint_layer(road, end):
    return road.get("elevation", {}).get(end + "_layer", 0)


def layer_at_join(road, station):
    """A sloping road meets other roads only at either authored endpoint."""
    profile = road.get("elevation")
    if not profile:
        return 0
    start, end = profile["start_layer"], profile["end_layer"]
    if start == end or station <= .12:
        return start
    if road["_stations"][-1] - station <= .12:
        return end
    return None


def validate_profile(road, length_m):
    profile = road.get("elevation")
    if not profile:
        return
    if math.dist(road["points"][0], road["points"][-1]) < .12:
        if profile["start_layer"] != profile["end_layer"]:
            raise ValueError("An elevation ramp must have distinct endpoints")
    rise = abs(profile["start_layer"] - profile["end_layer"]) * LAYER_HEIGHT_M
    if length_m < 4 or rise > MAX_SLOPE * length_m:
        raise ValueError(f"{road['name']}: ramp needs at least {rise / MAX_SLOPE:g} m for its rise")
