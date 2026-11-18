---
name: knowledge-maintenance
description: Use after verified development work to update only relevant architecture, decision, issue, work-log and handoff notes.
---

# Keep knowledge grounded

1. Read the target game's `docs/INDEX.md` or this toolkit's `knowledge/INDEX.md`; retrieve only the page related to the change.
2. Review actual diff, changed paths, current commit/PR and test results before documenting implementation.
3. Only record `Verified` facts backed by code or tests; mark uncertain items `Planned`, `Hypothesis`, or `Unverified`.
4. Update architecture when interfaces or file ownership change; log meaningful decisions and reproducible issues.
5. Record the latest short handoff with completed work, checks **actually run**, risk, and next action. Avoid full transcript dumps.
6. Put cross-game general techniques in the central vault and game-specific mechanics/values in that game's repository.
7. Check links and avoid secrets, plugin credentials, local workspace files and unlicensed third-party material.

A well-maintained small index is more useful than a huge automatically generated note.
