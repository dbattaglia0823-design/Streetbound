"""Build an isolated production map for the main-scene smoke test in CI."""
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from publish_custom_world import publish
from custom_test_world_bake_test import source

runtime=ROOT/".runtime"
runtime.mkdir(exist_ok=True)
doc=source()
doc["name"]="Published CI District"
doc["markers"][0]["name"]="City Spawn"
doc["races"][0]["first_win_reward_cash"]=1250
doc["races"][0].update({
    "multiplayer_reward_custom":True,
    "multiplayer_reward_cash":8600,
    "multiplayer_reward_player_xp":2600,
    "multiplayer_reward_car_xp":1300,
    "multiplayer_reward_part_chance":100,
})
src=runtime/"published-ci.world.json"
src.write_text(json.dumps(doc,indent=2),encoding="utf-8")
info=publish(src,ROOT,runtime/"publication-backups")
print(json.dumps(info,sort_keys=True))
