"""Step 2: cut the NOAA photos of the golf areas into Web Mercator map tiles (WebP) in one MBTiles file."""
import math, os, io, sys, glob, pickle, sqlite3, numpy as np, rasterio
from multiprocessing import Pool
from rasterio.warp import reproject, Resampling
from rasterio.transform import from_bounds
from shapely.geometry import box
from PIL import Image

AREA = pickle.load(open('area.pkl', 'rb'))
SRC = sorted(glob.glob('tifs/*.tif'))
BOUNDS = {}
for p in SRC:
    with rasterio.open(p) as s: BOUNDS[p] = s.bounds
R = 6378137.0
def merc_bounds(z, x, y):
    n = 2 ** z; size = 2 * math.pi * R / n
    return -math.pi * R + x * size, math.pi * R - (y + 1) * size, -math.pi * R + (x + 1) * size, math.pi * R - y * size
def ll_bounds(z, x, y):
    n = 2 ** z
    lon0 = x / n * 360 - 180; lon1 = (x + 1) / n * 360 - 180
    lat1 = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n)))); lat0 = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (y + 1) / n))))
    return lon0, lat0, lon1, lat1
def tiles(z):
    n = 2 ** z; x0, y0, x1, y1 = AREA.bounds
    tx = lambda lon: int((lon + 180) / 360 * n)
    ty = lambda lat: int((1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n)
    return [(x, y) for x in range(tx(x0), tx(x1) + 1) for y in range(ty(y1), ty(y0) + 1) if AREA.intersects(box(*ll_bounds(z, x, y)))]

TOP = 19; BLOCK = 17  # render z17 blocks at z19 detail (1024 px), split into z19 tiles
def render(block):
    x, y = block; scale = 2 ** (TOP - BLOCK); size = 256 * scale
    dst = np.zeros((3, size, size), np.uint8); filled = np.zeros((size, size), bool)
    mb = merc_bounds(BLOCK, x, y); transform = from_bounds(*mb, size, size)
    lb = box(*ll_bounds(BLOCK, x, y))
    for p in SRC:
        b = BOUNDS[p]
        if not lb.intersects(box(b.left, b.bottom, b.right, b.top)): continue
        with rasterio.open(p) as s:
            part = np.zeros((4, size, size), np.uint8)
            for i in range(1, 5):
                reproject(rasterio.band(s, i), part[i - 1], dst_transform=transform, dst_crs='EPSG:3857', resampling=Resampling.bilinear)
            m = (part[3] > 0) & ~filled
            dst[:, m] = part[:3, m]; filled |= m
    out = {}
    for dx in range(scale):
        for dy in range(scale):
            sub = filled[dy * 256:(dy + 1) * 256, dx * 256:(dx + 1) * 256]
            if sub.mean() < 0.02: continue
            rgb = np.transpose(dst[:, dy * 256:(dy + 1) * 256, dx * 256:(dx + 1) * 256], (1, 2, 0))
            img = Image.fromarray(np.dstack([rgb, (sub * 255).astype(np.uint8)]), 'RGBA')
            out[(x * scale + dx, y * scale + dy)] = img
    return out

def enc(img):
    b = io.BytesIO(); img.save(b, 'WEBP', quality=72, method=4, exact=False); return b.getvalue()

if __name__ == '__main__':
    out_path = sys.argv[1]
    if os.path.exists(out_path): os.remove(out_path)
    db = sqlite3.connect(out_path)
    db.executescript("""CREATE TABLE metadata (name TEXT, value TEXT);
      CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);
      CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);""")
    x0, y0, x1, y1 = AREA.bounds
    for k, v in dict(name='Kiawah Island golf imagery', format='webp', minzoom='14', maxzoom=str(TOP), type='baselayer',
                     bounds=f'{x0},{y0},{x1},{y1}', attribution='Imagery: NOAA National Geodetic Survey, 2026 (public domain)').items():
        db.execute('INSERT INTO metadata VALUES (?,?)', (k, v))
    level = {}
    blocks = tiles(BLOCK)
    with Pool(4) as pool:
        for i, res in enumerate(pool.imap_unordered(render, blocks)):
            level.update(res)
            if i % 50 == 0: print('block', i, '/', len(blocks), flush=True)
    keep = set(tiles(TOP))
    level = {k: v for k, v in level.items() if k in keep}
    for z in range(TOP, 13, -1):
        n = 2 ** z
        for (x, y), img in level.items():
            db.execute('INSERT INTO tiles VALUES (?,?,?,?)', (z, x, n - 1 - y, enc(img)))
        db.commit(); print('z', z, len(level), flush=True)
        if z == 14: break
        parent = {}
        for (x, y), img in level.items():
            parent.setdefault((x // 2, y // 2), Image.new('RGBA', (512, 512), (0, 0, 0, 0))).paste(img, ((x % 2) * 256, (y % 2) * 256))
        level = {k: v.resize((256, 256), Image.LANCZOS) for k, v in parent.items()}
    db.execute('VACUUM'); db.close()
    print('size MB', os.path.getsize(out_path) / 1e6)
