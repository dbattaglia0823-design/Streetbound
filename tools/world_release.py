"""Read-only preflight, portable release export/verification and safe rollback.

Packages contain the map source, production archive and explicitly referenced
project art. The base game and its built-in atlas resources are prerequisites.
Packages are not executables and are never automatically extracted or run.
"""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tempfile
import zipfile

from publish_custom_world import prepare, publish_prepared, _atomic_write, _activate, DEFAULT, MANIFEST, _json_bytes, MAX_SOURCE_BYTES
from world_release_audit import sha, file_sha, MAX_ARCHIVE, MAX_ASSET, MAX_PACKAGE, structural_audit, dependencies

def report(prepared):
    archive=prepared["archive"]
    return {"result":"ready","name":prepared["manifest"]["name"],
            "source_sha256":sha(prepared["raw"]),"archive_sha256":sha(prepared["binary"]),
            "world_id":prepared["manifest"]["id"],
            "archive_bytes":len(prepared["binary"]),"source_bytes":len(prepared["raw"]),
            "roads":len(archive["roads"]),"races":len(archive["editor_races"]),
            "markers":len(archive["editor_game_markers"]),"assets":prepared["dependencies"],
            "audit":prepared["audit"],"playtest":"not_verified",
            "multiplayer":"Same world ID and archive SHA-256 required; same base game build required."}

def preflight(source,root):
    return report(prepare(source,root))

def _safe_path(name):
    return (isinstance(name,str) and name and not name.startswith("/") and
            "\\" not in name and ":" not in name and
            all(part not in ("",".","..") for part in name.split("/")))

