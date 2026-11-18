#!/usr/bin/env python3
"""Guard existing handbrake drift/recovery behavior against the PR base.

An older test has a known *main-branch* failure at full throttle:
eventual_tire_recovery_1.0 (2.3s measured vs a 1.6s assertion).
Do not silently weaken that assertion. Instead verify no new assertions
fail and that the recovery timing is not worse than the unmodified main
VehicleController2D. When the main-branch test is corrected, the new branch
must also pass.
"""
import re
import sys
from pathlib import Path


def inspect(path: str) -> tuple[set[str], dict[str, float]]:
    log = Path(path).read_text(encoding="utf-8", errors="replace")
    if not re.search(r"^HANDBRAKE RECOVERY TESTS: (PASS|FAIL)", log, re.M):
        raise AssertionError(f"{path}: recovery suite did not finish")
    if re.search(r"SCRIPT ERROR:|Parse Error:|ERROR: Failed to load script", log):
        raise AssertionError(f"{path}: script import/runtime error")
    failed = set(re.findall(r"^FAIL ([\w.-]+):", log, re.M))
    timings = {
        pedal: float(seconds)
        for pedal, seconds in re.findall(
            r"^Recovery pedal (0\.0|1\.0): ([0-9.]+) s", log, re.M
        )
    }
    if set(timings) != {"0.0", "1.0"}:
        raise AssertionError(f"{path}: both recovery pedal traces missing")
    return failed, timings


def main() -> int:
    baseline_failures, baseline = inspect(sys.argv[1])
    candidate_failures, candidate = inspect(sys.argv[2])
    new_failures = candidate_failures - baseline_failures
    if new_failures:
        print(f"FAIL new handbrake recovery regressions: {sorted(new_failures)}")
        return 1
    for pedal in ("0.0", "1.0"):
        if candidate[pedal] > baseline[pedal] + 0.1:
            print(f"FAIL slower handbrake recovery at pedal {pedal}: "
                  f"baseline={baseline[pedal]}, candidate={candidate[pedal]}")
            return 1
    print("HANDBRAKE RECOVERY BASELINE PARITY: PASS")
    print(f"  existing main failures: {sorted(baseline_failures)}")
    print(f"  candidate failures: {sorted(candidate_failures)}")
    print(f"  baseline recovery seconds: {baseline}")
    print(f"  candidate recovery seconds: {candidate}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
