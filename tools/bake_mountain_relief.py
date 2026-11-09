"""Bake original elevation/hillshade data and atlas art. Requires numpy/Pillow.

Run after editing mountain_field.py. Runtime uses the checked-in PNGs only.
"""
from pathlib import Path
import numpy as np
from PIL import Image
from mountain_field import EXTENT

ROOT = Path(__file__).resolve().parents[1]
x, y = np.meshgrid(np.arange(0, EXTENT[0], 2, dtype=float)+1,
                   np.arange(0, EXTENT[1], 2, dtype=float)+1)
bulk = (850*np.exp(-((x-760)/800)**2-((y-510)/970)**2)
        +440*np.exp(-((x-1570)/600)**2-((y-600)/690)**2))
def noise(x,y):
    ix,iy=np.floor(x),np.floor(y)
    fx,fy=x-ix,y-iy
    fx,fy=fx*fx*(3-2*fx),fy*fy*(3-2*fy)
    def hashed(a,b):
        v=np.sin(a*127.1+b*311.7)*43758.5453
        return (v-np.floor(v))*2-1
    return ((hashed(ix,iy)*(1-fx)+hashed(ix+1,iy)*fx)*(1-fy)
            +(hashed(ix,iy+1)*(1-fx)+hashed(ix+1,iy+1)*fx)*fy)
height = np.maximum(0,bulk+np.minimum(1,bulk/250)*(46*noise(x/110,y/110)
                     +18*noise(x/42+17,y/42)+5*noise(x/14,y/14+31)))
dy, dx = np.gradient(height, 2)
normal_length = np.sqrt(1+dx*dx+dy*dy)
# Dot with normalized northwest sunlight, including a broad ambient term.
light = np.clip((dx*.48+dy*.57+.67)/normal_length, 0, 1)
slope = np.clip(np.sqrt(dx*dx+dy*dy)/2.2,0,1)
mask = np.clip((height-25)/100,0,1)
mask *= np.clip((EXTENT[0]-x)/180,0,1)*np.clip((EXTENT[1]-y)/180,0,1)
data = np.stack([light,np.clip(height/1200,0,1),slope,mask],axis=-1)
destination = ROOT/'assets/scenery'
Image.fromarray(np.uint8(np.clip(data,0,1)*255)).save(destination/'mountain-relief-data.png')
low, high = np.array([128,151,119]), np.array([183,178,157])
t = np.clip((height-180)/850,0,1)[...,None]
rgb = (low*(1-t)+high*t)*(.64+light[...,None]*.58)
rgba = np.concatenate([np.clip(rgb,0,255),mask[...,None]*210],axis=-1)
Image.fromarray(np.uint8(rgba)).save(destination/'mountain-relief-map.png')
print('Baked visual elevation: %.0f–%.0f m, %d × %d pixels' % (height.min(),height.max(),x.shape[1],x.shape[0]))
