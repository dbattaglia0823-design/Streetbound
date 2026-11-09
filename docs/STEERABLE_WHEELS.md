# Layered and steerable wheels

The Porsche body remains unchanged. Four small procedural wheel illustrations now
live on Player/Art/Wheels beneath Player/Art/Sprite. The body occludes the
inner portions of the tires, so they only peek out around the wheel wells.
The wheel layer inherits the existing sprung-body animation.

## Behavior

- The front-left and front-right tires pivot about their own centers, using the
  current VehicleController2D.steering angle, easing and a bounded display gain.
- Rear wheels stay straight, including during slides and reversing.
- There are no additional physics bodies or changes to vehicle traction.
- The wheels are dark rubber shapes with light sidewalls and tread accents.
- A full suspension overlay is intentionally omitted because it would be hidden
  by the body from the current top-down camera.

## Alignment per model

Select Player/Art/Wheels in the Godot scene editor.
Auto-fit samples opaque pixels of the body PNG once on startup and estimates
the axle anchors and visible body width; the scan respects sprite rotation,
scale and transparent canvas padding. It falls back to the editable manual
defaults when the image bounds look implausible.

Turn off auto_fit_to_body to manually configure front_axle_distance,
rear_axle_distance, half_track_width and tire_size for a specific car.
The car faces upward (-Y) in local coordinates. The inner tire portions
should disappear behind the car sprite, leaving only the outer shoulders.
visual_steer_multiplier and max_visual_steer_degrees only affect visual
rotation, not the handling controller.

For the best eventual quality, future car body images should not already
contain fully baked wheels. Separate transparent car body PNGs allow the new
wheel sprites to be cleanly hidden by the actual wheel arches.

## Testing

Run tests/wheel_visual_test.gd or the normal GitHub CI suite. Visually inspect
full-lock left/right steering and the tire exposure on the Porsche at high
and low camera zoom. Exact wheel-well placement still requires a visual check
against the original painted car body.

Godot CanvasItem rendering order: https://docs.godotengine.org/en/stable/classes/class_canvasitem.html
