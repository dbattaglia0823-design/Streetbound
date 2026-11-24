## Summary and affected paths

Describe the actual change, its owning subsystem and relevant source files. Note the current target branch / commit.

## Tests and evidence

- **Commands actually run, with results:**
- **CI run links / failing checks:**
- **Visual, device or interactive checks actually performed:**
- **What was not tested:**

Project-specific verification: Run relevant GDScript/Python regression checks and CI workflow for the changed subsystem. For AI/physics, include real driving benchmark evidence; for world changes, document whether a map rebake and visual inspection were performed.

## Compatibility and risks

- **Save/migration impact:**
- **Important behavior or asset references:**
- **Open risks or reproducible defects:**

Recheck when relevant: Handling and control input, AI races, map geometry, multiplayer behavior, persistence, mobile performance and wheel sprites.

## Knowledge updates

- [ ] Read `AGENTS.md`, `docs/INDEX.md`, relevant source and existing tests.
- [ ] Updated only affected system/architecture/decision notes, or explained why unchanged.
- [ ] Updated `docs/HANDOFF.md` with verified changed files, tests actually run, limitations and next action, or explained why no update is needed.
- [ ] Linked confirmed regressions in `docs/KNOWN_ISSUES.md` with reproduction evidence; did not label unverified concerns as defects.
- [ ] Kept reusable guidance in [Game-Dev-Toolkit](https://github.com/dbattaglia0823-design/Game-Dev-Toolkit/tree/main/knowledge), with game-specific facts local.
- [ ] Checked licenses and kept secrets, personal notes and private data out of public commits.

Documentation updated or reason unchanged:
