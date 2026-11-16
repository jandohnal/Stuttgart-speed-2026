"""Reads values of Porsche.exe by virtual address (shared by tools/parts.py and tools/handling_exe.py).

Only addresses live in the repository; the values are read from the local exe at conversion
time and written to decomposed/, never kept in the repository (D-023).
"""
import struct


class Exe:
    """Reads values of Porsche.exe by virtual address (PE sections)."""

    def __init__(self, path):
        self.data = open(path, "rb").read()
        pe = struct.unpack_from("<I", self.data, 0x3C)[0]
        count, opt = struct.unpack_from("<H", self.data, pe + 6)[0], struct.unpack_from("<H", self.data, pe + 20)[0]
        base = struct.unpack_from("<I", self.data, pe + 24 + 28)[0]
        self.sections = []
        for k in range(count):
            vsize, va, rsize, raw = struct.unpack_from("<IIII", self.data, pe + 24 + opt + 40 * k + 8)
            self.sections.append((base + va, max(vsize, rsize), raw))

    def offset(self, va):
        for start, size, raw in self.sections:
            if start <= va < start + size:
                return va - start + raw
        raise ValueError("address 0x%x outside the exe" % va)

    def f32(self, va):
        return round(struct.unpack_from("<f", self.data, self.offset(va))[0], 6)

    def f32s(self, va, count):
        return [round(v, 6) for v in struct.unpack_from("<%df" % count, self.data, self.offset(va))]

    def text(self, va):
        o = self.offset(va)
        return self.data[o:o + 16].split(b"\0")[0].decode("latin1")
