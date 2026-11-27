"""Release metadata and structural checks. No activation or source mutation."""
import hashlib
import math
from collections import Counter, defaultdict
from pathlib import Path

MAX_ARCHIVE = 128_000_000
MAX_ASSET = 64_000_000
MAX_PACKAGE = 512_000_000

def sha(data):
    return hashlib.sha256(data).hexdigest()

def file_sha(path):
    digest=hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024*1024), b""):
            digest.update(block)
    return digest.hexdigest()

def dependencies(archive, root):
    """Include prop artwork and explicit dealership appearance artwork."""
    paths=set()
    for prop in archive.get("props", []):
        if prop.get("asset_path"):
            paths.add(prop["asset_path"])
    for site in archive.get("editor_dealerships", []):
        appearance=site.get("appearance", {})
        if isinstance(appearance, dict) and appearance.get("asset_path"):
            paths.add(appearance["asset_path"])
    assets=(Path(root)/"assets").resolve()
    result=[]
    for resource in sorted(paths):
        if not isinstance(resource,str) or resource.startswith("/") or "\\" in resource:
            raise ValueError("Invalid map artwork resource")
        relative=resource.removeprefix("res://assets/")
        if ":" in relative or any(part in ("",".","..") for part in relative.split("/")):
            raise ValueError("Invalid map artwork resource: "+resource)
        candidate=(assets/relative).resolve()
        if not candidate.is_relative_to(assets) or not candidate.is_file():
            raise ValueError("Missing map artwork in game assets: "+resource)
        size=candidate.stat().st_size
        if size>MAX_ASSET:
            raise ValueError("Map artwork exceeds 64 MB: "+resource)
        result.append({"path":"assets/"+relative,"bytes":size,"sha256":file_sha(candidate)})
    if sum(row["bytes"] for row in result)>MAX_PACKAGE:
        raise ValueError("Map artwork exceeds release package budget")
    return result

def structural_audit(archive):
    """Check real baked index membership, not just source counts."""
    errors=[]
    warnings=list(archive.get("editor_warnings", []))
    chunks=archive["chunks"]
    size=float(archive["chunk_size"])
    if size<=0 or not math.isfinite(size):
        raise ValueError("Invalid chunk size")
    mappings={"segments":"segments","props":"props","junctions":"junctions",
              "walls":"walls","relief":"relief_faces","rails":"mountain_rails",
              "mountains":"mountains","bridges":"bridges"}
    membership=defaultdict(set)
    peaks=Counter()
    for key, cell in chunks.items():
        try:
            x,y=map(int,key.split(","))
            # Padded road geometry legitimately extends outside terrain.
            if abs(x)>10000 or abs(y)>10000:
                errors.append("Out-of-range chunk coordinate: "+key)
        except (TypeError,ValueError):
            errors.append("Invalid chunk coordinate: "+str(key))
            continue
        for field, source in mappings.items():
            indices=cell.get(field,[])
            peaks[field]=max(peaks[field],len(indices))
            count=len(archive.get(source,[]))
            for index in indices:
                if type(index) is not int or not 0<=index<count:
                    errors.append(f"Invalid {field} index in chunk {key}")
            if field in ("segments","props"):
                membership[(key,field)].update(indices)
    for field in ("segments","props"):
        for index,item in enumerate(archive[field]):
            if field=="props":
                x,y=item["p"]
            else:
                x=(item["a"][0]+item["b"][0])/2
                y=(item["a"][1]+item["b"][1])/2
                if not 0<=int(item["road"])<len(archive["roads"]):
                    errors.append(f"Segment {index} has invalid road")
            key=f"{math.floor(x/size)},{math.floor(y/size)}"
            if index not in membership.get((key,field),set()):
                errors.append(f"Missing {field} assignment {index} in {key}")
    # Weak road components are advisory: isolated circuits can be intentional.
    count=len(archive["roads"])
    parents=list(range(count))
    def find(n):
        while parents[n]!=n:
            parents[n]=parents[parents[n]]
            n=parents[n]
        return n
    for pair in archive.get("road_connections",[]):
        if len(pair)!=2 or any(type(n) is not int or not 0<=n<count for n in pair):
            errors.append("Invalid road connection")
            continue
        parents[find(pair[0])]=find(pair[1])
    components=len({find(n) for n in range(count)})
    if components>1:
        warnings.append(f"{components} weak road components; review isolated road networks")
    if peaks["props"]>500 or peaks["segments"]>1000:
        warnings.append("Dense streaming cells: run a measured Test Drive on target hardware")
    return {"errors":errors[:100],"error_count":len(errors),
            "warnings":warnings[:100],"warning_count":len(warnings),
            "road_components":components,"chunks":len(chunks),
            "peak_cell_assignments":dict(peaks)}
