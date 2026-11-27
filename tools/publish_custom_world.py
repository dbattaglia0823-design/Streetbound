"""Publish a saved custom Streetbound map as a production game world.

The compiler is the same one used for full-game Test Drive. Output archives
are immutable/content-addressed; the active-world pointer is replaced LAST.
No operation modifies Morrow Coast or the player's save. Old archives remain
available for rollback. All referenced project artwork must already exist
in the game repository so it can be included in the exported build.

Usage:
  python tools/publish_custom_world.py --project . --source /path/to/map.world.json --backup-dir /path/to/backups
  python tools/publish_custom_world.py --project . --restore --backup-dir /path/to/backups
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

from build_custom_test_world import make_archive
from world_release_audit import dependencies as dependency_manifest, structural_audit, MAX_ARCHIVE

MANIFEST = "worlds/active-world.json"
OUTPUT_DIR = "worlds/published"
DEFAULT = {
    "format": "streetbound.active-world", "version": 1,
    "mode": "morrow", "id": "morrow-coast", "name": "Morrow Coast",
    "archive": "res://worlds/morrow-coast.world.json",
}
MAX_SOURCE_BYTES = 8_000_000


def _json_bytes(data):
    return (json.dumps(data, ensure_ascii=False, allow_nan=False,
                       separators=(",", ":"), sort_keys=True) + "\n").encode("utf-8")


def _read_source(path):
    if not path.is_file() or path.stat().st_size > MAX_SOURCE_BYTES:
        raise ValueError("Saved custom map is missing or larger than 8 MB")
    raw = path.read_bytes()
    doc = json.loads(raw.decode("utf-8"))
    if not isinstance(doc, dict) or doc.get("customMap") is not True:
        raise ValueError("The selected map is not an authored custom map")
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,100}\.world\.json", path.name):
        raise ValueError("Custom map filename is not safe for publishing")
    return doc, raw


def _production_checks(doc, archive, root):
    """Fail instead of shipping a world the player cannot safely spawn into."""
    if not archive.get("roads") or not archive.get("segments"):
        raise ValueError("Add a drivable road before publishing a game world")
    spawn_markers = [m for m in doc.get("markers", []) if m.get("type") == "player_spawn"]
    if len(spawn_markers) != 1:
        raise ValueError("Place exactly one Player Spawn marker before publishing")
    spawn = archive["spawn"]["position"]
    on_road = False
    for road in archive["roads"]:
        if "elevation" in road:
            continue
        points = road["points"]
        for a, b in zip(points, points[1:]):
            abx, aby = b[0]-a[0], b[1]-a[1]
            extent = abx*abx+aby*aby
            if extent <= 0:
                continue
            u = max(0, min(1, ((spawn[0]-a[0])*abx+(spawn[1]-a[1])*aby)/extent))
            distance = math.hypot(spawn[0]-a[0]-u*abx, spawn[1]-a[1]-u*aby)
            if distance <= max(1.0, float(road["width"])*.5-1.5):
                on_road = True
                break
        if on_road:
            break
    if not on_road:
        raise ValueError("Player Spawn must sit on a drivable road with clearance")
    for prop in archive.get("props", []):
        if not bool(prop.get("solid", False)):
            continue
        px, py = prop["p"]
        width, height = prop["size"]
        angle = float(prop.get("angle", 0))
        dx, dy = spawn[0]-px, spawn[1]-py
        local_x = dx*math.cos(angle)+dy*math.sin(angle)
        local_y = -dx*math.sin(angle)+dy*math.cos(angle)
        if abs(local_x) <= width*.5+1.5 and abs(local_y) <= height*.5+1.5:
            raise ValueError("Player Spawn overlaps solid scenery: "+str(prop.get("authoring_id", "")))
    # The production game does not import files from user:// at runtime.
    # The authoring converter validates asset categories/regions; verify the
    # resulting on-disk art dependencies, and preserve the source snapshot.
    dependencies = set()
    for prop in archive["props"]:
        resource = prop.get("asset_path")
        if not resource:
            continue
        if not isinstance(resource, str) or resource.startswith("/") or "\\" in resource:
            raise ValueError("Invalid project artwork resource")
        name = resource.removeprefix("res://assets/")
        candidate = (root/"assets"/name).resolve()
        if not candidate.is_relative_to((root/"assets").resolve()) or not candidate.is_file():
            raise ValueError("Missing map artwork in game assets: " + resource)
        dependencies.add("res://assets/"+name)
    if not (root/"worlds"/"morrow-coast.world.json").is_file():
        raise ValueError("Fallback Morrow Coast world is missing")
    return sorted(dependencies)


def _atomic_write(target, data):
    target.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix="."+target.name+".",suffix=".tmp",dir=target.parent)
    try:
        with os.fdopen(handle,"wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary,target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _backup_manifest(root, backup_dir):
    path = root/MANIFEST
    prior = path.read_bytes() if path.is_file() else _json_bytes(DEFAULT)
    if backup_dir is None:
        raise ValueError("Provide a backup directory before changing the game world")
    backup_dir = Path(backup_dir)
    backup_dir.mkdir(parents=True,exist_ok=True)
    nonce = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    backup = backup_dir / ("active-world-"+nonce+".json")
    _atomic_write(backup,prior)
    return backup


def _activate(root, manifest, backup_dir):
    current = root/MANIFEST
    backup = _backup_manifest(root,backup_dir)
    try:
        _atomic_write(current,_json_bytes(manifest))
    except BaseException:
        _atomic_write(current,backup.read_bytes())
        raise
    return backup


def prepare(source, root):
    """Compile the exact saved source without activating or writing any files."""
    source = Path(source).resolve()
    root = Path(root).resolve()
    doc, raw = _read_source(source)
    # Stable event progress IDs depend on the original source filename.
    doc["_source_filename"] = source.name
    compiled = make_archive(doc)
    _production_checks(doc,compiled,root)
    dependencies = dependency_manifest(compiled,root)
    audit = structural_audit(compiled)
    if audit["error_count"]:
        raise ValueError("Release structural audit failed: "+"; ".join(audit["errors"][:5]))
    compiled["editor_custom_world"] = True
    compiled["editor_custom_test_drive"] = False
    compiled["editor_published_world"] = True
    compiled["editor_source_sha256"] = hashlib.sha256(raw).hexdigest()
    compiled["editor_required_assets"] = ["res://"+row["path"] for row in dependencies]
    compiled["editor_asset_manifest"] = dependencies
    binary = _json_bytes(compiled)
    if len(binary)>MAX_ARCHIVE:
        raise ValueError("Compiled world exceeds 128 MB release budget")
    # The package ID includes compiler output, not only source text: an
    # upgraded baker may produce different junctions from the same map.
    digest = hashlib.sha256(binary).hexdigest()[:20]
    filename = "world-"+digest+".world.json"
    source_name = "source-"+digest+".world.json"
    archive_rel = OUTPUT_DIR+"/"+filename
    source_rel = OUTPUT_DIR+"/"+source_name
    # Check the exact bytes being packaged, not just the Python object.
    if json.loads(binary.decode("utf-8"))["editor_races"] != compiled["editor_races"]:
        raise ValueError("Packaged event list did not survive JSON serialization")
    active = dict(DEFAULT,mode="published",id=source.name,
                  name=str(doc.get("name",source.stem))[:60],
                  archive="res://"+archive_rel,
                  source="res://"+source_rel,
                  source_sha256=compiled["editor_source_sha256"])
    return {"doc":doc,"raw":raw,"archive":compiled,"binary":binary,"manifest":active,
            "dependencies":dependencies,"audit":audit,"archive_rel":archive_rel,"source_rel":source_rel}


def publish(source, root, backup_dir):
    root=Path(root).resolve()
    prepared=prepare(source,root)
    raw=prepared["raw"]
    binary=prepared["binary"]
    compiled=prepared["archive"]
    active=prepared["manifest"]
    dependencies=prepared["dependencies"]
    archive_rel=prepared["archive_rel"]
    source_rel=prepared["source_rel"]
    archive_path = root/archive_rel
    source_path = root/source_rel
    # Historical packages are immutable. Never overwrite a different map's
    # world data, and never change the active pointer before both are safe.
    for path, payload in ((archive_path,binary),(source_path,raw)):
        if path.exists() and path.read_bytes()!=payload:
            raise ValueError("Existing immutable world package has conflicting bytes: "+path.name)
        if not path.exists():
            _atomic_write(path,payload)
    previous = _activate(root,active,backup_dir)
    return {
        "result":"published","name":active["name"],"world_id":active["id"],
        "archive":active["archive"],"source":active["source"],
        "roads":len(compiled["roads"]),"junctions":len(compiled["junctions"]),
        "races":len(compiled["editor_races"]),"markers":len(compiled["editor_game_markers"]),
        "dealerships":len(compiled["editor_dealerships"]),
        "assets":len(dependencies),"backup":str(previous),
    }


def restore(root, backup_dir):
    root=Path(root).resolve()
    if not (root/"worlds"/"morrow-coast.world.json").is_file():
        raise ValueError("Morrow Coast fallback archive is missing")
    previous=_activate(root,DEFAULT,backup_dir)
    return {"result":"restored","name":"Morrow Coast","backup":str(previous)}


def main():
    cli=argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--project",required=True)
    cli.add_argument("--source")
    cli.add_argument("--backup-dir",required=True)
    cli.add_argument("--restore",action="store_true")
    args=cli.parse_args()
    try:
        if args.restore:
            if args.source:raise ValueError("Restore does not take a map source")
            result=restore(args.project,args.backup_dir)
        else:
            if not args.source:raise ValueError("Select a saved custom map to publish")
            result=publish(args.source,args.project,args.backup_dir)
        print(json.dumps(result,sort_keys=True))
    except (OSError,ValueError,KeyError,TypeError,IndexError,UnicodeError) as error:
        print("WORLD PUBLISH FAILED: "+str(error),file=sys.stderr)
        sys.exit(1)


if __name__=="__main__":
    main()
