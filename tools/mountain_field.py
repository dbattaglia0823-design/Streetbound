"""Original visual-only elevation field shared by road/art bakes (metres).

No effect on vehicle forces. North is -Y; light arrives from the northwest.
"""
import math

EXTENT = (2800, 2400)


def noise(x,y):
    ix,iy=math.floor(x),math.floor(y)
    fx,fy=x-ix,y-iy
    fx,fy=fx*fx*(3-2*fx),fy*fy*(3-2*fy)
    def hashed(a,b):
        value=math.sin(a*127.1+b*311.7)*43758.5453
        return (value-math.floor(value))*2-1
    return ((hashed(ix,iy)*(1-fx)+hashed(ix+1,iy)*fx)*(1-fy)
            +(hashed(ix,iy+1)*(1-fx)+hashed(ix+1,iy+1)*fx)*fy)


def height_m(x, y):
    bulk = (850 * math.exp(-((x-760)/800)**2-((y-510)/970)**2)
            + 440 * math.exp(-((x-1570)/600)**2-((y-600)/690)**2))
    envelope = min(1, bulk/250)
    detail = 46*noise(x/110,y/110)+18*noise(x/42+17,y/42)+5*noise(x/14,y/14+31)
    return max(0, bulk + envelope*detail)


def gradient(x, y):
    return ((height_m(x+2,y)-height_m(x-2,y))/4,
            (height_m(x,y+2)-height_m(x,y-2))/4)
