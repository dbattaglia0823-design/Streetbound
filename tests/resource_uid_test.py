"""Check persistent resource identifiers before Godot regenerates missing ones."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def main():
    errors = []
    identifiers = {}
    sources = sorted(
        path
        for folder in ("scripts", "tests", "addons", "map-editor", "worlds")
        for path in (ROOT / folder).rglob("*")
        if path.suffix in (".gd", ".gdshader")
    )
    for source in sources:
        sidecar = Path(str(source) + ".uid")
        if not sidecar.is_file():
            errors.append(f"Missing persistent Godot identifier: {sidecar.relative_to(ROOT)}")
            continue
        value = sidecar.read_text(encoding="utf-8").strip()
        if not re.fullmatch(r"uid://[a-z0-9]+", value):
            errors.append(f"Invalid identifier in {sidecar.relative_to(ROOT)}")
        elif value in identifiers:
            errors.append(f"Duplicate identifier: {source.relative_to(ROOT)} / {identifiers[value]}")
        identifiers[value] = source.relative_to(ROOT)
    for error in errors:
        print("FAIL", error)
    if errors:
        raise SystemExit(1)
    print(f"RESOURCE UID CONTRACT: PASS ({len(sources)} scripts/shaders, no missing or duplicate IDs)")


if __name__ == "__main__":
    main()
