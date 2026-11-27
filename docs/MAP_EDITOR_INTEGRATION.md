# Map Editor integration polish (Phases 6–10)

This branch integrates PRs #206–210 without changing main. All five focused test suites remain wired into CI, plus the existing phase 1–5, physics and multiplayer checks. Review this integrated PR rather than merging the independent phase PRs separately.

Known prior CI failures: reconnect host selected vehicle assertion (#206), optional traffic-light proxy dimensions (#208), Morrow unchanged terrain round-trip metadata (#209). The latter two have targeted fixes here; reconnect requires investigation if it reproduces. No tests disabled or loosened.

Validation drives opt out of the living-world clock to keep scenario weather and density stable. Ordinary Test Drive remains temporary. Progress is measured in metres from actual movement, excluding projection discontinuities. New active chunks immediately inherit night lighting; dormant chunks remain unlit. Streaming prediction uses a metres-per-second threshold, not pixels per second.

Check before release: author a neighborhood, inspect validation, drive a flat route, return to editor, apply finishing, save and compare backup, preflight, export, verify and install on a second matching project. Test rest during idle, race, pursuit and contract; check morning/night, wet grip, traffic density, editor and split-screen UI; measure target-device streaming FPS. Existing Morrow and career saves must remain untouched. No claim of visual or hardware validation until performed.

Integrated regression `tests/integrated_map_editor_test.gd` checks a real generated neighborhood, source audit, authored home marker, finishing props, save backup and comparison, day/night response, and production preflight/export/verification without activation. The rest dialog uses compact two-column options; the stopped tolerance is 1 m/s. Save paths and temporary source checksums are validated before replacement.

The first combined CI run exposed a second real-map round-trip failure: stock terrain display names were still being persisted. Metadata is now emitted only for new authored Morrow parcels, not legacy terrain. The exact unchanged-map test remains intact.
