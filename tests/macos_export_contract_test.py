"""Fast, platform-independent guard for files required by Streetbound.app.

The real Mac runner additionally cold-imports, launches the game and exports
a universal signed app; this file prevents easy-to-miss packaging regressions.
"""
from configparser import ConfigParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def config(path: str) -> ConfigParser:
    parser = ConfigParser(interpolation=None)
    files = parser.read(ROOT / path, encoding="utf-8")
    assert files, f"Missing config: {path}"
    return parser


def main() -> None:
    preset = config("export_presets.cfg")
    general = preset["preset.0"]
    options = preset["preset.0.options"]

    assert general["name"].strip('"') == "macOS"
    assert general["platform"].strip('"') == "macOS"
    assert general["export_filter"].strip('"') == "all_resources"
    assert general["export_path"].strip('"').endswith(".app")
    assert options["binary_format/architecture"].strip('"') == "universal"
    assert options["codesign/codesign"] == "1", "Use ad-hoc signing for Apple Silicon"
    assert options["notarization/notarization"] == "0"
    assert options["codesign/entitlements/app_sandbox/enabled"] == "false"
    assert options["application/bundle_identifier"].strip('"') == (
        "com.dbattaglia0823.streetbound"
    )

    # JSON and text files are loaded via FileAccess, not preloaded resources.
    include = {item.strip() for item in general["include_filter"].strip('"').split(",")}
    assert {"*.json", "*.txt"}.issubset(include), (
        f"Runtime data could be omitted from the .pck: {sorted(include)}"
    )
    for relative in (
        "worlds/morrow-coast.world.json",
        "worlds/active-world.json",
        "data/player_vehicle_catalog.json",
        "data/player_vehicle_additions.json",
        "data/dealerships.json",
        "data/upgrade_parts.json",
        "data/pending_vehicle_audio_profiles.json",
        "assets/Vehicles/streetbound_vehicle_list.txt",
        "scenes/title_menu.tscn",
        "scenes/main.tscn",
    ):
        assert (ROOT / relative).is_file(), f"Missing runtime file: {relative}"

    godot = config("project.godot")
    assert godot["rendering"]["renderer/rendering_method"].strip('"') == (
        "gl_compatibility"
    )
    assert godot["rendering"]["textures/vram_compression/import_etc2_astc"] == (
        "true"
    ), "Mac universal export requires ETC2/ASTC import availability"

    print("MACOS EXPORT CONTRACT: PASS")


if __name__ == "__main__":
    main()
