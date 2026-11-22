"""校验 CLXShared.m 里的数学实现（同一套公式，用 Python 复算并与已知值比对）。"""
import math

PI = 3.14159265358979324
A = 6378245.0
EE = 0.00669342162296594323


def out_of_china(lat, lng):
    return lng < 72.004 or lng > 137.8347 or lat < 0.8293 or lat > 55.8271


def t_lat(x, y):
    ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(abs(x))
    ret += (20.0 * math.sin(6.0 * x * PI) + 20.0 * math.sin(2.0 * x * PI)) * 2.0 / 3.0
    ret += (20.0 * math.sin(y * PI) + 40.0 * math.sin(y / 3.0 * PI)) * 2.0 / 3.0
    ret += (160.0 * math.sin(y / 12.0 * PI) + 320.0 * math.sin(y * PI / 30.0)) * 2.0 / 3.0
    return ret


def t_lon(x, y):
    ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(abs(x))
    ret += (20.0 * math.sin(6.0 * x * PI) + 20.0 * math.sin(2.0 * x * PI)) * 2.0 / 3.0
    ret += (20.0 * math.sin(x * PI) + 40.0 * math.sin(x / 3.0 * PI)) * 2.0 / 3.0
    ret += (150.0 * math.sin(x / 12.0 * PI) + 300.0 * math.sin(x / 20.0 * PI)) * 2.0 / 3.0
    return ret


def wgs_to_gcj(lat, lng):
    if out_of_china(lat, lng):
        return lat, lng
    d_lat = t_lat(lng - 105.0, lat - 35.0)
    d_lon = t_lon(lng - 105.0, lat - 35.0)
    rad = lat / 180.0 * PI
    magic = math.sin(rad)
    magic = 1.0 - EE * magic * magic
    sq = math.sqrt(magic)
    d_lat = (d_lat * 180.0) / ((A * (1.0 - EE)) / (magic * sq) * PI)
    d_lon = (d_lon * 180.0) / (A / sq * math.cos(rad) * PI)
    return lat + d_lat, lng + d_lon


def gcj_to_wgs(lat, lng):
    if out_of_china(lat, lng):
        return lat, lng
    w_lat, w_lng = lat, lng
    for _ in range(6):
        g_lat, g_lng = wgs_to_gcj(w_lat, w_lng)
        w_lat = lat + (w_lat - g_lat)
        w_lng = lng + (w_lng - g_lng)
    return w_lat, w_lng


def distance(a, b):
    lat1, lat2 = math.radians(a[0]), math.radians(b[0])
    d_lat = math.radians(b[0] - a[0])
    d_lon = math.radians(b[1] - a[1])
    h = math.sin(d_lat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(d_lon / 2) ** 2
    return 2.0 * 6371000.0 * math.asin(min(1.0, math.sqrt(h)))


def lerp(a, b, p):
    p = max(0.0, min(1.0, p))
    alat, blat = math.radians(a[0]), math.radians(b[0])
    alon, blon = math.radians(a[1]), math.radians(b[1])
    d = 2.0 * math.asin(min(1.0, math.sqrt(
        math.sin((blat - alat) / 2) ** 2 +
        math.cos(alat) * math.cos(blat) * math.sin((blon - alon) / 2) ** 2)))
    if d < 1e-12:
        return b
    Aa = math.sin((1.0 - p) * d) / math.sin(d)
    Bb = math.sin(p * d) / math.sin(d)
    x = Aa * math.cos(alat) * math.cos(alon) + Bb * math.cos(blat) * math.cos(blon)
    y = Aa * math.cos(alat) * math.sin(alon) + Bb * math.cos(blat) * math.sin(blon)
    z = Aa * math.sin(alat) + Bb * math.sin(blat)
    return math.degrees(math.atan2(z, math.sqrt(x * x + y * y))), math.degrees(math.atan2(y, x))


print("=== 1. WGS-84 -> GCJ-02（天安门，参考值 39.910100 / 116.403870 附近）===")
g = wgs_to_gcj(39.9087, 116.3975)
print("  输入 39.908700, 116.397500")
print("  输出 %.6f, %.6f   偏移 %.1f m" % (g[0], g[1], distance((39.9087, 116.3975), g)))

print("\n=== 2. GCJ-02 -> WGS-84 往返一致性（应回到原点，误差 < 0.2 m）===")
w = gcj_to_wgs(g[0], g[1])
print("  往返 %.6f, %.6f   误差 %.3f m" % (w[0], w[1], distance(w, (39.9087, 116.3975))))

print("\n=== 3. 上海人民广场往返 ===")
g2 = wgs_to_gcj(31.2304, 121.4737)
w2 = gcj_to_wgs(g2[0], g2[1])
print("  %.6f, %.6f  往返误差 %.3f m" % (w2[0], w2[1], distance(w2, (31.2304, 121.4737))))

print("\n=== 4. 境外坐标不应被偏移 ===")
print("  东京 ->", wgs_to_gcj(35.6812, 139.7671))

print("\n=== 5. 大圆距离（北京->上海，参考 ~1067 km）===")
d = distance((39.9042, 116.4074), (31.2304, 121.4737))
print("  %.2f km" % (d / 1000.0))

print("\n=== 6. 球面插值：p=0 / 0.5 / 1 ===")
o = (39.9042, 116.4074)
t = (31.2304, 121.4737)
for p in (0.0, 0.5, 1.0):
    q = lerp(o, t, p)
    print("  p=%.1f -> %.6f, %.6f   距起点 %.2f km  距终点 %.2f km"
          % (p, q[0], q[1], distance(o, q) / 1000.0, distance(q, t) / 1000.0))

print("\n=== 7. 插值速度合理性（步行模式 1.35 m/s，距离 5 km 应约 3700 s）===")
print("  duration = %.0f s" % max(4.0, min(2400.0, 5000 / 1.35)))

print("\n=== 8. 精度采样分布（自动档，arrived=True）===")
for k in range(5):
    seed = k * 7.0
    s = math.sin(seed * 12.9898 + 78.233) * 43758.5453123
    n = s - math.floor(s)
    print("  seed=%4.0f noise=%.4f  acc=%.1f m" % (seed, n, 6.0 + n * 9.0))
