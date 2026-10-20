"""Step 1: find the golf areas on Kiawah Island and download the NOAA photos that cover them.

Golf features (greens, tees, fairways, bunkers) come from Overture Maps (OpenStreetMap data) on
public S3. Photos come from NOAA's 2026 pre-event coastal survey (public domain, ~30 cm).

    python3 -m pip install pyarrow shapely rasterio pillow
    python3 prepare_area.py            # writes base_land_use.parquet, area.pkl, tifs/*.tif
    python3 make_tiles.py kiawah-imagery.mbtiles
    cp kiawah-imagery.mbtiles ../../Gimme/Resources/
"""
import math, os, pickle, re, subprocess, urllib.parse, urllib.request
import pyarrow.dataset as ds, pyarrow.compute as pc, pyarrow.fs as fs, pyarrow.parquet as pq
from shapely import wkb
from shapely.geometry import box
from shapely.ops import unary_union

RELEASE = "2026-09-23.1"          # Overture release
BBOX = (-80.17, 32.57, -79.99, 32.64)  # Kiawah Island
NOAA = "https://noaa-eri-pds.s3.amazonaws.com"
COLLECTION = "2026_Pre_Event/EC2601a_OB_N_RGB/"

s3 = fs.S3FileSystem(anonymous=True, region="us-west-2")
d = ds.dataset(f"overturemaps-us-west-2/release/{RELEASE}/theme=base/type=land_use/", filesystem=s3, format="parquet")
x0, y0, x1, y1 = BBOX
f = (pc.field("bbox", "xmin") > x0) & (pc.field("bbox", "xmax") < x1) & (pc.field("bbox", "ymin") > y0) & (pc.field("bbox", "ymax") < y1)
t = d.to_table(filter=f); pq.write_table(t, "base_land_use.parquet")
rows = [r for r in t.to_pylist() if r["subtype"] == "golf"]
kx = 111_320 * math.cos(math.radians((y0 + y1) / 2))
area = unary_union([wkb.loads(r["geometry"]).buffer(60 / kx) for r in rows])   # 60 m around every golf feature
pickle.dump(area, open("area.pkl", "wb"))

# NOAA files are named by their NW corner on a 45 arc-second grid, e.g. C0800000w323645n.
keys, token = [], None
while True:
    url = f"{NOAA}/?list-type=2&prefix={COLLECTION}&max-keys=1000" + (f"&continuation-token={urllib.parse.quote(token)}" if token else "")
    body = urllib.request.urlopen(url).read().decode()
    keys += re.findall(r"_C(\d{7}w\d{6}n)\.tif</Key>", body)
    m = re.search(r"<NextContinuationToken>([^<]+)<", body)
    if not m: break
    token = m.group(1)
os.makedirs("tifs", exist_ok=True)
for k in keys:
    lon = int(k[0:3]) + int(k[3:5]) / 60 + int(k[5:7]) / 3600
    lat = int(k[8:10]) + int(k[10:12]) / 60 + int(k[12:14]) / 3600
    if box(-lon, lat - 45 / 3600, -lon + 45 / 3600, lat).intersects(area) and not os.path.exists(f"tifs/{k}.tif"):
        subprocess.run(["curl", "-sS", "--retry", "3", "-o", f"tifs/{k}.tif", f"{NOAA}/{COLLECTION}EC2601a_OB_N_C{k}.tif"], check=True)
print("golf features:", len(rows), "photo files:", len(os.listdir("tifs")))
