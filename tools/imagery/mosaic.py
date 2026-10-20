"""Build a north-up RGB mosaic of NOAA 2026 pre-event imagery for a lon/lat box."""
import math, os, numpy as np, rasterio
from rasterio.windows import from_bounds
from rasterio.enums import Resampling
from PIL import Image
os.environ.setdefault("CURL_CA_BUNDLE", "/root/.ccr/ca-bundle.crt")
os.environ.setdefault("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")
BASE = "/vsicurl/https://noaa-eri-pds.s3.amazonaws.com/2026_Pre_Event/EC2601a_OB_N_RGB/EC2601a_OB_N_C{lon}w{lat}n.tif"
STEP = 45 / 3600
KEYS = None  # set by callers that use the S3 listing; see prepare_area.py

def dms(v):
    s = round(abs(v) * 3600); return f"{s//3600:03d}{(s%3600)//60:02d}{s%60:02d}"

def mosaic(x0, y0, x1, y1, mpp=0.6):
    """x = lon (negative west), y = lat. Returns PIL image, north up, with mpp meters per pixel."""
    lat_m = 111_320; lon_m = 111_320 * math.cos(math.radians((y0 + y1) / 2))
    W = int((x1 - x0) * lon_m / mpp); H = int((y1 - y0) * lat_m / mpp)
    out = np.zeros((H, W, 3), np.uint8)
    # tiles are named by their NW corner on a 45 arc-second grid
    def sec(v): return round(v * 3600)
    for L in range(math.ceil(-x1 * 3600 / 45) * 45, math.ceil(-x0 * 3600 / 45) * 45 + 1, 45):
        for T in range(math.ceil(y0 * 3600 / 45) * 45, math.ceil(y1 * 3600 / 45) * 45 + 1, 45):
            lon_s, lat_s = dms(L / 3600), dms(T / 3600)[1:]
            if KEYS is not None and f"{lon_s}w{lat_s}n" not in KEYS: continue
            try:
                src = rasterio.open(BASE.format(lon=lon_s, lat=lat_s))
            except rasterio.errors.RasterioIOError:
                continue  # no photo for this grid square
            with src as s:
                b = s.bounds
                ix0, iy0, ix1, iy1 = max(b.left, x0), max(b.bottom, y0), min(b.right, x1), min(b.top, y1)
                if ix0 >= ix1 or iy0 >= iy1: continue
                c0 = int((ix0 - x0) / (x1 - x0) * W); c1 = int((ix1 - x0) / (x1 - x0) * W)
                r0 = int((y1 - iy1) / (y1 - y0) * H); r1 = int((y1 - iy0) / (y1 - y0) * H)
                if c1 <= c0 or r1 <= r0: continue
                win = from_bounds(ix0, iy0, ix1, iy1, s.transform)
                data = s.read([1, 2, 3], window=win, out_shape=(3, r1 - r0, c1 - c0), resampling=Resampling.bilinear)
                alpha = s.read(4, window=win, out_shape=(r1 - r0, c1 - c0)) if s.count >= 4 else None
                block = np.transpose(data, (1, 2, 0))
                mask = (alpha > 0) if alpha is not None else block.any(axis=2)
                region = out[r0:r1, c0:c1]
                region[mask] = block[mask]
    return Image.fromarray(out)

if __name__ == "__main__":
    import sys
    x0, y0, x1, y1, mpp = map(float, sys.argv[1:6])
    mosaic(x0, y0, x1, y1, mpp).save(sys.argv[6])
