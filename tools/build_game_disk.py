#!/usr/bin/env python3
"""build_game_disk.py — construit une disquette de jeu Ozmoo/Oric BOOTABLE (voie A).

Équivalent Oric+Sedoric de make.rb (build_S1). Assemble, sur un master Sedoric
bootable :
  - l'interpréteur VMEM + sa dynmem, en **fichier AUTO** Sedoric (lancé au boot) ;
  - la story-file en **secteurs bruts** (accès VMEM direct bloc→piste/secteur) ;
  - la **piste de config** (disk_info + vmem_data) lue par le boot VMEM de l'interp.

Faits établis (cf. docs/PORTING_ORIC.md §EPIC 5) :
  * l'EPROM Microdisc n'amorce que du Sedoric ; on réutilise donc son boot via un
    fichier AUTO (voie « bootstrap Sedoric minimal ») ;
  * le DOS Sedoric ne vit que sur **side 0, pistes 0 et 20** (prouvé : effacer tout le
    reste boote encore) → tout le reste est libre pour nous ;
  * le fichier AUTO = interp ($0500–$33FF) + dynmem (chargée à $3400), load/exec $0500 ;
  * la story va sur les **pistes 1-19** (bruts), l'interp AUTO dès la **piste 21**
    (`sedoric_inject`), la piste 20 reste au DOS → aucune collision (petit jeu).

Pipeline : mfm2raw(master) → efface hors {t0,t20} → reset directory (t20 s4) →
écrit story+config bruts → sedoric_inject (interp AUTO + INIST) → dsk_raw2mfm.

Usage : build_game_disk.py <master.dsk> <interp.bin> <story.z*> <out.dsk>
          [name=OZMOO] [game_id_hex8=00__] [conf_trk=1]
"""
import importlib.util
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ORIC_TOOLS = os.path.expanduser("~/Oric1/tools")
SECSZ = 256
DIR_TRACK, DIR_SECTOR = 20, 4
KEEP = {0, 20}                 # pistes DOS (side 0) à préserver


