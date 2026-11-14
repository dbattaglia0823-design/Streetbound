"""Exact rectangular clearance for adjoining city buildings."""
import math
BUILDINGS={'house','coastal_house','lodge','building','shop','warehouse','garage','workshop','showroom','fuel','cafe','office','hotel'}
def overlaps(a,b,adapt_legacy=False):
    if adapt_legacy:
        from road_widths import SCENERY_FACTORS
        def adapted(p):
            if p.get('authoring_id') or p.get('asset_path'):return p
            factor=SCENERY_FACTORS.get(p['kind'],1)
            return {**p,'size':[v*factor for v in p['size']]}
        a,b=adapted(a),adapted(b)
    if a['kind'] not in BUILDINGS or b['kind'] not in BUILDINGS:
        return math.dist(a['p'],b['p']) < a.get('radius',0)+b.get('radius',0)+.5
    def axes(prop):
        angle=prop.get('angle',0);c,s=math.cos(angle),math.sin(angle)
        return [(c,s),(-s,c)]
    aa,bb=axes(a),axes(b)
    delta=[a['p'][i]-b['p'][i] for i in (0,1)]
    for axis in aa+bb:
        extent=lambda p,basis: sum(abs(sum(u*v for u,v in zip(axis,d)))*p['size'][i]/2 for i,d in enumerate(basis))
        if abs(sum(u*v for u,v in zip(delta,axis))) >= extent(a,aa)+extent(b,bb)-.02:return False
    return True
