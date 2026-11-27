# Stunt ramp footprint and airborne light alignment

The rear running/brake/reverse lights and roof emergency effects now copy the animated car body's local transform after its frame update. The light anchors and glow sizes follow the body's lift, rotation and scale; the independent ground shadow and collision shape remain unscaled.

The runtime derives the object-ramp launch lip from the actual baked scenery prop dimensions, including X/Y scale, rotation and overall scale, rather than trusting cached jump metadata. The spatial index covers the entire rotated lip, and the swept launch check includes the car's projected capsule width. A car touching the lip near either edge launches; a car completely outside the ramp does not. The ramp's slope, height and flight physics are otherwise unchanged. Legacy road jumps retain their existing rules.

Regression tests cover both edges of a wide ramp across spatial cells, rotated/axis-scaled dimensions, cached scenery rebuild and removal, and airborne light scaling/restoration. Save and rebuild existing maps to apply source changes; no ramps need recreation.
