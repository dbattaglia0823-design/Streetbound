"""Deterministic city-scale grade bake fixture and structural benchmark."""
import argparse,copy,json,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from build_custom_test_world import make_archive

def source():
    doc=json.loads((ROOT/"tests/fixtures/road-elevation.world.json").read_text())
    doc["name"]="Elevation City Stress"
    doc["world"].update(width=6400,height=4800,base="grass")
    template=doc["roads"][0]
    doc.update(roads=[],regions=[],props=[],markers=[],races=[],assets=[])
    def add(name,points,profile=None,highway=False):
        road=copy.deepcopy(template)
        road.update(id=f"road-{len(doc['roads'])}",name=name,points=[dict(x=x,y=y) for x,y in points],
                    roadClass="highway" if highway else "city",width=16 if highway else 12,lanes=4 if highway else 2)
        road.pop("elevation",None)
        if profile is not None:road["elevation"]=dict(start_layer=profile[0],end_layer=profile[-1],point_layers=profile)
        doc["roads"].append(road)
    rows=[100]+list(range(400,4301,150))+[4600]
    for i,y in enumerate(rows):add(f"Cross street {i}",[(100,y),(6300,y)])
    for i in range(28):
        x=200+200*i
        add(f"City avenue {i}",[(x,100),(x,4600)])
    for i in range(24):
        x=300+200*i
        level=1 if i<12 else -1
        add(f"Grade highway {i}",[(x,100),(x,275),(x,4400),(x,4600)],[0,level,level,0],True)
    doc["markers"]=[dict(id="marker-0",name="City start",type="player_spawn",x=300,y=850,rotation=90,properties={})]
    doc["races"]=[dict(id="race-grade",name="Bridge to tunnel",mode="sprint",points=[dict(x=300,y=850,road_layer=1),dict(x=2700,y=850,road_layer=-1)])]
    return doc

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--output",required=True,type=Path)
    args=ap.parse_args()
    original=source()
    start=time.perf_counter()
    archive=make_archive(original)
    elapsed=time.perf_counter()-start
    roads=archive["roads"]
    assert len(roads)==len(original["roads"])+48,(len(roads),len(original["roads"]))
    assert len(archive["junctions"])>=700,len(archive["junctions"])
    assert not archive["editor_warnings"],archive["editor_warnings"]
    assert len(archive["surface_index"])>500
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(archive,separators=(",",":")))
    print(json.dumps(dict(authored_roads=len(original["roads"]),runtime_roads=len(roads),junctions=len(archive["junctions"]),
          segments=len(archive["segments"]),chunks=len(archive["chunks"]),bake_seconds=round(elapsed,3),
          archive_bytes=args.output.stat().st_size)))
    print("ELEVATION CITY BAKE: PASS")

if __name__=="__main__":main()
