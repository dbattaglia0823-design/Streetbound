#!/usr/bin/env python3
"""Validate exported AI benchmark data without declaring weak AI a CI error.

Bad JSON, missing scenarios, negative telemetry or invalid completion timing
are infrastructure failures. DNFs and slow times are observations.
"""
import argparse
import csv
import json
import math
from pathlib import Path

REQUIRED = (
    "vehicle_id", "layout", "completed", "laps_completed", "lap_times_s",
    "run_time_s", "elapsed_s", "steering_corrections", "offroad_time_s",
    "collisions", "stuck_events", "stuck_recoveries", "unresolved_stuck_events",
    "route_length_m", "forward_route_distance_m", "wall_time_ms"
)
VEHICLES = {"acura-integra", "mclaren-570s", "cadillac-escalade"}
LAYOUTS = {"ashford_drag", "larkspur_street", "ashford_circuit"}


def validate(folder: Path, mode: str) -> None:
    source = folder / "ai_driving_benchmark.json"
    csv_path = folder / "ai_driving_benchmark.csv"
    report = json.loads(source.read_text(encoding="utf-8"))
    assert report["schema_version"] == 1, "unexpected schema version"
    assert report["mode"] == mode, "wrong benchmark mode"
    rows = report["results"]
    expected = 3 if mode == "smoke" else 10
    assert len(rows) == report["cases"] == expected, "incomplete scenario matrix"
    assert report["completions"] == sum(bool(r["completed"]) for r in rows)
    seen = set()
    for row in rows:
        assert all(key in row for key in REQUIRED), f"missing metric in {row}"
        assert row["vehicle_id"] in VEHICLES
        assert row["layout"] in LAYOUTS
        key = (row["vehicle_id"], row["layout"], bool(row["obstructed"]))
        assert key not in seen, f"duplicate case: {key}"
        seen.add(key)
        for field in ("elapsed_s", "offroad_time_s", "route_length_m",
                      "forward_route_distance_m", "wall_time_ms"):
            value = row[field]
            assert isinstance(value, (int, float)) and math.isfinite(value) and value >= 0, (key, field, value)
        for field in ("steering_corrections", "collisions", "stuck_events",
                      "stuck_recoveries", "unresolved_stuck_events", "laps_completed"):
            value = row[field]
            assert isinstance(value, int) and value >= 0, (key, field, value)
        assert row["route_length_m"] >= 100.0, key
        assert row["offroad_time_s"] <= row["elapsed_s"] + 0.001, key
        assert row["stuck_events"] == row["stuck_recoveries"] + row["unresolved_stuck_events"], key
        if row["completed"]:
            assert row["status"] == "completed" and row["run_time_s"] > 0, key
        else:
            assert row["status"] == "dnf_or_timeout" and row["run_time_s"] is None, key
        if row["layout"] == "ashford_circuit" and row["completed"]:
            assert row["laps_completed"] == 1 and len(row["lap_times_s"]) == 1, key
            assert abs(row["lap_times_s"][0] - row["run_time_s"]) < 0.001, key
        else:
            assert row["laps_completed"] == 0 and row["lap_times_s"] == [], key
    combos = {(r["vehicle_id"], r["layout"]) for r in rows if not r["obstructed"]}
    assert len(combos) == (3 if mode == "smoke" else 9), "vehicle-layout coverage missing"
    assert {x[1] for x in combos} == LAYOUTS
    assert {x[0] for x in combos} == VEHICLES
    if mode == "full":
        assert ("acura-integra", "larkspur_street", True) in seen, "missing blocked road recovery probe"

    with csv_path.open(encoding="utf-8", newline="") as handle:
        csv_rows = list(csv.DictReader(handle))
    assert len(csv_rows) == expected, "CSV/JSON row mismatch"
    assert all(c in csv_rows[0] for c in (
        "vehicle_id", "layout", "run_time_s", "steering_corrections",
        "offroad_time_s", "collisions", "stuck_recoveries"
    )), "CSV fields missing"
    for row, csv_row in zip(rows, csv_rows):
        assert csv_row["vehicle_id"] == row["vehicle_id"]
        assert csv_row["layout"] == row["layout"]
    print(f"AI BENCHMARK REPORT: PASS ({mode}, {expected} runs, "
          f"{report['completions']} completed, {expected-report['completions']} DNF)")
    for r in rows:
        print(f"  {r['layout']:<18} {r['vehicle_id']:<19} "
              f"{r['status']:<14} t={r['elapsed_s']:>7.2f}s "
              f"steer={r['steering_corrections']:>4} "
              f"offroad={r['offroad_time_s']:>7.2f}s "
              f"crashes={r['collisions']:>2} "
              f"recovered={r['stuck_recoveries']}/{r['stuck_events']}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=("smoke", "full"), default="smoke")
    ap.add_argument("--folder", type=Path, default=Path(".runtime/ai_benchmark"))
    args = ap.parse_args()
    validate(args.folder, args.mode)
