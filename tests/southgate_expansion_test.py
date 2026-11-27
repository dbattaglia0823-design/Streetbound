"""Validate the separate draft; never overwrite the shipped world."""
import json
import sys
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from authored_races import authored_races
from authored_markers import validate_markers
from morrow_editor_import import validate_world_bounds, _authoring_props

class Southgate(unittest.TestCase):
    def test_preserves_original_and_validates_new_content(self):
        directory=ROOT/"map-editor/maps"
        stock=json.loads((directory/"morrow-coast.edits.world.json").read_text())
        draft=json.loads((directory/"morrow-coast.southgate-draft.world.json").read_text())
        width,height=validate_world_bounds(draft["world"]["width"],draft["world"]["height"])
        self.assertEqual(draft["roads"][:len(stock["roads"])],stock["roads"])
        self.assertEqual(draft["regions"][:len(stock["regions"])],stock["regions"])
        self.assertEqual(draft["markers"][:len(stock["markers"])],stock["markers"])
        self.assertEqual(height,6400)
        self.assertEqual(len(draft["roads"])-len(stock["roads"]),16)
        self.assertEqual(len({r["id"] for r in draft["roads"]}),len(draft["roads"]))
        races=authored_races(draft,width,height)
        self.assertEqual(len(races),3)
        markers=validate_markers(draft["markers"],races,[],width,height)
        self.assertTrue(any(m["type"]=="home" for m in markers))
        self.assertTrue(any(m["type"]=="contract_contact" for m in markers))
        self.assertTrue(any(m["type"]=="robbery_target" for m in markers))
        coast=next(r for r in stock["roads"] if r["name"]=="South Coastal Link")
        parkway=next(r for r in draft["roads"] if r["name"]=="South Morrow Parkway")
        self.assertEqual(parkway["points"][-1],coast["points"][0])
        self.assertGreater(len(_authoring_props(draft,width,height)),50)

if __name__=="__main__":unittest.main()
