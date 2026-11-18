#!/usr/bin/env python3
"""Compare two Streetbound AI driving benchmark JSON artifacts by scenario."""
import argparse
import json
from pathlib import Path

METRICS = (
    ("elapsed_s", "s"),
    ("steering_corrections", ""),
    ("offroad_time_s", "s"),
    ("collisions", ""),
    ("stuck_events", ""),
    ("stuck_recoveries", ""),
    ("max_cross_track_error_m", "m"),
)


def load(path: Path) -> dict:
    report = json.loads(path.read_text(encoding="utf-8"))
    if report.get("schema_version") != 1:
        raise ValueError(f"Unsupported schema: {path}")
    return report


def key(row: dict) -> tuple:
    return row["layout"], row["vehicle_id"], bool(row["obstructed"])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    args = parser.parse_args()
    before, after = load(args.baseline), load(args.candidate)
    if before["physics_hz"] != after["physics_hz"]:
        raise SystemExit("Incomparable benchmark: physics tick rates differ")
    if before["godot_version"] != after["godot_version"]:
        raise SystemExit("Incomparable benchmark: Godot versions differ")
    if before["seed"] != after["seed"]:
        raise SystemExit("Incomparable benchmark: random seeds differ")
    base_rows = {key(row): row for row in before["results"]}
    new_rows = {key(row): row for row in after["results"]}
    if set(base_rows) != set(new_rows):
        raise SystemExit("Incomparable benchmark: scenario matrices differ")
    for scenario in sorted(base_rows):
        old, new = base_rows[scenario], new_rows[scenario]
        print(f"\n{scenario[0]} / {scenario[1]}"
              + (" / obstacle" if scenario[2] else ""))
        print("  Completed:", old["completed"], "->", new["completed"])
        print("  Run time:", old["run_time_s"], "->", new["run_time_s"])
        for metric, unit in METRICS:
            lhs, rhs = float(old[metric]), float(new[metric])
            print(f"  {metric}: {lhs:.2f}{unit} -> {rhs:.2f}{unit}"
                  f" (change {rhs - lhs:+.2f}{unit})")


if __name__ == "__main__":
    main()
