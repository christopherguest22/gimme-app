"""Render one hole as a phone-sized satellite picture (tee at the bottom, green at the top) for mockups."""
import math, json, sys, pyarrow.parquet as pq
from shapely import wkb
from mosaic import mosaic
from PIL import Image

def local(lat0, lon0):
    kx = 111_320 * math.cos(math.radians(lat0)); ky = 111_320
    return (lambda lat, lon: ((lon - lon0) * kx, (lat - lat0) * ky)), (lambda x, y: (lat0 + y / ky, lon0 + x / kx))

def render(tee, green, out, W=780, H=1688, mpp=0.30, along=0.52):
    (lat_t, lon_t), (lat_g, lon_g) = tee, green
    to_xy, to_ll = local(lat_t, lon_t)
    gx, gy = to_xy(lat_g, lon_g)
    length = math.hypot(gx, gy)
    bearing = math.degrees(math.atan2(gx, gy)) % 360
    # screen center sits `along` of the way from tee to green
    cx, cy = gx * along, gy * along
    half = math.hypot(W, H) / 2 * mpp + 20
    lat_c, lon_c = to_ll(cx, cy)
    la0, lo0 = to_ll(cx - half, cy - half); la1, lo1 = to_ll(cx + half, cy + half)
    im = mosaic(lo0, la0, lo1, la1, mpp)
    im = im.rotate(bearing, resample=Image.BICUBIC)        # counterclockwise: line of play points up
    w, h = im.size
    im = im.crop(((w - W) // 2, (h - H) // 2, (w + W) // 2, (h + H) // 2))
    im.save(out, quality=82, optimize=True, progressive=True)
    b = math.radians(bearing)
    def px(lat, lon):
        x, y = to_xy(lat, lon); x -= cx; y -= cy
        # rotate world by -bearing so the hole points up, then to screen pixels
        rx = x * math.cos(b) - y * math.sin(b); ry = x * math.sin(b) + y * math.cos(b)
        return W / 2 + rx / mpp, H / 2 - ry / mpp
    return px, bearing, length

if __name__ == "__main__":
    pass
