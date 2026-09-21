"""Minimal reader for binary FBX files: just enough to pull meshes out of a character."""
import struct, zlib

def parse(path):
    data = open(path, "rb").read()
    assert data[:20] == b"Kaydara FBX Binary  ", "not a binary FBX"
    version = struct.unpack_from("<I", data, 23)[0]
    wide = version >= 7500
    head, null = ("<QQQ", 25) if wide else ("<III", 13)

    def prop(at):
        kind = chr(data[at]); at += 1
        if kind in "YCIFDL":
            fmt = {"Y": "<h", "C": "<?", "I": "<i", "F": "<f", "D": "<d", "L": "<q"}[kind]
            return struct.unpack_from(fmt, data, at)[0], at + struct.calcsize(fmt)
        if kind in "fdlib":
            count, encoding, size = struct.unpack_from("<III", data, at); at += 12
            raw = data[at:at + size]
            if encoding: raw = zlib.decompress(raw)
            fmt = {"f": "f", "d": "d", "l": "q", "i": "i", "b": "?"}[kind]
            return list(struct.unpack("<%d%s" % (count, fmt), raw)), at + size
        size = struct.unpack_from("<I", data, at)[0]; at += 4
        raw = data[at:at + size]
        return (raw.decode("utf-8", "replace") if kind == "S" else raw), at + size

    def node(at):
        end, count, _ = struct.unpack_from(head, data, at); at += struct.calcsize(head)
        if end == 0: return None, at
        name = data[at + 1:at + 1 + data[at]].decode(); at += 1 + data[at]
        props = []
        for _ in range(count):
            value, at = prop(at); props.append(value)
        children = []
        while at < end:
            child, at = node(at)
            if child is None: break
            children.append(child)
        return {"name": name, "props": props, "children": children}, end

    nodes, at = [], 27
    while at < len(data) - null:
        n, at = node(at)
        if n is None: break
        nodes.append(n)
    return version, nodes

def find(nodes, name): return [n for n in nodes if n["name"] == name]
def child(n, name):
    found = find(n["children"], name)
    return found[0] if found else None
