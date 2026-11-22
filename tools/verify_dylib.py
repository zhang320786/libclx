"""从 deb 中提取 dylib，校验 Mach-O 架构、install_name 与关键符号。"""
import io, lzma, struct, sys, tarfile

path = sys.argv[1]
raw = open(path, "rb").read()

pos, members = 8, {}
while pos + 60 <= len(raw):
    hdr = raw[pos:pos + 60]
    name = hdr[0:16].decode("ascii", "replace").strip().rstrip("/")
    size = int(hdr[48:58].decode("ascii", "replace").strip())
    members[name] = raw[pos + 60:pos + 60 + size]
    pos += 60 + size
    if pos % 2:
        pos += 1

data = [d for n, d in members.items() if n.startswith("data.tar")][0]
blob = lzma.decompress(data, format=lzma.FORMAT_ALONE)
tf = tarfile.open(fileobj=io.BytesIO(blob))

dylib = next(m for m in tf.getmembers() if m.name.endswith(".dylib"))
bin_data = tf.extractfile(dylib).read()

CPU = {0x0100000C: "arm64", 0x0100000C | 0x02000000: "arm64e", 0x0000000C: "arm"}

# ---- fat binary 展开 ----
def slices(data):
    magic_be = struct.unpack(">I", data[:4])[0]
    if magic_be != 0xCAFEBABE:
        return [(data, None)]
    n = struct.unpack(">I", data[4:8])[0]
    out = []
    for i in range(n):
        base = 8 + i * 20
        cputype, cpusub, offset, size, align = struct.unpack(">iiIII", data[base:base + 20])
        out.append((data[offset:offset + size], (cputype, cpusub)))
        print("  fat slice %d: cputype=0x%08X (%s)  size=%d"
              % (i, cputype, CPU.get(cputype, "?"), size))
    return out

print("=== Mach-O 容器 ===")
if struct.unpack(">I", bin_data[:4])[0] == 0xCAFEBABE:
    print("  类型: FAT (多架构)")
else:
    print("  类型: thin")
parts = slices(bin_data)

MAGIC = {0xFEEDFACF: "64-bit little endian", 0xFEEDFACE: "32-bit little endian"}
magic = struct.unpack("<I", parts[0][0][:4])[0]
print("\n=== 首个架构 ===")
print("  magic   : 0x%08X  (%s)" % (magic, MAGIC.get(magic, "未知")))

# 选最后一个 arm64 slice 做结构检查
arch_data = None
for blob_, meta in parts:
    if meta is None or meta[0] == 0x0100000C:
        arch_data = blob_
print("  使用 slice: %d bytes" % len(arch_data))

cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags = struct.unpack("<iiIIII", arch_data[4:28])
ftype = {0x6: "MH_DYLIB", 0x2: "MH_EXECUTE", 0x8: "MH_BUNDLE"}
print("  cputype : 0x%08X  (%s)" % (cputype, CPU.get(cputype, "?")))
print("  filetype: %d  (%s)" % (filetype, ftype.get(filetype, "?")))
print("  ncmds   : %d" % ncmds)

# 遍历 load commands 找 LC_ID_DYLIB 与 LC_LOAD_DYLIB
LC_ID_DYLIB, LC_LOAD_DYLIB = 0xD, 0xC
off = 32
print("\n=== load commands（dylib 相关）===")
loads = []
for i in range(ncmds):
    cmd, cmdsize = struct.unpack("<II", arch_data[off:off + 8])
    name = ""
    if cmd in (LC_ID_DYLIB, LC_LOAD_DYLIB):
        name_off = struct.unpack("<I", arch_data[off + 8:off + 12])[0]
        s = arch_data[off + name_off:off + cmdsize].split(b"\x00")[0].decode("ascii", "replace")
        tag = "ID  " if cmd == LC_ID_DYLIB else "LOAD"
        print("  %s %s" % (tag, s))
        loads.append(s)
    elif cmd == 0x19:
        segname = arch_data[off + 8:off + 24].split(b"\x00")[0].decode("ascii", "replace")
        name = "LC_SEGMENT_64 " + segname
    print("  [%2d] cmd=0x%08X size=%-4d %s" % (i, cmd, cmdsize, name))
    off += cmdsize

print("\n=== 关键符号 / 字符串 ===")
for token in [b"CLXSession", b"CLXStore", b"CLXGuard", b"CLXPanelController",
              b"TencentLBSLocation", b"CLLocationManager", b"com.tencent.ww",
              b"doesNotExistTokenXYZ"]:
    found = token in bin_data
    note = ""
    if token == b"doesNotExistTokenXYZ":
        note = "  (对照组，应为 False)"
    print("  %-24s %s%s" % (token.decode(), "找到" if found else "未找到", note))

print("\n=== Filter plist ===")
plist = next(m for m in tf.getmembers() if m.name.endswith(".plist"))
print("  " + tf.extractfile(plist).read().decode("utf-8", "replace").strip())

ok = (magic == 0xFEEDFACF
      and filetype == 0x6
      and any(meta is None or meta[0] == 0x0100000C for _b, meta in parts)
      and b"CLXSession" in bin_data
      and b"TencentLBSLocation" in bin_data)
print("\n结论: " + ("通过" if ok else "异常"))
sys.exit(0 if ok else 1)
