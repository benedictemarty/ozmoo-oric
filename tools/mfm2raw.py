#!/usr/bin/env python3
"""mfm2raw.py — extrait une image MFM_DISK (format Phosphoric, cf. dsk_raw2mfm.py)
en image BRUTE side-major (secteurs 256 o concaténés, toutes les pistes de la face 0
puis celles de la face 1). Inverse exact de `dsk_raw2mfm.py`.

Nécessaire pour la voie A Oric : partir d'un disque **Sedoric bootable** (fourni en MFM)
et obtenir un raw side-major sur lequel `sedoric_inject.py` (injection fichier AUTO) et
`oric_disk.py` (écriture des secteurs bruts story/config) opèrent, avant reconversion MFM.

Format MFM (dsk_raw2mfm) : header 256 o (`MFM_DISK` + sides/tracks/geometry en <I>),
puis par (side, track) en side-major une piste de TRK_RAW octets ; chaque secteur =
sync + ID `A1 A1 A1 FE track side sec size` +CRC + gap + sync + data `A1 A1 A1 FB`+256o
+CRC + gap. On repère les secteurs par leurs address marks.

Usage : mfm2raw.py <in_mfm.dsk> <out_raw.dsk> [sectors=17]
"""
import struct
import sys

SECSZ = 256
ID_AM = bytes([0xA1, 0xA1, 0xA1, 0xFE])
DATA_AM = bytes([0xA1, 0xA1, 0xA1, 0xFB])


def parse_mfm(buf, sectors=17):
    """Renvoie (sides, tracks, sectors, raw_bytes side-major)."""
    if buf[:8] != b"MFM_DISK":
        raise SystemExit("pas un MFM_DISK (header absent)")
    sides = struct.unpack("<I", buf[8:12])[0]
    tracks = struct.unpack("<I", buf[12:16])[0]
    trk_raw = (len(buf) - 256) // (sides * tracks)
    raw = bytearray(sides * tracks * sectors * SECSZ)
    for side in range(sides):
        for track in range(tracks):
            block = side * tracks + track      # side-major
            t = buf[256 + block * trk_raw: 256 + (block + 1) * trk_raw]
            i, seen = 0, 0
            while True:
                j = t.find(ID_AM, i)
                if j < 0:
                    break
                sec = t[j + 6]                 # A1 A1 A1 FE track side SEC size
                k = t.find(DATA_AM, j)
                if k < 0:
                    break
                data = t[k + 4:k + 4 + SECSZ]
                if 1 <= sec <= sectors and len(data) == SECSZ:
                    off = (block * sectors + (sec - 1)) * SECSZ
                    raw[off:off + SECSZ] = data
                    seen += 1
                i = k + 4 + SECSZ
    return sides, tracks, sectors, bytes(raw)


def _roundtrip_test():
    """raw -> MFM (dsk_raw2mfm) -> raw (mfm2raw) == raw. Import du convertisseur voisin."""
    import importlib.util
    import os
    r2m_path = os.path.expanduser("~/Oric1/tools/dsk_raw2mfm.py")
    spec = importlib.util.spec_from_file_location("dsk_raw2mfm", r2m_path)
    r2m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(r2m)
    sides, tracks, sectors = 2, 42, 17
    # image raw synthétique : chaque secteur = motif unique
    raw = bytearray(sides * tracks * sectors * SECSZ)
    for n in range(len(raw)):
        raw[n] = (n * 7 + (n >> 8)) & 0xFF
    # construit la piste MFM comme dsk_raw2mfm.main, mais en mémoire
    hdr = bytearray(b"MFM_DISK") + struct.pack("<I", sides) + struct.pack("<I", tracks) \
        + struct.pack("<I", 1)
    hdr += b"\x00" * (256 - len(hdr))
    out = bytearray(hdr)
    for side in range(sides):
        for track in range(tracks):
            block = side * tracks + track
            base = block * sectors * SECSZ
            secs = [raw[base + i * SECSZ: base + (i + 1) * SECSZ] for i in range(sectors)]
            out += r2m.build_track(track, side, secs)
    _, _, _, back = parse_mfm(bytes(out), sectors)
    assert back == bytes(raw), "round-trip mfm2raw != identité"
    print("OK: round-trip raw->MFM->raw == identité (%d octets)" % len(raw))


def main():
    if len(sys.argv) < 3:
        _roundtrip_test()
        sys.exit(__doc__)
    sectors = int(sys.argv[3]) if len(sys.argv) > 3 else 17
    buf = open(sys.argv[1], "rb").read()
    sides, tracks, sectors, raw = parse_mfm(buf, sectors)
    open(sys.argv[2], "wb").write(raw)
    print("extrait %s -> %s : sides=%d tracks=%d sectors=%d raw=%d octets" %
          (sys.argv[1], sys.argv[2], sides, tracks, sectors, len(raw)))


if __name__ == "__main__":
    main()
