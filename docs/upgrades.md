# Six-slot upgrade system

The active game uses **Quick Upgrades** (`scripts/ui/quick_upgrades_overlay.gd`).
The only supported equipment slots are Engine, Turbo, Transmission, Tires,
Suspension, and Nitrous, in that order. The old stand-alone ten-slot garage
screen and its ECU, Intake, Exhaust, and Brakes parts have been removed.

`data/upgrade_parts.json` is the authoritative catalog: **90 templates**,
three specializations in each of five rarity tiers per slot. Of these, 30
unchanged legacy templates can be earned from current races; 60 expanded
variants are previewable but remain marked `race_drop_enabled=false`.
No reward, balance, rarity threshold, or vehicle physics tuning was changed
by this cleanup.

Old saves remain readable: `VehicleOwnership._load_upgrades()` skips parts
whose template ID is no longer in the catalog, and therefore also omits
their obsolete equipped slots. The player's cars, credits, progression,
eligible parts, and UID counter are preserved. Saving afterward persists
the cleaned six-slot inventory. This is intentionally a removal, not an
automatic conversion to free parts.

When adding future upgrades, add them to one of the six supported slots
and update both the catalog and tests. Do not reintroduce the old garage UI.
