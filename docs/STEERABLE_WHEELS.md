# Reusable wheel rigs for vehicles of different sizes

Streetbound uses one wheel-rig implementation across all vehicles. Each car
receives a VehicleAppearanceProfile resource with its body image, display
scale, four axle anchors and tire dimensions. That keeps wheel alignment
data out of the movement and steering physics scripts.

## Current game content

Only one playable car sprite is currently in the repository:
assets/player_car.png. Its layout is now captured in
resources/appearance/porsche_coupe.tres and assigned to
scenes/vehicle.tscn. The other files under
resources/appearance/templates are **unassigned examples** for upcoming
compact, sedan, SUV and pickup assets, not new driveable vehicles.

## Adding a different-size car

1. Import a top-down transparent PNG with its front pointing toward the top
   of the image. Prefer a body-only sprite with transparent wheel openings
   and no baked-in tires, so the turning tires are visible at the wells.
2. Duplicate the closest VehicleAppearanceProfile template into a new
   .tres file (e.g. resources/appearance/ford_pickup.tres).
3. In Godot's Inspector, assign Body Texture. Set Sprite Scale and Sprite
   Rotation Degrees so the car has the correct in-game displayed dimensions.
   The existing Porsche image uses 0.054 scale and 180-degree rotation.
   A source PNG's pixel resolution *alone* does not determine the car's
   displayed size.
4. Edit Front Left UV, Front Right UV, Rear Left UV and Rear Right UV to
   align with the centers of the actual painted wheel wells. Coordinates
   are fractions of the alpha-trimmed visible body bounding box:
   (0,0) = top-left, (1,1) = bottom-right *after* the sprite rotation.
   Example: Front Left UV (0.06, 0.24), Rear Left UV (0.06, 0.76).
   Right-side wheels typically use an x coordinate near 0.94.
5. Set Tire Width Ratio and Tire Length Ratio (fractions of visible body
   width/length). Minimum Tire Px and Maximum Tire Px protect against
   extremely large or tiny tires.
6. Make a new scene inherited from scenes/vehicle.tscn and assign the
   new appearance .tres to Art/Wheels > Appearance. Assign a matching
   VehicleConfig for the new car's handling. Do not use a single 39x88
   collision rectangle for physically larger trucks without also updating
   the collision shape and related physics configuration.

The wheel rig reads the opaque sprite silhouette once at setup. This
avoids alignment issues from transparent canvas margins; anchors are
relative to the visible body, not absolute source-image pixels.
Independent front/rear and left/right anchor coordinates handle differing
axle lengths, track widths and asymmetrical vehicle artwork.

## Runtime vehicle art switching

To replace the look of an already-instantiated car:

    var rig = car.get_node("Art/Wheels")
    rig.apply_appearance(load("res://resources/appearance/my_car.tres"))

This replaces the body image/transform when the appearance profile has a
texture, recalculates all four tire pivots, resizes and redraws the tires,
and reuses the same wheel nodes. It does not touch the vehicle's physics
or collision shape. Changes to handling/config and collision dimensions
must be made by the separate vehicle selection system when added.

Car physics still drives visual front steering and self-centering. Both
rear wheels remain unsteered. All tire nodes are children of the existing
Art body animation node and use negative z-index, so the body art covers
most of the wheel. A complete suspension sprite is unnecessary from
the present vertical top-down view.

## Alignment pitfalls and validation

- Auto-fit (no appearance profile) remains as a fallback for older cars;
  exact normalized profiles are preferred for production assets.
- A top-down PNG that already has painted wheels may hide or conflict with
  the separately rendered tires. Removing those baked tires from future
  body images is the cleanest solution.
- A mostly opaque background image will create an incorrect bounding box.
  Ensure the unused pixels really are alpha-transparent.
- Headless tests cannot confirm the actual wheel-well outline. Inspect
  several steering angles at low/high camera zoom and fine-tune the four
  anchors individually.

Run tests/wheel_visual_test.gd, tests/multi_model_wheels_test.gd and the
normal Godot regression suite. The multi-model test uses two synthetic
vehicle silhouettes with different sizes and aspect ratios and verifies
normalized coordinates, wheel resizing, steering, reset and physics
isolation. The additional template files do not imply the models are
already in the game.

Reference on reusable custom Resources:
https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html