def _load(mod, path):
    spec = importlib.util.spec_from_file_location(mod, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


od = _load("oric_disk", os.path.join(HERE, "oric_disk.py"))
mfm2raw = _load("mfm2raw", os.path.join(HERE, "mfm2raw.py"))


def _catalog_used(raw, tracks, sectors, side=0):
    """Carte des secteurs (piste, secteur 1-based) occupés par le catalogue Sedoric
    (mêmes règles que sedoric_inject) : secteurs directory + descripteurs + data des
    fichiers. Marche robuste (bornes) sur la chaîne directory depuis (20,4)."""
    def rd(t, s):
        o = ((side * tracks + t) * sectors + (s - 1)) * SECSZ
        return raw[o:o + SECSZ]

    def valid(t, s):
        return 0 <= t < tracks and 1 <= s <= sectors

    used = set()
    dt, ds, guard = DIR_TRACK, DIR_SECTOR, 0
    while guard < 128 and valid(dt, ds):
        guard += 1
        dirs = rd(dt, ds)
        used.add((dt, ds))
        for e in range(16, SECSZ, 16):
            if dirs[e] == 0 and dirs[e + 15] == 0:
                continue
            if dirs[e + 15] & 0x80:            # supprimé
                continue
            cdt, cds, dg, first = dirs[e + 12], dirs[e + 13], 0, True
            while dg < 128 and valid(cdt, cds):
                dg += 1
                desc = rd(cdt, cds)
                used.add((cdt, cds))
                p = 12 if first else 2
                while p + 1 < SECSZ:
                    if desc[p] == 0 and desc[p + 1] == 0:
                        break
                    if valid(desc[p], desc[p + 1]):
                        used.add((desc[p], desc[p + 1]))
                    p += 2
                if desc[0] == 0 and desc[1] == 0:
                    break
                cdt, cds, first = desc[0], desc[1], False
        if dirs[0] == 0 and dirs[1] == 0:
            break
        dt, ds = dirs[0], dirs[1]
    return used


def _geometry(tracks, sectors, first_track, config_sectors=2, skip_tracks=(), total_tracks=None):
    """Géométrie où les pistes 1..first_track-1 sont RÉSERVÉES (le DOS Sedoric occupe
    les pistes basses hors catalogue — écrire dessus casse le LOAD), la story commence
    à `first_track` avec `config_sectors` réservés pour la piste de config.
    `skip_tracks` : pistes supplémentaires réservées EN MILIEU de zone story (piste
    système Sedoric 20 + pistes du fichier interpréteur AUTO) — place_story les saute
    et readblock aussi (octet disk_info = 0 => .next_track). Permet un GROS jeu dont la
    story s'étale au-delà de la piste système/interp (ex. HHGG : 15-19 + 27..).
    `total_tracks` : nb TOTAL de pistes de l'espace LINÉAIRE (défaut = `tracks`). Pour la
    FACE 1 : passer 2*tracks → les pistes linéaires `tracks..2*tracks-1` (face 1, vide sur
    un master Sedoric mono-face) sont LIBRES (rs=0). read_track_sector mappe piste
    linéaire >= TRACKS_PER_SIDE(=tracks) sur la face 1 (piste physique = lin - tracks)."""
    n = total_tracks if total_tracks else tracks
    tl = [0] + [sectors] * (n - 1)
    rs = [0] * n
    for t in range(1, first_track):
        rs[t] = sectors                        # piste pleine = sautée par place_story
    rs[first_track] = config_sectors           # piste config = story - 2 secteurs
    for t in skip_tracks:                       # système + interp = pleines (sautées)
        if 0 <= t < n:
            rs[t] = sectors
    # Pistes de la face 1 (>= tracks) laissées LIBRES (rs=0 déjà) : face vide.
    return od.Geometry(track_length=tl, reserved_sectors=rs, interleave=0)


def build(master, interp_bin, story_path, out_dsk, name="OZMOO",
          game_id=b"\x00OZM", conf_trk=15, sectors=17):
    story = open(story_path, "rb").read()
    interp = open(interp_bin, "rb").read()

    # 1) master MFM -> raw side-major (+ géométrie réelle)
    buf = open(master, "rb").read()
    sides, tracks, sectors, raw = mfm2raw.parse_mfm(buf, sectors)
    raw = bytearray(raw)
    print(f"master {master}: sides={sides} tracks={tracks} sectors={sectors}")

    def off(side, t, s):       # s : index 0-based dans la piste
        return ((side * tracks + t) * sectors + s) * SECSZ

    # 2) carte des secteurs occupés par le DOS/fichiers (catalogue Sedoric).
    #    On NE touche PAS au disque (le DOS Sedoric vit sur quelques pistes — ex.
    #    7-10 + 0 + 20 sur SEDO40u ; l'effacer casse le LOAD). On écrit la story
    #    uniquement sur des pistes catalogue-LIBRES.
    used = _catalog_used(raw, tracks, sectors)
    used_tracks = sorted(set(t for (t, s) in used))
    print(f"catalogue : {len(used)} secteurs occupés, pistes {used_tracks}")

    # 4) placement story + piste config (secteurs bruts, pistes libres)
    # IMPORTANT : le disque ne contient QUE la portion STATIQUE (la story après la
    # mémoire dynamique). La dynmem (nonstored_pages) est chargée à part via le fichier
    # AUTO. readblock lit le bloc `currentblock - nonstored_pages` → disque bloc 0 = 1er
    # bloc statique (cf. make.rb : $story_file_cursor = $dynmem_blocks * $VMEM_BLOCKSIZE).
    nonstored_pages, dynmem_blocks, total_blocks = od.story_vmem_layout(story)
    story_static = story[nonstored_pages * SECSZ:]
    nblocks = (len(story_static) + SECSZ - 1) // SECSZ

    # Empreinte du fichier interpréteur AUTO (interp + dynmem) : sedoric_inject l'alloue
    # À PARTIR de la piste 21, contigu (hors catalogue). On calcule les pistes qu'il
    # occupera pour les RÉSERVER (avec la piste système 20) → la story les saute. Permet
    # un GROS jeu dont la story s'étale au-delà (ex. HHGG : pistes 15-19 puis 27..).
    INTERP_START_TRACK, DIR_TRACK = 21, 20
    auto_size = len(interp) + nonstored_pages * SECSZ
    ndata = (auto_size + SECSZ - 1) // SECSZ
    FIRST_CAP, CONT_CAP = (SECSZ - 12) // 2, (SECSZ - 2) // 2   # cf. sedoric_inject
    ndesc = 1 if ndata <= FIRST_CAP else 1 + -(-(ndata - FIRST_CAP) // CONT_CAP)
    interp_sectors = ndesc + ndata
    interp_last_track = INTERP_START_TRACK + (interp_sectors - 1) // sectors
    skip = {DIR_TRACK} | set(range(INTERP_START_TRACK, interp_last_track + 1))

    # Story sur les pistes HAUTES libres : pistes basses (≈1-14) réservées au DOS,
    # piste système 20 + pistes du fichier interp réservées (sautées). `conf_trk` = 1re
    # piste story/config (doit == -DCONF_TRK du build).
    # Espace de pistes LINÉAIRE sur 2 faces : 0..2*tracks-1 (face 0 puis face 1). La
    # face 1 (>= tracks) est vide → libre. read_track_sector (interp, TRACKS_PER_SIDE=
    # tracks) mappe piste linéaire >= tracks sur la face 1.
    geo = _geometry(tracks, sectors, first_track=conf_trk,
                    config_sectors=od.CONFIG_SECTORS, skip_tracks=skip, total_tracks=2 * tracks)
    p = od.place_story(nblocks, geo)
    if len(p.blocks) < nblocks:
        sys.exit(f"story trop grande : {len(p.blocks)}/{nblocks} blocs placés (2 faces pleines)")
    story_tracks = sorted(set(t for (t, s) in p.blocks) | {conf_trk})
    last_story_track = max(story_tracks)
    side1_tracks = [t for t in story_tracks if t >= tracks]
    print(f"interp AUTO ~{interp_sectors} sect -> pistes {INTERP_START_TRACK}-{interp_last_track} "
          f"(réservées) ; piste système {DIR_TRACK} sautée")
    if side1_tracks:
        print(f"story DÉBORDE sur la FACE 1 : pistes linéaires {side1_tracks[0]}-{side1_tracks[-1]} "
              f"(= face 1 physiques {side1_tracks[0]-tracks}-{side1_tracks[-1]-tracks})")
    # sécurité : les pistes story/config de la FACE 0 doivent être LIBRES (le catalogue
    # DOS est en face 0 ; la face 1 est vide). L'effacement des overlays DOS casse le LOAD.
    collide = [t for t in story_tracks if t < tracks
               and any((t, s) in used for s in range(1, sectors + 1))]
    if collide:
        sys.exit(f"pistes story/config {collide} occupées par le DOS/fichiers — "
                 "choisir un master avec pistes basses libres ou étendre le placement")

    di_full = od.build_full_disk_info(p.config_track_map, interleave=0)
    ver = story[0]
    di_cap = 71 if ver < 4 else 200   # cf. disk.asm !fill (Oric : 200 o pour V4+, story 2-faces)
    if len(di_full) > di_cap:
        sys.exit(f"disk_info trop grand ({len(di_full)} o > {di_cap} o pour V{ver}) — story "
                 f"étalée sur trop de pistes ({last_story_track}). Réduire la fragmentation "
                 "(placement plus compact) ou augmenter le buffer disk_info.")
    vmem_data = od.build_vmem_data(dynmem_blocks, total_blocks)
    cfg = od.build_config_track_bytes(list(game_id), di_full, vmem_data)
    cfg_cap = od.CONFIG_SECTORS * SECSZ
    if len(cfg) > cfg_cap:
        sys.exit(f"piste config trop grande ({len(cfg)} o > {cfg_cap}) — "
                 f"game_id+disk_info+vmem_data dépasse {od.CONFIG_SECTORS} secteurs.")

    # écrit les blocs story STATIQUES (dynmem exclue). Piste LINÉAIRE t -> (face, piste
    # physique) = (t // tracks, t % tracks) : face 0 pour t < tracks, face 1 au-delà.
    for n, (t, s) in enumerate(p.blocks):
        blk = story_static[n * SECSZ:(n + 1) * SECSZ]
        blk = blk + bytes(SECSZ - len(blk))
        o = off(t // tracks, t % tracks, s)
        raw[o:o + SECSZ] = blk
    # écrit la piste config (od.CONFIG_SECTORS secteurs 0-based) sur conf_trk
    padded = bytes(cfg) + bytes(cfg_cap - len(cfg))
    for si in range(od.CONFIG_SECTORS):
        o = off(0, conf_trk, si)
        raw[o:o + SECSZ] = padded[si * SECSZ:(si + 1) * SECSZ]
    print(f"story {len(story)}o -> {nblocks} blocs (pistes {conf_trk}-{last_story_track}), "
          f"config piste {conf_trk} ({len(cfg)}o), dynmem={dynmem_blocks} blocs, "
          f"statiques {dynmem_blocks}..{total_blocks - 1}")

    # 5) fichier AUTO = interp + dynmem (chargé à story_start=$3400)
    dynmem = od.story_dynmem_prefix(story)
    auto = interp + dynmem
    tmp_raw = out_dsk + ".raw"
    tmp_auto = out_dsk + ".auto"
    tmp_raw2 = out_dsk + ".raw2"
    open(tmp_raw, "wb").write(bytes(raw))
    open(tmp_auto, "wb").write(auto)
    print(f"fichier AUTO = interp {len(interp)}o + dynmem {len(dynmem)}o = {len(auto)}o "
          f"(load/exec $0500)")

    # 6) injection Sedoric (fichier AUTO + INIST autoexec)
    nm = (name.split(".")[0] + ".COM") if "." not in name else name
    init_cmd = f'LOAD"{nm.split(".")[0]}"'
    r = subprocess.run([sys.executable, os.path.join(ORIC_TOOLS, "sedoric_inject.py"),
                        tmp_raw, tmp_auto, "500", nm, tmp_raw2,
                        str(tracks), str(sectors), init_cmd, "500"],
                       capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.exit("sedoric_inject a échoué")

    # 7) raw -> MFM
    r2m = _load("dsk_raw2mfm", os.path.join(ORIC_TOOLS, "dsk_raw2mfm.py"))
    raw2 = open(tmp_raw2, "rb").read()
    hdr = bytearray(b"MFM_DISK")
    import struct
    hdr += struct.pack("<I", sides) + struct.pack("<I", tracks) + struct.pack("<I", 1)
    hdr += b"\x00" * (256 - len(hdr))
    outb = bytearray(hdr)
    for side in range(sides):
        for t in range(tracks):
            block = side * tracks + t
            base = block * sectors * SECSZ
            secs = [raw2[base + i * SECSZ: base + (i + 1) * SECSZ] for i in range(sectors)]
            outb += r2m.build_track(t, side, secs)
    open(out_dsk, "wb").write(outb)
    for f in (tmp_raw, tmp_auto, tmp_raw2):
        os.remove(f)
    print(f"OK -> {out_dsk} ({len(outb)}o) — INIST={init_cmd}")


def main():
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    master, interp_bin, story_path, out_dsk = sys.argv[1:5]
    name = sys.argv[5] if len(sys.argv) > 5 else "OZMOO"
    game_id = bytes.fromhex(sys.argv[6]) if len(sys.argv) > 6 else b"\x00OZM"
    conf_trk = int(sys.argv[7]) if len(sys.argv) > 7 else 1
    build(master, interp_bin, story_path, out_dsk, name, game_id, conf_trk)


if __name__ == "__main__":
    main()
