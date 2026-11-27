"""Custom Test Drive uses the production junction baker without touching Morrow Coast."""
import json
import pathlib
import sys
import tempfile
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from build_custom_test_world import make_archive,build_file


def source():
    return {
        "format":"gdt.racing-world","version":2,"customMap":True,
        "name":"Test Junctions","world":{"width":1200,"height":1000,"base":"grass","seed":1847},
        "roads":[
            {"id":"road-0","name":"East West","roadClass":"city","surface":"asphalt",
             "width":12,"lanes":2,"points":[{"x":100,"y":500},{"x":1100,"y":500}]},
            {"id":"road-1","name":"North South","roadClass":"city","surface":"asphalt",
             "width":12,"lanes":2,"points":[{"x":500,"y":120},{"x":500,"y":880}]},
            {"id":"road-2","name":"T road","roadClass":"city","surface":"asphalt",
             "width":10,"lanes":2,"points":[{"x":900,"y":500},{"x":900,"y":790}]}],
        "regions":[{"id":"region-0","biome":"lake",
                    "points":[{"x":250,"y":220},{"x":360,"y":220},
                              {"x":360,"y":340},{"x":250,"y":340}]}],
        "props":[{"id":"prop-test-house","type":"house","name":"Test Home",
                  "x":220,"y":240,"scale":1.0,"rotation":0.0}],
        "markers":[{"id":"marker-0","type":"player_spawn","x":160,"y":500,"rotation":90.0}],
        "assets":[],
        "races":[{"id":"race-0","name":"City Sprint","mode":"sprint","laps":1,
                  "points":[{"x":160,"y":500},{"x":500,"y":500}],
                  "enemy_starts":[]}]}


