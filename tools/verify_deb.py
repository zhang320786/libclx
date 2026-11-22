"""解析 deb（ar 归档），校验内部结构与路径。"""
import io, lzma, os, struct, sys, tarfile

path = sys.argv[1]
raw = open(path, "rb").read()

# ---- ar 解析 ----
assert raw[:8] == b"!<arch>\n", "不是 ar 归档"
pos = 8
members = []
while pos + 60 <= len(raw):
    hdr = raw[pos:pos + 60]
    name = hdr[0:16].decode("ascii", "replace").strip().rstrip("/")
    size = int(hdr[48:58].decode("ascii", "replace").strip())
    data_off = pos + 60
    members.append((name, raw[data_off:data_off + size]))
    pos = data_off + size
    if pos % 2:
        pos += 1

print("=== ar 成员 ===")
for n, d in members:
    print("  %-24s %8d bytes   magic=%s" % (n, len(d), d[:6].hex()))

ctrl_blob = dict(members).get("control")
if ctrl_blob is None:
    import gzip
    ctrl_name, ctrl_tar = [(n, d) for n, d in members if n.startswith("control.tar")][0]
    tf = tarfile.open(fileobj=io.BytesIO(gzip.decompress(ctrl_tar)))
    for m in tf.getmembers():
        if m.name.endswith("control"):
            ctrl_blob = tf.extractfile(m).read()
            break

print("\n=== control ===")
print(ctrl_blob.decode("utf-8", "replace") if ctrl_blob else "(未找到)")

data_name, data_blob = [(n, d) for n, d in members if n.startswith("data.tar")][0]
print("\n=== %s ===" % data_name)

if data_blob[:6] == b"\xfd7zXZ\x00" or data_name.endswith(".xz"):
    decompressed = lzma.decompress(data_blob)
elif data_name.endswith(".lzma"):
    decompressed = lzma.decompress(data_blob, format=lzma.FORMAT_ALONE)
elif data_name.endswith(".gz"):
    import gzip
    decompressed = gzip.decompress(data_blob)
elif data_name.endswith(".zst"):
    print("  zstd 格式，跳过内容列举")
    decompressed = None
else:
    decompressed = data_blob

files = []
if decompressed:
    tf = tarfile.open(fileobj=io.BytesIO(decompressed))
    for m in tf.getmembers():
        kind = "d" if m.isdir() else ("l" if m.issym() or m.islnk() else "f")
        print("  %s %8d  %s" % (kind, m.size, m.name))
        files.append(m.name)

print("\n=== 断言 ===")
bad = [f for f in files if "/var/jb" in f or f.startswith("./var/jb")]
dylibs = [f for f in files if f.endswith(".dylib")]
plists = [f for f in files if f.endswith(".plist")]
print("  含 /var/jb 前缀         : %s" % ("是 -> 失败" if bad else "否 -> 通过"))
print("  DynamicLibraries 下 dylib: %s" % (dylibs[0] if dylibs else "缺失 -> 失败"))
print("  Filter plist             : %s" % (plists[0] if plists else "缺失 -> 失败"))

sys.exit(1 if (bad or not dylibs or not plists) else 0)
