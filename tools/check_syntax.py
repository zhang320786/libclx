import io, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = ["Tweak.xm", "CLXGuard.xm", "CLXShared.m", "CLXStore.m", "CLXSession.m",
         "CLXPanelController.m", "CLXMapController.m"]
HEADERS = ["CLXShared.h", "CLXStore.h", "CLXSession.h", "CLXGuard.h",
           "CLXPanelController.h", "CLXMapController.h"]


def strip_code(src):
    """去掉注释与字符串字面量，保留结构字符。"""
    out = []
    i, n = 0, len(src)
    state = None
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if state is None:
            if c == "/" and nxt == "/":
                state = "line"
                i += 2
                continue
            if c == "/" and nxt == "*":
                state = "block"
                i += 2
                continue
            if c == "@" and nxt == '"':
                state = "str"
                i += 2
                continue
            if c == '"':
                state = "str"
                i += 1
                continue
            if c == "'":
                state = "chr"
                i += 1
                continue
            out.append(c)
            i += 1
        elif state == "line":
            if c == "\n":
                state = None
                out.append(c)
            i += 1
        elif state == "block":
            if c == "*" and nxt == "/":
                state = None
                i += 2
                continue
            i += 1
        elif state == "str":
            if c == "\\":
                i += 2
                continue
            if c == '"':
                state = None
            i += 1
        elif state == "chr":
            if c == "\\":
                i += 2
                continue
            if c == "'":
                state = None
            i += 1
    return "".join(out)


def check(name):
    path = os.path.join(ROOT, name)
    src = io.open(path, encoding="utf-8").read()
    code = strip_code(src)

    problems = []

    stack = []
    line = 1
    pairs = {")": "(", "]": "[", "}": "{"}
    for ch in code:
        if ch == "\n":
            line += 1
        elif ch in "([{":
            stack.append((ch, line))
        elif ch in ")]}":
            if not stack:
                problems.append("多余的 %s (line %d)" % (ch, line))
            else:
                op, oline = stack.pop()
                if op != pairs[ch]:
                    problems.append("括号不匹配: %s(line %d) vs %s(line %d)" % (op, oline, ch, line))
    for op, oline in stack:
        problems.append("未闭合 %s (line %d)" % (op, oline))

    nhook = len(re.findall(r"^%hook\b", code, re.M))
    nend = len(re.findall(r"^%end\b", code, re.M))
    if nhook != nend:
        problems.append("%%hook=%d 但 %%end=%d" % (nhook, nend))

    for m in re.finditer(r'#import\s+"([^"]+)"', src):
        hdr = m.group(1)
        if not os.path.exists(os.path.join(ROOT, hdr)):
            problems.append("缺失头文件: %s" % hdr)

    return problems, nhook, nend


total = 0
for f in FILES:
    problems, nh, ne = check(f)
    status = "OK" if not problems else "FAIL"
    print("[%s] %-24s %5d lines  hook=%d end=%d" % (
        status, f, len(io.open(os.path.join(ROOT, f), encoding="utf-8").readlines()), nh, ne))
    for p in problems:
        print("     -> " + p)
        total += 1

print()
print("问题总数: %d" % total)
