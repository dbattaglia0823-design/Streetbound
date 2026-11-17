# Off-screen vehicle awareness

## Player behavior

Streetbound shows small directional **CAR / RIVAL** chips near the edge of
the driving view when a nearby car is **ahead, out of camera view, and
closing**. Each chip contains an arrow toward the other vehicle and a
distance in feet. A slightly stronger color indicates near hazards. Markers
disappear when the car becomes visible, the player drives away from it,
or it is no longer closing. Only the three nearest qualifying cars appear,
preventing traffic clusters from covering the HUD.

The system is *informational* and does not change AI routing, car physics,
spawn/despawn logic or traffic collision behavior.

## Technical behavior

Implemented by `scripts/ui/offscreen_vehicle_awareness.gd`, mounted under
the existing driving HUD in `scripts/main.gd`. The same component is
instantiated per-player in each of the two `SubViewport` HUDs used by local
split-screen (`scripts/ui/local_split_screen.gd`).

- Watches the existing `traffic_vehicle`, `race_opponent` and
  `local_multiplayer_vehicle` groups; ignores the current driver's own car.
- Uses each viewport's actual `get_canvas_transform()`, preserving correct
  bearings when cameras lead, rotate, zoom or render in separate viewports.
- Requires a car within **8–260 meters**, in the forward field, with relative
  closing speed of at least **1.25 meters/second**. Both faster player
  approaches and stationary-player oncoming traffic can qualify.
- Never marks visible cars, including those just past the view boundary;
  considers a 45-pixel visible-car margin to avoid flickering during entry.
- Refreshes at **~8 times/second** and draws at most three compact chips,
  using a 94-pixel horizontal / 99-pixel vertical screen inset.
- Shows **feet** to match the project's imperial driving display.
- Suppresses warnings during game pause and other full-screen pause menus.
- Uses the traffic manager's actual per-agent speed and direction instead of
  reading the unset velocity on traffic `CharacterBody2D` actors.

### Limits

This is forward-obstacle awareness, not a collision predictor or an active
navigation route marker. Nearby traffic on an adjacent road may occasionally
qualify if it lies ahead and closes relative to the player; identifying the
same road through the routed street graph is a possible later refinement.

Validated by `tests/offscreen_vehicle_awareness_test.gd` on Godot 4.4.1 and
4.6.3, including bearing geometry, closing/receding traffic, imperial labels,
pause behavior, actual main-scene integration and split-screen cameras.