def export_package(source,root,destination):
    root=Path(root).resolve()
    prepared=prepare(source,root)
    info=report(prepared)
    archive=prepared["archive_rel"]
    snapshot=prepared["source_rel"]
    entries=[{"path":archive,"bytes":len(prepared["binary"]),"sha256":info["archive_sha256"]},
             {"path":snapshot,"bytes":len(prepared["raw"]),"sha256":info["source_sha256"]}]
    entries+=prepared["dependencies"]
    manifest={"format":"streetbound.map-release","version":1,
              "active_world":prepared["manifest"],"files":entries}
    if sum(row["bytes"] for row in entries)>MAX_PACKAGE:
        raise ValueError("Package exceeds 512 MB uncompressed budget")
    destination=Path(destination).resolve()
    if destination.suffix.lower()!=".zip":
        raise ValueError("Release destination must end in .zip")
    if destination.exists():
        raise ValueError("Release ZIP already exists; choose a new filename")
    destination.parent.mkdir(parents=True,exist_ok=True)
    fd,temp=tempfile.mkstemp(suffix=".zip",dir=destination.parent)
    os.close(fd)
    try:
        with zipfile.ZipFile(temp,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
            z.writestr("release.json",_json_bytes(manifest))
            z.writestr(archive,prepared["binary"])
            z.writestr(snapshot,prepared["raw"])
            for row in prepared["dependencies"]:
                z.write(root/row["path"],row["path"])
        verify_package(temp)
        # Atomic no-overwrite publication on the same filesystem.
        # Fail rather than expose a partial ZIP if hard links are unavailable.
        os.link(temp,destination)
    finally:
        Path(temp).unlink(missing_ok=True)
    return dict(info,result="exported",package=str(destination),package_sha256=file_sha(destination))

def _manifest_paths(active):
    if not isinstance(active,dict) or active.get("format")!="streetbound.active-world" or active.get("version")!=1 or active.get("mode")!="published":
        raise ValueError("Invalid published-world manifest")
    archive=str(active.get("archive","")).removeprefix("res://")
    match=re.fullmatch(r"worlds/published/world-([0-9a-f]{20})\.world\.json",archive)
    if not match:
        raise ValueError("Invalid archive path")
    source="worlds/published/source-"+match[1]+".world.json"
    if active.get("source")!="res://"+source:
        raise ValueError("Invalid source path")
    if len(str(active.get("id","")))>100 or not re.fullmatch(r"[A-Za-z0-9_.-]{1,100}\.world\.json",str(active.get("id",""))):
        raise ValueError("Invalid map identity")
    return archive,source,match[1]

def _check_payloads(active,archive_raw,source_raw):
    _,_,digest=_manifest_paths(active)
    if sha(archive_raw)[:20]!=digest or sha(source_raw)!=active.get("source_sha256"):
        raise ValueError("Archive or source checksum mismatch")
    archive=json.loads(archive_raw)
    if (archive.get("format")!="streetbound.streamed-world" or archive.get("version")!=1 or
        archive.get("editor_published_world") is not True or archive.get("editor_custom_test_drive") is not False or
        archive.get("editor_world_id")!=active["id"] or archive.get("editor_source_sha256")!=sha(source_raw)):
        raise ValueError("Archive release identity mismatch")
    if structural_audit(archive)["error_count"]:
        raise ValueError("Archive structural audit failed")
    return archive

def verify_package(path):
    path=Path(path)
    if path.stat().st_size>MAX_PACKAGE+1_000_000:
        raise ValueError("Oversized ZIP")
    with zipfile.ZipFile(path) as z:
        infos=z.infolist()
        names=[item.filename for item in infos]
        if len(names)>10000 or len(set(names))!=len(names) or any(not _safe_path(name) for name in names):
            raise ValueError("Invalid or duplicate ZIP member")
        if any(item.is_dir() or item.flag_bits&1 for item in infos):
            raise ValueError("Directories or encrypted ZIP members are not supported")
        if sum(item.file_size for item in infos)>MAX_PACKAGE+1_000_000:
            raise ValueError("Oversized uncompressed ZIP")
        if "release.json" not in names or z.getinfo("release.json").file_size>1_000_000:
            raise ValueError("Missing or oversized release manifest")
        manifest=json.loads(z.read("release.json"))
        if manifest.get("format")!="streetbound.map-release" or manifest.get("version")!=1:
            raise ValueError("Unsupported release package")
        active=manifest["active_world"]
        archive,source,_=_manifest_paths(active)
        rows=manifest["files"]
        expected={}
        for row in rows:
            name=row["path"]
            if name in expected or not _safe_path(name) or (name not in (archive,source) and not name.startswith("assets/")):
                raise ValueError("Unexpected release member")
            expected[name]=row
        if set(names)!=set(expected)|{"release.json"} or archive not in expected or source not in expected:
            raise ValueError("Missing or unlisted release member")
        import hashlib
        for name,row in expected.items():
            size=z.getinfo(name).file_size
            cap=MAX_ARCHIVE if name==archive else MAX_SOURCE_BYTES if name==source else MAX_ASSET
            if size!=row["bytes"] or size>cap:
                raise ValueError("Member size mismatch: "+name)
            digest=hashlib.sha256()
            with z.open(name) as stream:
                for block in iter(lambda:stream.read(1024*1024),b""):
                    digest.update(block)
            if digest.hexdigest()!=row["sha256"]:
                raise ValueError("Member checksum mismatch: "+name)
        data=_check_payloads(active,z.read(archive),z.read(source))
        assets=[expected[name] for name in sorted(expected) if name.startswith("assets/")]
        if data.get("editor_asset_manifest",[])!=assets:
            raise ValueError("Archive dependency manifest mismatch")
        return {"result":"verified","world_id":active["id"],"archive_sha256":expected[archive]["sha256"],"assets":len(assets)}

def install_package(path,root,backup_dir):
    """Activate only after a matching local compiler and artwork check."""
    verified=verify_package(path)
    root=Path(root).resolve()
    with zipfile.ZipFile(path) as z:
        manifest=json.loads(z.read("release.json"))
        active=manifest["active_world"]
        archive,source,_=_manifest_paths(active)
        source_raw=z.read(source)
        archive_raw=z.read(archive)
        data=_check_payloads(active,archive_raw,source_raw)
        if dependencies(data,root)!=data.get("editor_asset_manifest",[]):
            raise ValueError("Local project artwork differs; use the matching game project and assets")
        with tempfile.TemporaryDirectory(prefix="streetbound-release-") as scratch:
            local=Path(scratch)/active["id"]
            local.write_bytes(source_raw)
            prepared=prepare(local,root)
            if sha(prepared["binary"])!=verified["archive_sha256"] or prepared["binary"]!=archive_raw:
                raise ValueError("Local compiler output differs; use the same game project version")
            result=publish_prepared(prepared,root,backup_dir)
    return dict(result,result="installed",archive_sha256=verified["archive_sha256"])


def compare(before,after):
    """Stable ID comparisons. JSON object ordering does not imply a change."""
    result={}
    for key in ("roads","regions","props","markers","races","dealerships"):
        left={str(row["id"]):row for row in before.get(key,[])}
        right={str(row["id"]):row for row in after.get(key,[])}
        added=sorted(right.keys()-left.keys())
        removed=sorted(left.keys()-right.keys())
        changed=sorted(k for k in left.keys()&right.keys() if left[k]!=right[k])
        result[key]={"added":len(added),"removed":len(removed),"changed":len(changed),
                     "added_ids":added[:100],"removed_ids":removed[:100],"changed_ids":changed[:100]}
    other=sorted(key for key in before.keys()|after.keys() if key not in result and before.get(key)!=after.get(key))
    return {"result":"compared","entities":result,"other_changed":other}

def rollback(root,backup_dir,backup):
    root=Path(root).resolve()
    backup_dir=Path(backup_dir).resolve()
    backup=Path(backup).resolve()
    if backup.parent!=backup_dir or not re.fullmatch(r"active-world-\d{8}T\d{12}Z\.json",backup.name):
        raise ValueError("Select an existing publication backup")
    if backup.stat().st_size>100_000:
        raise ValueError("Oversized backup manifest")
    active=json.loads(backup.read_bytes())
    if active==DEFAULT:
        if not (root/"worlds/morrow-coast.world.json").is_file():
            raise ValueError("Missing Morrow fallback")
    else:
        archive,source,_=_manifest_paths(active)
        for name,cap in ((archive,MAX_ARCHIVE),(source,MAX_SOURCE_BYTES)):
            target=(root/name).resolve()
            if not target.is_relative_to(root/"worlds"/"published") or target.stat().st_size>cap:
                raise ValueError("Invalid historical package path or size")
        data=_check_payloads(active,(root/archive).read_bytes(),(root/source).read_bytes())
        actual=dependencies(data,root)
        if "editor_asset_manifest" in data and data["editor_asset_manifest"]!=actual:
            raise ValueError("Historical project artwork has changed; restore matching assets first")
    saved=_activate(root,active,backup_dir)
    return {"result":"rolled_back","name":active["name"],"backup":str(saved)}

def main():
    cli=argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--project",required=True)
    modes=cli.add_mutually_exclusive_group(required=True)
    modes.add_argument("--preflight")
    modes.add_argument("--export")
    modes.add_argument("--verify")
    modes.add_argument("--rollback")
    modes.add_argument("--install")
    cli.add_argument("--output")
    cli.add_argument("--backup-dir")
    args=cli.parse_args()
    try:
        if args.preflight:
            result=preflight(args.preflight,args.project)
        elif args.export:
            if not args.output:raise ValueError("Choose a ZIP output")
            result=export_package(args.export,args.project,args.output)
        elif args.verify:
            result=verify_package(args.verify)
        elif args.install:
            if not args.backup_dir:raise ValueError("Choose a backup directory")
            result=install_package(args.install,args.project,args.backup_dir)
        else:
            if not args.backup_dir:raise ValueError("Choose a backup directory")
            result=rollback(args.project,args.backup_dir,args.rollback)
        print(json.dumps(result,sort_keys=True,allow_nan=False))
    except (OSError,ValueError,KeyError,TypeError,IndexError,AttributeError,zipfile.BadZipFile,RuntimeError) as error:
        print(json.dumps({"result":"blocked","error":str(error)}))
        sys.exit(1)

if __name__=="__main__":
    main()
