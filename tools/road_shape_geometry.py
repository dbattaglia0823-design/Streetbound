"""Analytic circle sampling for editor-authored roundabout control points.

The source points remain authoritative: manual reshaping naturally returns
to the ordinary spline, while exact circles keep a smooth closing seam.
"""
import math


def circle(points):
    if len(points) < 9 or math.dist(points[0], points[-1]) > .01:
        return None
    count = len(points) - 1
    a = points[0]
    u = [points[count // 3][i] - a[i] for i in (0, 1)]
    v = [points[count * 2 // 3][i] - a[i] for i in (0, 1)]
    divisor = 2 * (u[0] * v[1] - u[1] * v[0])
    if abs(divisor) < .01:
        return None
    uu, vv = sum(x*x for x in u), sum(x*x for x in v)
    center = [a[0] + (v[1]*uu - u[1]*vv)/divisor,
              a[1] + (u[0]*vv - v[0]*uu)/divisor]
    radius = math.dist(center, a)
    if radius < 7.98 or not math.isfinite(radius):
        return None
    direction = 1 if ((a[0]-center[0])*(points[1][1]-center[1]) -
                      (a[1]-center[1])*(points[1][0]-center[0])) > 0 else -1
    angles = [math.atan2(p[1]-center[1], p[0]-center[0]) for p in points]
    total = 0
    for i in range(count):
        if abs(math.dist(points[i], center)-radius) > .02:
            return None
        sweep = (direction*(angles[i+1]-angles[i])) % math.tau
        if sweep < .00001 or sweep > math.pi:
            return None
        total += sweep
    if abs(total-math.tau) > .01:
        return None
    return center, radius, direction


def circle_path(points):
    shape = circle(points)
    if shape is None:
        return None
    center, radius, direction = shape
    max_angle = min(6/radius, 2*math.acos(max(-1, min(1, 1-.035/radius))))
    result = []
    for first, last in zip(points, points[1:]):
        angle = math.atan2(first[1]-center[1], first[0]-center[0])
        sweep = (direction*(math.atan2(last[1]-center[1], last[0]-center[0])-angle)) % math.tau
        steps = max(1, math.ceil(sweep/max_angle))
        for j in range(steps):
            p = first if j == 0 else [center[0]+math.cos(angle+direction*sweep*j/steps)*radius,
                                     center[1]+math.sin(angle+direction*sweep*j/steps)*radius]
            result.append([round(p[0], 3), round(p[1], 3)])
    result.append(list(points[-1]))
    return result
