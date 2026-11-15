"""Curated regions for the six supplied, irregularly packed map-art sheets.

Only writes metadata beside the source PNGs; pixels and transparency stay intact.
Coordinates are source pixels. Size is the longest footprint dimension in metres.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / 'assets/Map Building Assets/Sprite Sheets'


def sprite(name, rect, length, kind='industrial_prop', collision='solid'):
    x, y, w, h = rect
    return dict(name=name, region=[x, y, w, h], type=kind, collision=collision,
                worldSize=[round(w/max(w, h)*length, 3), round(h/max(w, h)*length, 3)])


SHEETS = {}
items = []
def add(name, rect, length, kind='industrial_prop', collision='solid'):
    items.append(sprite(name, rect, length, kind, collision))

# Industrial cargo and yard equipment.
for name, rect, length in [
    ('Wooden pallet upright',(24,28,157,170),1.2),('Wooden pallet sideways',(201,31,156,168),1.2),
    ('Stacked wooden pallets',(371,7,165,193),1.4),('Wrapped cardboard pallet',(549,21,177,181),1.4),
    ('White wrapped pallet',(738,22,172,180),1.4),('Cardboard box pallet',(921,10,160,193),1.4),
    ('Tall wooden crate',(1095,35,139,168),1.5),('Large wooden crate',(1254,21,147,182),1.7),
    ('Small wooden crate',(1414,53,108,133),1.1),('Open wooden crate',(23,229,155,150),1.3),
    ('Slatted wooden crate',(191,233,145,145),1.3),('Strapped box pallet',(355,215,161,169),1.4),
    ('White strapped bale',(530,219,169,162),1.4),('Blue tarp pallet',(706,217,176,162),1.5),
    ('Green cases pallet',(891,226,154,153),1.4),('Grey cases pallet',(1060,231,141,148),1.4),
    ('Pipe crate',(1210,233,167,146),1.6),('Sealed green cargo case',(1378,236,141,129),1.1),
    ('Green dumpster closed',(18,391,217,173),2.5),('Blue dumpster closed',(246,396,208,169),2.5),
    ('Black dumpster closed',(462,396,203,169),2.5),('Yellow skip empty',(677,395,267,169),4),
    ('Rust skip with rubbish',(949,394,268,170),4),('Blue skip with rubble',(1221,393,302,173),4.5),
    ('Blue steel drum',(620,580,80,132),.9),('Red steel drum',(707,579,83,133),.9),
    ('Green steel drum',(795,579,85,133),.9),('Yellow steel drum',(884,579,86,133),.9),
    ('Red drum group',(989,570,150,148),1.5),('Blue drum group',(1154,570,157,148),1.5),
    ('Yellow drum group',(1326,570,186,149),1.7),('Cable reel large',(8,711,171,172),1.6),
    ('Orange cable reel',(185,712,153,169),1.5),('Cable reel small',(337,731,100,143),1),
    ('Red cable reel small',(438,735,90,138),1),('Two steel pipes',(550,744,191,116),2.3),
    ('Strapped steel pipes',(768,737,240,130),3),('Steel section bundle',(1026,735,209,127),3),
    ('Rust steel beam stack',(1245,735,278,132),4),('Yellow forklift',(17,878,335,143),4),
    ('Hollow concrete block pallet',(377,879,141,137),1.4),('Concrete paving pallet',(535,880,161,136),1.5),
    ('Red brick pallet',(705,877,137,141),1.3),('Cement bag pallet',(848,881,139,137),1.3),
    ('Timber bundle',(1001,891,257,126),3.5),('Rust rebar bundle',(1265,889,253,128),3.5),
]: add(name,rect,length)
for name,x,w in [('Green wheelie bin',25,103),('Blue recycling wheelie bin',146,103),('Grey wheelie bin',267,99),('Yellow wheelie bin',379,107),('Red wheelie bin',494,101)]:add(name,(x,573,w,135),1.1)
SHEETS['Industrial Warehouse Props Asset Sheet-1']=items

# Road works, utilities, street furniture and markings.
items=[]
for name,rect,length in [
    ('Traffic cone small',(22,53,107,124),.65),('Traffic cone tall',(145,12,109,166),.9),
    ('Traffic drum',(267,10,128,167),1),('Traffic drum with beacon',(407,10,83,167),1),
    ('Road barricade wide',(519,26,187,158),2.4),('Road barricade with beacons',(724,9,192,175),2.4),
    ('Road barricade narrow',(938,27,109,157),1),('Concrete barrier plain',(1066,35,239,139),2.5),
    ('Concrete barrier yellow',(1313,32,214,144),2.5),('Mobile arrow sign',(25,195,242,191),4.2),
    ('Roadworks warning sign',(273,198,137,187),1.3),('Narrow road warning sign',(419,198,134,187),1.3),
    ('Two way traffic warning sign',(559,198,140,187),1.3),('Bend right warning sign',(701,198,138,187),1.3),
    ('Narrow barricade with beacon',(850,198,98,190),1.3),('Orange delineator post',(967,204,77,184),1.2),
    ('Red concrete barrier left',(1065,239,246,116),2.5),('Red concrete barrier right',(1325,239,202,116),2.5),
    ('Utility pole dual transformers',(1,401,295,218),3.5),('Utility pole single transformer',(299,401,225,217),3),
    ('Utility pole streetlight arm',(528,403,232,216),4),('Green utility cabinet large',(770,436,156,172),2),
    ('Grey utility cabinet large',(944,444,142,163),1.8),('Green utility cabinet small',(1100,468,97,119),1),
    ('Grey electrical box',(1207,444,102,150),1),('Utility cover large',(1320,459,124,135),1.4),
    ('Utility cover narrow',(1443,466,84,127),1),('Bus stop sign',(27,622,77,199),1.1),
    ('Bus shelter',(110,614,426,214),7),('Round litter bin',(563,659,121,135),.9),
    ('Street bench',(680,677,197,103),1.8),('Square street planter',(897,646,115,140),1.3),
    ('Blue newspaper box',(1040,651,82,133),.9),('Red newspaper box',(1126,651,78,133),.9),
    ('Yellow newspaper box',(1205,655,81,131),.9),('Street bicycle rack',(1321,663,200,105),3),
    ('Manhole cover large',(15,892,125,113),1.2),('Manhole cover small',(140,897,104,107),1),
    ('Storm drain long',(254,911,126,90),1),('Storm drain square',(379,911,108,90),.9),
    ('Red fire hydrant',(488,884,91,119),1),('Yellow fire hydrant',(575,884,87,119),1),
    ('Grey fire hydrant',(655,884,81,119),1),('Modern streetlight',(721,807,76,194),1.5),
    ('Globe streetlight',(799,797,70,204),1.4),('Classic streetlight',(866,791,66,210),1.5),
    ('Parking meter left',(939,862,58,141),.7),('Parking meter right',(995,860,55,143),.7),
    ('Striped bollard',(1057,869,58,134),.8),('Yellow bollard',(1112,869,51,134),.8),
    ('Blue post box',(1169,901,78,102),1),('Black post box',(1252,905,84,98),1),
    ('Pedestrian crossing signal walk',(1355,801,79,202),1.2),('Pedestrian crossing signal stop',(1441,800,83,202),1.2),
]:add(name,rect,length,'road_prop','none' if any(word in name for word in ['cover','drain']) else 'solid')
SHEETS['Urban Roadside Infrastructure Sprite Atlas-2']=items

# Service station, shopping, car wash and rooftop equipment.
items=[]
for name,rect,length in [
    ('Fuel island red single',(24,12,205,170),4),('Fuel island blue single',(236,12,194,170),4),
    ('Fuel island red double',(440,12,354,170),7),('Fuel island blue double',(806,12,361,170),7),
    ('Diesel pump island',(1180,14,149,172),2.5),('Propane cylinder cage',(1348,10,168,178),2.5),
    ('Shopping cart shelter',(15,197,333,216),5),('Shopping cart narrow',(362,223,80,169),1.1),
    ('Shopping cart wide',(454,242,91,151),1.1),('Bicycles in rack',(563,221,268,180),3.5),
    ('Yellow parking stop striped',(850,228,167,43),1.8),('Yellow parking stop',(850,282,167,43),1.8),
    ('Concrete parking stop',(850,339,167,43),1.8),('Yellow safety bollard',(1035,271,50,116),.8),
    ('Black safety bollard',(1102,268,49,119),.8),('Steel safety bollard',(1171,266,48,121),.8),
    ('Concrete safety bollard',(1231,268,68,120),.8),('Parking sign',(1321,215,66,181),1),
    ('Accessible parking sign',(1395,215,61,181),1),('Blank parking sign',(1465,215,63,181),1),
    ('Car wash brush bay',(13,423,367,254),9),('Car wash gantry',(400,424,339,253),8),
    ('Car wash payment terminal',(763,491,115,177),1.5),('Dual vacuum island',(897,493,317,178),5),
    ('Drive through menu board',(1233,431,292,254),3),('Rooftop air conditioner double',(12,683,205,135),3),
    ('Rooftop air conditioner single',(232,688,115,130),1.8),('Rooftop HVAC unit',(366,686,187,132),2.5),
    ('Rooftop ventilation elbow',(574,689,185,127),2),('Rooftop extractor fan',(779,699,117,117),1.5),
    ('Rooftop turbine vent',(916,688,110,129),1.4),('Rooftop louvre vent',(1052,696,100,119),1.3),
    ('Skylight square',(1173,689,138,126),2),('Skylight wide',(1332,699,185,116),3),
    ('Red drinks vending machine',(13,836,101,183),1),('Blue drinks vending machine',(117,836,97,183),1),
    ('Snack vending machine',(213,837,100,182),1),('Green round bin',(318,877,81,131),.8),
    ('Square concrete bin',(395,875,68,134),.8),('Blue recycling bin',(468,875,66,134),.8),
    ('Round concrete bin',(536,875,79,134),.8),('Wooden litter bin',(614,873,66,139),.8),
    ('Cafe table red umbrella',(702,826,142,192),2.5),('Cafe table blue umbrella',(849,826,148,192),2.5),
    ('Picnic table rectangular',(1001,877,168,141),2),('Picnic table round',(1174,871,165,147),2),
    ('Long shrub planter',(1341,872,183,146),2.5),
]:add(name,rect,length)
SHEETS['Commercial Service Station Prop Atlas-3']=items

# Construction materials and parked equipment.
items=[]
for name,rect,length in [
    ('Concrete pipe pallet',(33,13,251,247),3),('Concrete pipe upright',(301,21,122,158),1.4),
    ('Concrete pipe horizontal',(291,175,145,88),1.4),('Parked excavator',(455,5,718,263),11),
    ('Portable cement mixer',(1209,18,289,244),2),('Light timber stack',(17,271,376,142),4),
    ('Dark timber stack',(411,277,344,136),4),('Construction rebar stack',(766,277,359,136),4),
    ('Construction steel beam stack',(1136,265,382,148),5),('Portable toilet',(30,406,137,217),1.5),
    ('Temporary fence green screen',(193,436,320,181),3.5),('Temporary fence dark screen',(468,436,314,181),3.5),
    ('Temporary chain link fence',(748,436,337,181),3.5),('Construction hollow block pallet',(1095,430,217,187),2),
    ('Construction paving block pallet',(1321,433,197,184),2),('Scaffold platform',(14,624,422,246),5),
    ('Site office trailer',(481,614,571,255),9),('Construction rubble skip',(1090,642,425,214),5),
    ('Orange construction drum',(9,863,133,155),1),('Construction traffic cone',(137,879,82,139),.8),
    ('Construction delineator',(226,860,66,158),1),('Construction concrete barrier',(304,888,212,116),2.5),
    ('Orange plastic barrier',(511,888,201,116),2.5),('White plastic barrier',(711,888,198,116),2.5),
    ('Gravel pile',(913,861,215,157),3),('Sand pile',(1132,861,202,157),3),('Asphalt rubble pile',(1328,861,205,157),3),
]:add(name,rect,length)
SHEETS['Top-Down Construction Site Asset Sheet-4']=items

# Residential garden and backyard objects.
items=[]
for name,rect,length,kind,collision in [
    ('Swimming pool',(8,15,566,361),12,'ground_decal','none'),
    ('Garden shed',(575,0,285,362),4,'building','solid'),
    ('Patio sofa set',(877,39,342,324),5,'industrial_prop','solid'),
    ('Garden umbrella table',(1249,17,268,363),3,'industrial_prop','solid'),
    ('Wood fence panel',(17,397,427,180),3.5,'industrial_prop','solid'),
    ('Lattice fence panel',(451,397,373,180),3.5,'industrial_prop','solid'),
    ('Garden barbecue',(840,387,268,192),1.5,'industrial_prop','solid'),
    ('Garden picnic table',(1136,391,338,201),2.5,'industrial_prop','solid'),
    ('Garden bin green',(34,608,124,206),1.1,'industrial_prop','solid'),
    ('Garden bin blue',(160,608,125,206),1.1,'industrial_prop','solid'),
    ('Garden bin grey',(286,608,121,206),1.1,'industrial_prop','solid'),
    ('Garden bin small',(410,645,102,166),.8,'industrial_prop','solid'),
    ('Garden bicycle blue',(519,587,150,262),1.8,'industrial_prop','solid'),
    ('Garden bicycle red',(649,586,132,263),1.8,'industrial_prop','solid'),
    ('Children play structure',(800,574,466,361),7,'industrial_prop','solid'),
    ('Playground roundabout',(1261,650,237,193),2.5,'industrial_prop','solid'),
    ('Garden mailbox',(52,816,144,198),1.1,'industrial_prop','solid'),
    ('Hydrangea garden planter',(237,861,209,155),2,'industrial_prop','solid'),
    ('Yellow flower garden planter',(467,871,184,145),1.8,'industrial_prop','solid'),
    ('Lavender garden planter',(665,878,203,138),2,'industrial_prop','solid'),
    ('Garden storage box grey',(1041,874,220,142),1.6,'industrial_prop','solid'),
    ('Garden storage box green',(1274,883,239,133),1.8,'industrial_prop','solid'),
]:add(name,rect,length,kind,collision)
SHEETS['Top-Down Backyard Neighborhood Props-5']=items

# Natural scenery and non-solid surface detail.
items=[]
for name,rect,length,kind in [
    ('Oak tree canopy large',(0,0,322,268),10,'oak'),('Oak tree canopy medium',(322,0,264,264),8,'oak'),
    ('Pink blossom tree canopy',(587,0,242,265),7,'oak'),('Orange autumn tree canopy',(829,0,242,266),8,'oak'),
    ('Red autumn tree canopy',(1069,0,252,266),8,'oak'),('Palm tree canopy',(1322,0,214,267),8,'palm'),
    ('Garden tree round',(1,262,199,153),4,'oak'),('Garden tree green',(200,263,164,152),4,'oak'),
    ('Garden tree yellow',(363,263,135,152),3.5,'oak'),('Dense green shrub',(493,263,195,152),3.5,'bush'),
    ('Purple flowering shrub',(695,264,175,149),2.5,'bush'),('White flowering shrub',(870,264,164,149),2.5,'bush'),
    ('Red flowering shrub',(1034,263,181,150),2.5,'bush'),('Pink flowering shrub',(1215,263,151,150),2.5,'bush'),
    ('Yellow flowering shrub',(1364,263,172,150),2.5,'bush'),
    ('Spiky plant green',(5,411,136,108),1.7,'bush'),('Spiky plant yellow',(141,411,142,108),1.7,'bush'),
    ('Spiky plant red',(284,411,140,108),1.7,'bush'),('Shrub square',(418,412,134,106),1.7,'bush'),
    ('Shrub low',(552,412,120,106),1.7,'bush'),('Shrub tall',(672,409,128,109),1.7,'bush'),
    ('Fern patch',(797,411,177,108),2,'bush'),('Purple flower patch',(975,411,140,108),1.7,'bush'),
    ('White flower patch',(1114,411,134,108),1.7,'bush'),('Yellow flower patch',(1247,411,143,108),1.7,'bush'),
    ('Palm fern',(1388,405,148,114),2,'bush'),
]:add(name,rect,length,kind,'none')
for name,rect,length in [
    ('Long hedge planter',(13,517,187,96),2.5),('Magenta flower planter',(206,516,195,97),2.5),
    ('Yellow flower planter',(412,515,194,98),2.5),('Pink flower planter',(611,516,196,97),2.5),
    ('Mixed shrub planter',(822,515,199,98),2.5),('Round green planter',(1025,508,109,110),1.4),
    ('Round purple planter',(1152,508,114,110),1.4),('Round red planter',(1274,508,115,110),1.4),
    ('Round yellow planter',(1393,508,120,110),1.4),
]:add(name,rect,length)
for name,rect,length in [
    ('Grass patch lush',(5,612,190,111),3),('Grass patch dark',(198,612,184,111),3),
    ('Grass patch sparse',(383,612,176,111),3),('Grass tuft large',(558,612,123,111),1.6),
    ('Grass tuft small',(681,612,88,111),1.2),('Dry weed clump',(770,612,102,111),1.4),
    ('Green weed clump',(873,612,120,111),1.5),('Green fallen leaves',(992,612,119,111),1.8),
    ('Yellow fallen leaves',(1111,612,117,111),1.8),('Orange fallen leaves',(1228,612,133,111),1.8),
    ('Red fallen leaves',(1361,612,175,111),2),
]:add(name,rect,length,'ground_decal','none')
for name,rect,length in [
    ('Grey rock large',(8,723,140,89),2.2),('Mossy rock',(151,723,165,89),2.5),
    ('Grey rock medium',(315,723,111,89),1.7),('Grey rock small',(428,723,99,89),1.4),
    ('Small rock group',(529,723,125,89),1.8),('Pebble group',(661,723,123,89),1.6),
    ('Angular rock group',(792,723,132,89),1.9),
]:add(name,rect,length,'rock','solid')
for name,rect,length in [
    ('Puddle blue large',(5,810,181,99),3),('Asphalt rough patch',(187,810,163,99),3),
    ('Puddle grey',(355,810,162,99),2.5),('Puddle muddy',(525,810,143,99),2.5),
    ('Dirt patch broad',(662,810,157,99),2.5),('Dirt patch small',(818,810,117,99),1.5),
    ('Oil stain dark',(932,810,120,99),2),('Oil stain rainbow',(1054,810,159,99),2.5),
    ('Asphalt debris patch',(1210,810,145,99),2.5),('Gravel debris patch',(1352,810,184,99),3),
    ('Asphalt cracks large',(0,907,185,117),3),('Asphalt cracks branching',(188,907,163,117),3),
    ('Asphalt cracks dense',(351,907,159,117),3),('Asphalt cracks fine',(510,907,137,117),2.5),
    ('Curved tyre tracks',(649,907,234,117),5),('Circular tyre marks',(883,907,160,117),4),
    ('Straight tyre tracks',(1046,907,490,117),10),
]:add(name,rect,length,'ground_decal','none')
SHEETS['Top-Down Nature and Asphalt Asset Sheet-6']=items


def main():
    total = 0
    for name, sprites in SHEETS.items():
        path = FOLDER / (name + '.sheet.json')
        if not (FOLDER / (name + '.png')).is_file():
            raise FileNotFoundError(name)
        path.write_text(json.dumps({'sprites': sprites}, indent=2)+'\n', encoding='utf-8')
        total += len(sprites)
        print(f'{name}: {len(sprites)} sprites')
    print(f'Map sprite regions configured: {total}; source PNGs unchanged')


if __name__ == '__main__':
    main()