class CustomTestWorldBaker(unittest.TestCase):
    def test_alleyway_bakes_as_connected_paved_road(self):
        doc=source()
        doc['roads'][2].update(roadClass='alley',width=6,lanes=1,shoulder=0,markings=False)
        archive=make_archive(doc)
        alley=archive['roads'][2]
        self.assertEqual(alley['kind'],'alley')
        self.assertEqual(alley['surface'],'ASPHALT')
        self.assertEqual(alley['lanes'],1)
        self.assertTrue(any(2 in j['roads'] for j in archive['junctions']))
        self.assertTrue(any(s['road']==2 for s in archive['segments']))

    def test_explicit_onramp_bakes_yield_merge(self):
        doc=source()
        doc['roads'][0].update(roadClass='highway',width=16,lanes=4)
        doc['roads'][2].update(roadClass='onramp',width=8,lanes=1,
                              points=[{'x':720,'y':570},{'x':900,'y':500}])
        archive=make_archive(doc)
        self.assertEqual(archive['roads'][2]['kind'],'onramp')
        merge=next(j for j in archive['junctions'] if j.get('kind')=='merge')
        self.assertEqual((merge['ramp_road'],merge['main_road'],merge['merge_side']),(2,0,1))
        self.assertEqual([a['control'] for a in merge['approaches'] if a['road']==2],['yield'])
        self.assertTrue(all(a['control']=='none' for a in merge['approaches'] if a['road']==0))
        self.assertTrue(any(j['kind']=='crossroads' for j in archive['junctions']))
        doc['roads'][2]['points'][0]={'x':900,'y':650}
        with self.assertRaisesRegex(ValueError,'On-ramp'):
            make_archive(doc)
        doc['roads'][2]['points'][0]={'x':720,'y':430}
        with self.assertRaisesRegex(ValueError,'On-ramp'):
            make_archive(doc)

    def test_existing_branch_connection_can_hot_swap_without_geometry_changes(self):
        doc=source()
        branch=doc['roads'][2]
        before=make_archive(doc)
        branch['junctionStart']='merge'
        merged=make_archive(doc)
        target=next(j for j in merged['junctions'] if j['kind']=='merge')
        self.assertEqual(target['ramp_road'],2)
        self.assertEqual(target['ramp_side'],1)
        self.assertEqual(merged['roads'][2]['points'],before['roads'][2]['points'])
        self.assertEqual(merged['roads'][2]['lanes'],before['roads'][2]['lanes'])
        self.assertEqual(merged['roads'][2]['kind'],before['roads'][2]['kind'])
        branch['junctionStart']='intersection'
        restored=make_archive(doc)
        self.assertFalse(any(j['kind']=='merge' for j in restored['junctions']))
        self.assertEqual(restored['roads'][2]['points'],before['roads'][2]['points'])

    def test_full_junction_geometry_and_routing(self):
        archive=make_archive(source())
        self.assertEqual(archive["format"],"streetbound.streamed-world")
        self.assertTrue(archive["editor_custom_test_drive"])
        self.assertEqual(len(archive["roads"]),3)
        self.assertGreater(len(archive["segments"]),3)
        self.assertGreaterEqual(len(archive["junctions"]),2)
        self.assertTrue(any(j["control"]!="none" for j in archive["junctions"]))
        self.assertTrue(any(j.get("polygon") and j.get("approaches") for j in archive["junctions"]))
        self.assertTrue(any(r["marking_gaps"] for r in archive["roads"]))
        self.assertTrue(archive["road_connections"])
        self.assertEqual(len(archive["editor_races"]),1)
        self.assertEqual(len(archive["props"]),1)
        self.assertEqual(archive["spawn"]["position"],[160,500])
        self.assertEqual(len(archive["terrain"]),2)
        self.assertTrue(archive["chunks"])
        for cell in archive["chunks"].values():
            for field,kind in (("junctions","junctions"),("segments","segments"),("props","props")):
                self.assertTrue(all(0<=i<len(archive[kind]) for i in cell[field]))

    def test_career_and_gameplay_marker_data_survive_production_bake(self):
        doc=source()
        race=doc["races"][0]
        race.update(category="challenge",difficulty="pro",repeatable=False,
                    required_player_level=8,required_car_level=4,
                    prerequisite_races=[],required_vehicle_ids=["audi-rs3"],
                    first_win_reward_cash=2000,first_win_reward_player_xp=1000)
        doc["markers"].append({
            "id":"marker-1","name":"Street Mission","type":"mission","x":160,"y":500,
            "rotation":0,"properties":{"race_id":"race-0","radius_m":10}})
        doc["markers"].append({
            "id":"marker-2","name":"Downtown Travel","type":"fast_travel","x":500,"y":500,
            "rotation":0,"properties":{"required_race":"race-0"}})
        doc["markers"].append({
            "id":"marker-3","name":"Traffic","type":"traffic_spawn","x":500,"y":500,
            "rotation":0,"properties":{"traffic_weight":8}})
        compiled=make_archive(doc)
        self.assertEqual(compiled["editor_races"][0]["first_win_reward_cash"],2000)
        self.assertFalse(compiled["editor_races"][0]["repeatable"])
        self.assertEqual(compiled["editor_game_markers"],doc["markers"])
        self.assertEqual(len(compiled["editor_game_markers"]),4)
        broken=source()
        broken["markers"].append({"id":"marker-2","name":"Invalid","type":"mission",
            "x":500,"y":500,"properties":{"race_id":"race-404"}})
        with self.assertRaises(ValueError):make_archive(broken)

    def test_contracts_and_underground_race_survive_playtest_bake(self):
        doc=source()
        doc['races'][0].update(race_heat=3,escape_time_limit=90,entry_fee=2000,
                                underground_rep_reward=6,required_underground_rep=2)
        doc['markers'] += [
            {'id':'marker-contact','type':'contract_contact','name':'Fixer','x':160,'y':500,
             'properties':{'contact_style':'racing','offers':[{'id':'job_1','title':'Getaway',
                'kind':'robbery','required_race_id':'race-0','destination_marker_id':'marker-drop',
                'robbery_marker_id':'marker-target','arrival_radius_m':18,'robbery_hold_seconds':12}]}},
            {'id':'marker-target','type':'robbery_target','name':'Target','x':500,'y':500},
            {'id':'marker-drop','type':'contract_dropoff','name':'Drop','x':800,'y':500}]
        data=make_archive(doc)
        self.assertEqual(data['editor_races'][0]['race_heat'],3)
        self.assertEqual(data['editor_races'][0]['entry_fee'],2000)
        self.assertEqual(data['editor_races'][0]['escape_time_limit'],90)
        self.assertEqual(data['editor_game_markers'],doc['markers'])
        doc['markers'][1]['properties']['offers'][0]['robbery_marker_id']='missing'
        with self.assertRaises(ValueError):make_archive(doc)

    def test_empty_map_remains_drivable_and_has_terrain_chunks(self):
        doc=source()
        doc["roads"]=[]
        doc["props"]=[]
        doc["regions"]=[]
        doc["markers"]=[]
        doc["races"]=[]
        data=make_archive(doc)
        self.assertFalse(data["segments"])
        self.assertFalse(data["junctions"])
        self.assertFalse(data["props"])
        self.assertEqual(data["spawn"]["position"],[600.0,500.0])
        self.assertGreater(len(data["chunks"]),0)
        # Every edge segment must be assigned to a resident chunk in its
        # immediate area; a single midpoint wall would lose collision when
        # the player drives toward distant corners.
        self.assertGreater(len(data["walls"]),4)
        self.assertTrue(all(0<=i<len(data["walls"]) for cell in data["chunks"].values()
                            for i in cell["walls"]))
        assigned={i for cell in data["chunks"].values() for i in cell["walls"]}
        self.assertEqual(len(assigned),len(data["walls"]))

    def test_isolated_atomic_temp_archive(self):
        doc=source()
        with tempfile.TemporaryDirectory() as temp:
            base=pathlib.Path(temp)
            src=base/"authoring.world.json"
            output=base/"temporary.stream.json"
            src.write_text(json.dumps(doc),encoding="utf-8")
            shipped=ROOT/"worlds"/"morrow-coast.world.json"
            before=(shipped.stat().st_size,shipped.stat().st_mtime_ns)
            baked=build_file(src,output)
            self.assertTrue(output.is_file())
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")),baked)
            self.assertEqual((shipped.stat().st_size,shipped.stat().st_mtime_ns),before)
            self.assertFalse(output.with_suffix(output.suffix+".tmp").exists())

    def test_gameplay_edits_reuse_geometry(self):
        from unittest.mock import patch
        doc=source()
        with tempfile.TemporaryDirectory() as temp:
            base=pathlib.Path(temp)
            src=base/"authoring.world.json"
            output=base/"temporary.stream.json"
            cache=base/"geometry.json"
            src.write_text(json.dumps(doc),encoding="utf-8")
            build_file(src,output,cache)
            doc["markers"][0]["x"]=180
            doc["races"][0]["name"]="Updated Sprint"
            doc["rain_intensity"]=0.25
            src.write_text(json.dumps(doc),encoding="utf-8")
            expected=make_archive(dict(doc,_source_filename=src.name))
            with patch("build_custom_test_world.make_archive",side_effect=AssertionError("Unexpected full geometry bake")):
                actual=build_file(src,output,cache)
            self.assertEqual(actual,expected)

    def test_rejects_wrong_source_and_nonintegral_dimensions(self):
        doc=source()
        doc["customMap"]=False
        with self.assertRaises(ValueError):make_archive(doc)
        doc=source()
        doc["world"]["width"]=1200.5
        with self.assertRaises(ValueError):make_archive(doc)


if __name__=="__main__":
    unittest.main()
