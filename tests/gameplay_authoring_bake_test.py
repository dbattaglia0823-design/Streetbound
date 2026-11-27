"""Focused gameplay validation and intersection bake regressions."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from gameplay_authoring import validate,apply

def rejects(fn):
    try:fn()
    except ValueError:return
    raise AssertionError("Invalid authoring was accepted")

z=dict(name="District",x=0,y=0,w=100,h=100,density=50,speed=30,patrol=0,response=100,models="commercial")
c=dict(x=40,y=50,layer=1,control="signal",turns=["straight"])
zones,controls=validate(dict(gameplayZones=[z],junctionControls=[c]),600,600)
assert zones==[z] and controls==[c]
rejects(lambda:validate(dict(gameplayZones=[dict(z,w=601)]),600,600))
junctions=[dict(p=[40,50],road_layer=0,control="priority",approaches=[{} for _ in range(3)]),
           dict(p=[40,50],road_layer=1,control="priority",approaches=[{} for _ in range(3)])]
apply(junctions,controls)
assert junctions[0]["control"]=="priority"
assert junctions[1]["control"]=="signal"
assert junctions[1]["allowed_turns"]==["straight"]
assert [a["signal_slot"] for a in junctions[1]["approaches"]]==[0,1,2]
rejects(lambda:apply(junctions,[dict(c,layer=-1)]))
rejects(lambda:apply(junctions,[c,c]))
j2=[dict(p=[40,50],road_layer=1,control="priority",approaches=[{} for _ in range(3)])]
apply(j2,[c,dict(c,approach=1,lane=-1,control="yield",turns=["right"]),dict(c,approach=1,lane=0,turns=["straight"])])
assert j2[0]["approaches"][1]["control"]=="yield"
assert j2[0]["approaches"][1]["allowed_turns"]==["right"]
assert j2[0]["approaches"][1]["lane_turns"]=={"0":["straight"]}
print("GAMEPLAY AUTHORING BAKE: PASS")
