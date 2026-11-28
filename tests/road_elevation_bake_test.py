"""Compile the same fixture used by the editor and Godot lane-graph tests."""
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT / "tools"))
from build_custom_test_world import make_archive, scenery_rebuild, geometry_cache_key


def fixture():
    return json.loads((ROOT / "tests/fixtures/road-elevation.world.json").read_text(encoding="utf-8"))


class ElevationBakeTests(unittest.TestCase):
    def test_lane_transition_is_uncontrolled_even_with_equal_width(self):
        source=fixture()
        a,b=copy.deepcopy(source["roads"][0]),copy.deepcopy(source["roads"][0])
        a.update(id="road-0",name="Wide",roadClass="highway",lanes=6,width=18,points=[{"x":100,"y":400},{"x":500,"y":400}])
        b.update(id="road-1",name="Narrow",roadClass="highway",lanes=2,width=18,points=[{"x":900,"y":400},{"x":500,"y":400}])
        source["roads"]=[a,b]
        archive=make_archive(source)
        j,=[j for j in archive["junctions"] if j["kind"]=="lane_transition"]
        self.assertEqual(j["control"],"lane_transition")
        self.assertEqual(len(j["approaches"]),2)
        self.assertTrue(all(arm["control"]=="none" for arm in j["approaches"]))
        self.assertTrue(all(arm["setback"]>=30 for arm in j["approaches"]))
        self.assertEqual(j.get("signal_count",0),0)

    def test_street_entrance_stops_only_minor_road_and_has_tight_mouths(self):
        source=fixture()
        a,b=copy.deepcopy(source["roads"][0]),copy.deepcopy(source["roads"][0])
        a.update(id="road-0",name="Main",roadClass="city",lanes=4,width=20,points=[{"x":100,"y":400},{"x":900,"y":400}])
        b.update(id="road-1",name="Side",roadClass="street",lanes=2,width=8,points=[{"x":500,"y":400},{"x":500,"y":650}])
        source["roads"]=[a,b]
        for road in source["roads"]:road.pop("elevation",None)
        archive=make_archive(source)
        j,=archive["junctions"]
        self.assertTrue(j["street_access"])
        self.assertEqual(j["corner_style"],"square")
        self.assertEqual(j["control"],"priority")
        self.assertEqual([arm["control"] for arm in j["approaches"] if arm["road"]==0],["none","none"])
        self.assertEqual([arm["control"] for arm in j["approaches"] if arm["road"]==1],["stop"])
        self.assertTrue(all(arm["setback"]<=6 for arm in j["approaches"] if arm["road"]==0))
        self.assertIn((0,1),{tuple(pair) for pair in archive["road_connections"]})
        # Legacy service still loads and follows the same rule.
        b["roadClass"]="service"
        self.assertEqual(make_archive(source)["junctions"],archive["junctions"])

    def test_square_intersections_are_optional_and_endpoint_local(self):
        source=fixture()
        a,b=copy.deepcopy(source["roads"][0]),copy.deepcopy(source["roads"][0])
        a.update(id="road-0",name="Main",roadClass="city",width=20,points=[{"x":100,"y":400},{"x":900,"y":400}])
        b.update(id="road-1",name="Branch",roadClass="city",width=10,points=[{"x":500,"y":400},{"x":500,"y":650}])
        source["roads"]=[a,b]
        for road in source["roads"]:road.pop("elevation",None)
        rounded,=make_archive(source)["junctions"]
        b["junctionStart"]="square"
        square,=make_archive(source)["junctions"]
        self.assertEqual(square["corner_style"],"square")
        self.assertLess(len(square["polygon"]),len(rounded["polygon"]))
        self.assertEqual(square["control"],rounded["control"])
        b.pop("junctionStart")
        b["junctionStyle"]="square"
        self.assertEqual(make_archive(source)["junctions"],[square])

    def test_named_editor_layers_never_hide_game_geometry(self):
        source=fixture()
        expected=make_archive(source)
        source["editorLayers"]=[{"name":"Hidden deck","ids":["road-1"],"visible":False,"locked":True}]
        self.assertEqual(make_archive(source),expected)

    def test_authored_height_field_bake_and_cache_invalidation(self):
        source=fixture()
        base=geometry_cache_key(source)
        field={"size":129,"values":[0.0]*(129*129)}
        field["values"][64*129+64]=123.5
        source["terrainHeight"]=field
        self.assertEqual(make_archive(source)["terrainHeight"],field)
        self.assertNotEqual(geometry_cache_key(source),base)
        field["values"][0]=1201
        with self.assertRaisesRegex(ValueError,"terrain height field"):
            make_archive(source)

    def test_stacked_roads_share_coordinates_without_connections(self):
        archive = make_archive(fixture())
        connections = {tuple(pair) for pair in archive["road_connections"]}
        for pair in [(0,1),(0,2),(1,2),(1,8),(2,4),(2,8),(3,9)]:
            self.assertNotIn(pair,connections)
        self.assertTrue({(0,6),(1,3),(1,4),(2,7),(4,5)} <= connections)
        self.assertNotIn("elevation",archive["roads"][0])
        self.assertEqual(archive["roads"][4]["elevation"],{"start_layer":1,"end_layer":0})
        stacked = [j for j in archive["junctions"] if j["p"] == [500,450]]
        self.assertEqual([(j["road_layer"],j["roads"]) for j in stacked],[(1,[1,3])])

    def test_two_way_portal_ramp_keeps_tunnel_connection(self):
        source=fixture()
        source["roads"][7].update(roadClass="onramp",lanes=2)
        archive=make_archive(source)
        self.assertEqual(archive["roads"][7]["lanes"],2)
        self.assertIn((2,7),{tuple(pair) for pair in archive["road_connections"]})
        self.assertFalse(any(j["control"]=="merge" and j.get("ramp_road")==7 for j in archive["junctions"]))

    def test_directional_merge_does_not_connect_to_overlapping_deck(self):
        source = fixture()
        ground = copy.deepcopy(source["roads"][0])
        deck = copy.deepcopy(source["roads"][1])
        deck["points"] = [{"x":700,"y":250},{"x":700,"y":600}]
        ramp = copy.deepcopy(ground)
        ramp.update(id="road-2", name="Directional Ramp", roadClass="onramp",
                    lanes=1, width=8, points=[{"x":520,"y":480},{"x":700,"y":400}])
        source["roads"] = [ground,deck,ramp]
        archive = make_archive(source)
        merges = [j for j in archive["junctions"] if j["control"] == "merge"]
        self.assertEqual(len(merges),1)
        self.assertEqual(merges[0]["ramp_road"],2)
        self.assertEqual(merges[0]["main_road"],0)
        self.assertEqual(merges[0].get("road_layer",0),0)
        self.assertEqual(set(merges[0]["roads"]),{0,2})
        connections = {tuple(pair) for pair in archive["road_connections"]}
        self.assertNotIn((0,1),connections)
        self.assertNotIn((1,2),connections)

    def test_elevated_merge_retains_direction_and_layer(self):
        source = fixture()
        ground = copy.deepcopy(source["roads"][0])
        deck = copy.deepcopy(ground)
        deck.update(id="road-1", name="Elevated Highway", roadClass="highway",
                    width=16, lanes=4, elevation={"start_layer":1,"end_layer":1})
        ramp = copy.deepcopy(deck)
        ramp.update(id="road-2", name="Elevated Merge Ramp", roadClass="onramp",
                    width=8, lanes=1, points=[{"x":520,"y":480},{"x":700,"y":400}])
        source["roads"] = [ground,deck,ramp]
        archive = make_archive(source)
        merges = [j for j in archive["junctions"] if j["control"] == "merge"]
        self.assertEqual(len(merges),1)
        self.assertEqual(merges[0]["road_layer"],1)
        self.assertEqual(merges[0]["main_road"],1)
        self.assertEqual(merges[0]["ramp_road"],2)
        self.assertEqual(merges[0]["merge_side"],1)
        self.assertEqual(set(merges[0]["roads"]),{1,2})
        connections = {tuple(pair) for pair in archive["road_connections"]}
        self.assertNotIn((0,2),connections)

    def test_ground_legacy_and_explicit_ground_compile_identically(self):
        source = fixture()
        for road in source["roads"]:
            road.pop("elevation",None)
        explicit = copy.deepcopy(source)
        explicit["roads"][0]["elevation"] = {"start_layer":0,"end_layer":0}
        self.assertEqual(make_archive(source),make_archive(explicit))

    def test_shallow_grade_separation_is_rejected(self):
        source = fixture()
        cross = copy.deepcopy(source["roads"][5])
        cross["points"] = [{"x": 340, "y": 685}, {"x": 650, "y": 685}]
        cross["name"] = "Crossing Across Ramp"
        source["roads"].append(cross)
        with self.assertRaisesRegex(ValueError,"Crossing Across Ramp.*4.5 m vertical clearance"):
            make_archive(source)

    def test_open_cut_rejects_water_but_covered_tunnel_keeps_roof(self):
        source = fixture()
        lake = dict(id="region-lake",name="Portal lake",biome="lake",elevation=0,
                    points=[{"x":480,"y":190},{"x":520,"y":190},
                            {"x":520,"y":230},{"x":480,"y":230}])
        source["regions"].append(lake)
        with self.assertRaisesRegex(ValueError,"open terrain cut intersects water"):
            make_archive(source)
        lake["points"] = [{"x":480,"y":300},{"x":520,"y":300},
                          {"x":520,"y":345},{"x":480,"y":345}]
        archive = make_archive(source)
        self.assertEqual(archive["roads"][2]["elevation"],{"start_layer":-1,"end_layer":-1})

    def test_objective_layers_survive_bake_and_invalid_layers_fail(self):
        source = fixture()
        source["races"] = [dict(id="race-grade",name="Grade trial",mode="sprint",
                                points=[dict(x=500,y=400,road_layer=1),
                                        dict(x=500,y=450,road_layer=-1)])]
        source["markers"].extend([
            dict(id="marker-grade-drop",type="contract_dropoff",name="Tunnel drop",
                 x=500,y=400,rotation=0,properties={"road_layer":-1}),
            dict(id="marker-grade-pickup",type="contract",name="Bridge pickup",
                 x=500,y=550,rotation=0,properties={"road_layer":1,
                    "contract_kind":"courier","destination_marker_id":"marker-grade-drop"})])
        archive = make_archive(source)
        self.assertEqual([p["road_layer"] for p in archive["editor_races"][0]["points"]],[1,-1])
        self.assertEqual([m["properties"]["road_layer"] for m in archive["editor_game_markers"] if m["id"].startswith("marker-grade")],[-1,1])
        bad=copy.deepcopy(source)
        bad["races"][0]["points"][0]["road_layer"]=True
        with self.assertRaisesRegex(ValueError,"checkpoint road layer"):
            make_archive(bad)
        bad=copy.deepcopy(source)
        bad["markers"][-1]["properties"]["road_layer"]=3
        with self.assertRaisesRegex(ValueError,"marker road layer"):
            make_archive(bad)

    def test_persistent_profile_bakes_continuous_smoothed_sections(self):
        source=fixture()
        road=copy.deepcopy(source["roads"][0])
        road.update(points=[{"x":100,"y":700},{"x":200,"y":700},{"x":300,"y":700},
                            {"x":400,"y":700},{"x":500,"y":700},{"x":600,"y":700}],
                    elevation={"start_layer":0,"end_layer":-1,"point_layers":[0,1,1,0,-1,-1]})
        source["roads"]=[road]
        before=copy.deepcopy(source)
        archive=make_archive(source)
        self.assertEqual(source,before)
        sections=archive["roads"]
        self.assertEqual(len(sections),5)
        self.assertEqual(sections[0]["editor_grade_source"]["elevation"],road["elevation"])
        self.assertTrue(all(r["editor_grade_source_id"]==0 for r in sections))
        for a,b in zip(sections,sections[1:]):
            self.assertEqual(a["points"][-1],b["points"][0])
            self.assertEqual(a["end"],b["start"])
        for r in sections:
            if r.get("grade_smooth") is not None:self.assertAlmostEqual(r["grade_smooth"],1.0)

    def test_incremental_scenery_bake_matches_clean_build(self):
        doc=fixture()
        initial=make_archive(doc)
        changed=copy.deepcopy(doc)
        changed["props"].append(dict(id="prop-incremental-tree",name="Tree",type="oak",
                                     x=120,y=120,scale=1,rotation=0,assetId="game-tree"))
        self.assertEqual(geometry_cache_key(doc),geometry_cache_key(changed))
        self.assertEqual(scenery_rebuild(copy.deepcopy(initial),changed),make_archive(changed))
        moved=copy.deepcopy(changed)
        moved["props"][-1]["x"]=850
        self.assertEqual(scenery_rebuild(make_archive(changed),moved),make_archive(moved))
        moved["roads"][0]["points"][0]["x"]+=5
        self.assertNotEqual(geometry_cache_key(moved),geometry_cache_key(changed))

    def test_expanded_custom_map_capacity(self):
        source=fixture()
        source["world"].update(width=6400,height=4800)
        template=copy.deepcopy(source["roads"][0])
        template.pop("elevation",None)
        source.update(roads=[],regions=[],props=[],markers=[],races=[])
        for i in range(360):
            x=100+(i%20)*280
            y=100+(i//20)*220
            road=copy.deepcopy(template)
            road.update(id=f"road-{i}",name=f"Capacity road {i}",points=[dict(x=x,y=y),dict(x=x+90,y=y)])
            source["roads"].append(road)
        for i in range(8000):
            source["props"].append(dict(id=f"prop-{i}",name="Capacity tree",type="oak",
                x=50+(i%100)*60,y=50+(i//100)*58,scale=1,rotation=0,assetId="game-tree"))
        archive=make_archive(source)
        self.assertEqual(len(archive["roads"]),360)
        self.assertEqual(len(archive["props"]),8000)
        source["roads"].append(copy.deepcopy(source["roads"][0]))
        with self.assertRaisesRegex(ValueError,"road list"):
            make_archive(source)

    def test_bad_profiles_fail_before_archive_output(self):
        source = fixture()
        for profile in [None, {"start_layer":True,"end_layer":1},
                        {"start_layer":0,"end_layer":2}, {"start_layer":2.1,"end_layer":2}]:
            with self.subTest(profile=profile):
                source["roads"][1]["elevation"] = profile
                with self.assertRaises(ValueError):
                    make_archive(source)
        source = fixture()
        source["roads"][4]["points"][-1]["y"] = 640
        with self.assertRaisesRegex(ValueError,"at least 50 m"):
            make_archive(source)


if __name__ == "__main__":
    unittest.main()
