#!/usr/bin/env python3
"""oric_disk.py — socle du constructeur de disque VMEM Oric (voie A).

Porte fidèlement, en Python, les DEUX algorithmes clés d'Ozmoo :

  * placement des blocs story sur le disque  (make.rb : Disk#add_story_data)
  * mapping bloc VMEM -> (piste, secteur)     (asm/disk.asm : readblock)

Les deux partagent la même logique d'interleave ; un test de cohérence
aller-retour (place_story -> readblock_map) prouve que le portage est fidèle
et que la structure `disk_info` produite est celle qu'attend l'interpréteur.

C'est le socle réutilisable de la voie A (VMEM + disque). Étapes suivantes :
en-tête config + assemblage disk_info complet, écriture MFM Oric, boot loader.

Références :
  make.rb  Disk#add_story_data (L360-442), build_S1 disk_info (L1718-1725)
  disk.asm readblock (L134-317)  [disk_info+8,x : bits0-5=secteurs, bits6-7=sautés/2]
"""
from dataclasses import dataclass, field


@dataclass
class Geometry:
    """Géométrie d'un disque + réservations. Pistes 1-based (piste 0 non utilisée
    par la story ; réservée boot/format selon la cible)."""
    track_length: list          # track_length[t] = nb secteurs sur la piste t
    reserved_sectors: list      # reserved_sectors[t] = secteurs réservés (config/dir)
    interleave: int = 0

    @property
    def tracks(self):
        return len(self.track_length) - 1  # index 0 inutilisé


# Géométrie Sedoric standard (confirmée par « Sedoric 3.0 à nu » + dsk_raw2mfm) :
#   2 faces x 42 pistes x 17 secteurs x 256 o. Secteurs 1-based (IDs 1..17).
#   read_track_sector reçoit un secteur 0-based (readblock) et ajoute +1 -> ID
#   physique. Le skew physique (pistes commençant aux secteurs 1,14,10,6,2...) est
#   une optimisation de latence ignorée par dsk_raw2mfm (IDs posés 1..17 en ordre) :
#   sans impact sur la correction (le WD1793 trouve un secteur par son ID). Piste 20
#   = piste système Sedoric (à éviter si le disque doit rester Sedoric-compatible).
SEDORIC_SIDES, SEDORIC_TRACKS_PER_SIDE, SEDORIC_SECTORS = 2, 42, 17


def default_microdisc(tracks=41, sectors=17, config_track=1, config_sectors=2,
                      interleave=0):
    """Géométrie Microdisc/Sedoric simplifiée mono-face : pistes 1..tracks,
    `sectors` secteurs/piste, `config_sectors` secteurs réservés sur la piste
    config pour disk_info. (piste 0 laissée hors story)."""
    tl = [0] + [sectors] * tracks
    rs = [0] * (tracks + 1)
    rs[config_track] = config_sectors
    return Geometry(track_length=tl, reserved_sectors=rs, interleave=interleave)


# --------------------------------------------------------------------------
# 1) PLACEMENT (port de make.rb Disk#add_story_data, sans add_at_end)
# --------------------------------------------------------------------------
@dataclass
class Placement:
    blocks: list = field(default_factory=list)   # [(track, sector)] par bloc story
    config_track_map: list = field(default_factory=list)  # octet par piste (disk_info+8..)
    first_story_track: int = 1
    story_blocks: int = 0


def place_story(num_sectors, geo: Geometry):
    """Place `num_sectors` blocs story et renvoie un Placement.
    Port fidèle de la boucle make.rb (interleave, secteurs réservés au début)."""
    p = Placement(first_story_track=1)
    itl = geo.interleave
    remaining = num_sectors
    for track in range(1, geo.tracks + 1):
        if remaining <= 0:
            p.config_track_map.append(0)
            continue
        reserved = geo.reserved_sectors[track]
        sector_count = geo.track_length[track]
        if track < p.first_story_track:
            sector_count = reserved
        elif sector_count - reserved > remaining:
            sector_count = remaining + reserved
        track_map = [0] * sector_count
        for i in range(reserved):
            track_map[i] = 1
        free_in_track = sector_count - reserved
        last_story_sector = 0
        sector = 0
        for _ in range(min(free_in_track, remaining)):
            while track_map[sector] != 0:
                sector = (sector + 1) % sector_count
            track_map[sector] = 1
            p.blocks.append((track, sector))
            last_story_sector += 1
            remaining -= 1
            p.story_blocks += 1
            sector = (sector + itl) % sector_count
        # octet disk_info pour cette piste
        if reserved == sector_count:
            p.config_track_map.append(0)
        elif reserved % 2 == 0 and reserved <= 6:
            p.config_track_map.append(64 * (reserved // 2) + last_story_sector)
        else:
            raise ValueError(f"reserved_sectors invalide piste {track}: {reserved}")
    # supprime les zéros de fin (make.rb : reverse.drop_while(0).reverse)
    while p.config_track_map and p.config_track_map[-1] == 0:
        p.config_track_map.pop()
    return p


# --------------------------------------------------------------------------
# 2) disk_info d'un disque (port de build_S1, L1718-1725)
# --------------------------------------------------------------------------
def build_disk_info_entry(config_track_map, device=0):
    """Renvoie l'entrée disk_info d'un disque (hors nom), telle que lue par
    readblock : [taille, device, lastblock+1_hi, lastblock+1_lo, nb_pistes] + map."""
    last_block_plus_1 = sum(b & 0x3f for b in config_track_map)
    size = 11 + len(config_track_map)   # 5 en-tête + map + 6 octets nom
    return {
        "size": size,
        "device": device,
        "last_block_plus_1": last_block_plus_1,
        "track_bytes": list(config_track_map),
    }


# --------------------------------------------------------------------------
# 2bis) disk_info COMPLET (préambule global + entrée save + entrée story)
# --------------------------------------------------------------------------
# Structure réelle lue par disk.asm (déduite de make.rb config_data + build_S1) :
#   disk_info+0 : interleave
#   disk_info+1 : save slots
#   disk_info+2 : nombre de disques (2 = save + story)
#   disk_info+3.. : entrées disque. Chaque entrée (indexée par x, memory index) :
#     +0 taille (offset vers l'entrée suivante), +1 device, +2/+3 lastblock+1 (hi,lo),
#     +4 nb pistes, +5.. octets/piste puis nom (longueur = taille - 5 - nbpistes).
# L'entrée 0 est le DISQUE DE SAUVEGARDE (8 octets, lastblock+1=0, 0 piste) ; la
# story est donc sur le disque d'indice 1. C'est indispensable : la track-walk de
# readblock n'obtient `.blocks_to_go` en big-endian (ordre qu'elle attend) qu'après
# être passée par une entrée précédente via `.next_disk` (cf. FINDING v0.21.0).
#
# NB : le nom d'un disque n'a PAS une longueur fixe (save = 3 octets, story = 6) ;
# c'est le champ « taille » qui pilote le saut d'une entrée à l'autre.

# Valeurs de nom neutres (l'interpréteur ne s'en sert que pour l'affichage).
SAVE_ENTRY_NAME = [ord('S'), ord('D'), 0]          # « Save disk » (3 octets)
STORY_ENTRY_NAME = [ord('B'), ord('/'), ord(' '), ord('S'), ord('D'), 0]  # 6 octets


def build_full_disk_info(config_track_map, device=0, interleave=0, save_slots=1,
                         save_name=None, story_name=None):
    """Construit le `disk_info` COMPLET (liste d'octets) tel que l'interpréteur le
    reçoit en RAM : préambule + entrée save (index 0) + entrée story (index 1).
    C'est la structure à écrire dans la piste de config et à valider on-Oric."""
    if save_name is None:
        save_name = SAVE_ENTRY_NAME
    if story_name is None:
        story_name = STORY_ENTRY_NAME
    story = build_disk_info_entry(config_track_map, device)
    lb = story["last_block_plus_1"]
    story_size = 5 + len(config_track_map) + len(story_name)
    save_size = 5 + 0 + len(save_name)
    di = [interleave, save_slots, 2]
    # entrée 0 : disque de sauvegarde (aucune piste, lastblock+1 = 0)
    di += [save_size, device, 0, 0, 0] + list(save_name)
    # entrée 1 : disque story
    di += ([story_size, device, lb >> 8, lb & 0xff, len(config_track_map)]
           + list(config_track_map) + list(story_name))
    return di


# --------------------------------------------------------------------------
# 3) LECTEUR (port de asm/disk.asm readblock, mono-disque)
# --------------------------------------------------------------------------
def readblock_map(block, disk_info_entry, interleave=0, nonstored_pages=0):
    """Reproduit readblock : bloc VMEM -> (piste, secteur). Mono-disque.
    disk_info_entry = sortie de build_disk_info_entry."""
    adjusted = block - nonstored_pages
    if adjusted >= disk_info_entry["last_block_plus_1"]:
        raise IndexError(f"bloc {block} au-delà de la story (adjusted={adjusted})")
    blocks_to_go = adjusted
    track_bytes = disk_info_entry["track_bytes"]
    # trouve la piste
    track = 1
    for byte in track_bytes:
        if byte == 0:
            track += 1
            continue
        sectors_used = byte & 0x3f
        if blocks_to_go - sectors_used < 0:
            logical_sector = blocks_to_go       # index logique dans la piste
            break
        blocks_to_go -= sectors_used
        track += 1
    else:
        raise IndexError("piste introuvable")
    # trouve le secteur physique (interleave + secteurs sautés au début)
    skip = (byte >> 5) & 0x06
    sector_count = (byte & 0x3f) + skip
    track_map = [0xff] * skip + [0] * ((byte & 0x3f))
    target = logical_sector
    sector = 0
    while True:
        while track_map[sector] != 0:
            sector = (sector + 1) % sector_count
        target -= 1
        if target < 0:
            return (track, sector)
        track_map[sector] = 0xff
        sector = (sector + interleave) % sector_count


def readblock_full(block, di, nonstored_pages=0, check_errors=True):
    """Port FIDÈLE du readblock multi-disque de disk.asm sur le `disk_info`
    complet (sortie de build_full_disk_info). Reproduit octet par octet :
      - la disk-walk (compare le bloc à chaque lastblock+1 ; le passage par une
        entrée non retenue réordonne `.blocks_to_go` en big-endian) ;
      - la track-walk (attend `.blocks_to_go` big-endian : +1 = poids faible) ;
      - la recherche du secteur physique (interleave + secteurs sautés).
    Renvoie (piste, secteur 0-based). Valide la structure telle que la lira l'Oric."""
    interleave = di[0]
    ndisks = di[2]
    cur = block - nonstored_pages
    adj_lo, adj_hi = cur & 0xff, (cur >> 8) & 0xff
    btg = [adj_lo, adj_hi]      # .blocks_to_go : [+0, +1]
    x, y = 0, 0
    while True:
        # .check_next_disk — utilise toujours currentblock_adjusted (inchangé)
        next_disk_index = (x + di[3 + x]) & 0xff
        t = adj_lo - di[6 + x]                 # sbc lastblock+1 lo  -> tmp+1
        tmp1, carry = t & 0xff, 1 if t >= 0 else 0
        t2 = adj_hi - di[5 + x] - (1 - carry)  # sbc lastblock+1 hi  -> tmp+0
        tmp0, carry2 = t2 & 0xff, 1 if t2 >= 0 else 0
        if carry2 == 0:                        # bcc -> disque trouvé
            break
        btg[0], btg[1] = tmp0, tmp1            # réordonnancement big-endian
        x = next_disk_index
        y += 1
        if check_errors and y >= ndisks:
            raise IndexError(f"bloc {block} au-delà de la story (out of memory)")
    # .right_disk_found — track-walk
    disk_tracks = di[7 + x]
    track = 1
    while True:
        byte = di[8 + x]
        if byte == 0:
            x += 1
            track += 1
            disk_tracks -= 1
            if disk_tracks == 0:
                raise IndexError("config incorrecte : piste introuvable")
            continue
        sector = byte & 0x3f
        t = btg[1] - sector                    # .blocks_to_go+1 - sectors
        tmp1, carry = t & 0xff, 1 if t >= 0 else 0
        t2 = btg[0] - (1 - carry)              # .blocks_to_go+0 - borrow
        tmp0, carry2 = t2 & 0xff, 1 if t2 >= 0 else 0
        if carry2 == 0:                        # bcc -> piste trouvée
            break
        btg[0], btg[1] = tmp0, tmp1
        x += 1
        track += 1
        disk_tracks -= 1
        if disk_tracks == 0:
            raise IndexError("config incorrecte : piste introuvable")
    # .right_track_found — secteur physique (identique à readblock_map)
    logical_sector = btg[1]
    skip = (byte >> 5) & 0x06
    sector_count = (byte & 0x3f) + skip
    track_map = [0xff] * skip + [0] * (byte & 0x3f)
    target, sec = logical_sector, 0
    while True:
        while track_map[sec] != 0:
            sec = (sec + 1) % sector_count
        target -= 1
        if target < 0:
            return (track, sec)
        track_map[sec] = 0xff
        sec = (sec + interleave) % sector_count


# --------------------------------------------------------------------------
# 4) ÉCRITURE d'une image disque brute (story placée) + disk_info
# --------------------------------------------------------------------------
def raw_offset(side, track, sector, sectors_per_track=SEDORIC_SECTORS):
    """Offset fichier d'un secteur dans l'image BRUTE side-major (ordre lu par
    Phosphoric via dsk_raw2mfm : position = side*tracks + track). `sector` est
    l'index 0-based dans la piste ; l'ID physique MFM sera sector+1."""
    return ((side * SEDORIC_TRACKS_PER_SIDE + track) * sectors_per_track + sector) * 256


def build_disk(story_bytes, geo: Geometry, device=0):
    """Construit l'image disque BRUTE (side-major, 2x42x17x256) avec les blocs
    story placés aux (piste, secteur) calculés, et renvoie (raw_image, disk_info,
    placement). `disk_info` = entrée prête pour l'interpréteur (dict).
    Story sur la face 0 (pistes 1..41) ; suppose que la story tient sur une face."""
    nblocks = (len(story_bytes) + 255) // 256
    p = place_story(nblocks, geo)
    if len(p.blocks) < nblocks:
        raise ValueError(f"disque trop petit : {len(p.blocks)}/{nblocks} blocs placés")
    total = SEDORIC_SIDES * SEDORIC_TRACKS_PER_SIDE * SEDORIC_SECTORS * 256
    raw = bytearray(total)
    for n, (track, sector) in enumerate(p.blocks):
        block = story_bytes[n * 256:(n + 1) * 256]
        block = block + bytes(256 - len(block))     # padding dernier bloc
        off = raw_offset(0, track, sector)
        raw[off:off + 256] = block
    return bytes(raw), build_disk_info_entry(p.config_track_map, device), p


# --------------------------------------------------------------------------
# Test de cohérence aller-retour
# --------------------------------------------------------------------------
def _roundtrip_test():
    ok = 0
    for interleave in (0, 1, 3, 5):
        for nsec in (1, 2, 16, 17, 18, 34, 35, 100, 300):
            geo = default_microdisc(tracks=41, sectors=17, config_track=1,
                                    config_sectors=2, interleave=interleave)
            p = place_story(nsec, geo)
            entry = build_disk_info_entry(p.config_track_map)
            for block, (t, s) in enumerate(p.blocks):
                got = readblock_map(block, entry, interleave=interleave)
                assert got == (t, s), (
                    f"interleave={interleave} nsec={nsec} bloc={block}: "
                    f"placé en {(t, s)} mais readblock donne {got}")
                ok += 1
    print(f"OK: {ok} blocs vérifiés (placement <-> readblock coïncident)")
    return ok


def _disk_data_test():
    """Vérifie qu'une image disque construite se relit correctement : pour chaque
    bloc N, readblock_map(N) -> (piste, secteur) -> octets à cet emplacement dans
    l'image brute == bloc N de la story. Prouve placement+disk_info+écriture cohérents."""
    checks = 0
    for interleave in (0, 1, 3):
        geo = default_microdisc(tracks=41, sectors=17, config_track=1,
                                config_sectors=0, interleave=interleave)
        # story synthétique : bloc N -> 256 octets = (N, N+1, ...) & 0xff
        nblocks = 200
        story = bytes(((n + i) & 0xff) for n in range(nblocks) for i in range(256))
        raw, info, p = build_disk(story, geo)
        for n in range(nblocks):
            track, sector = readblock_map(n, info, interleave=interleave)
            off = raw_offset(0, track, sector)
            assert raw[off:off + 256] == story[n * 256:(n + 1) * 256], \
                f"interleave={interleave} bloc {n}: relecture incorrecte"
            checks += 1
    print(f"OK: {checks} blocs relus depuis l'image disque == story (placement+écriture+readblock)")
    return checks


def _full_disk_info_test():
    """Valide le walk COMPLET (save+story) : pour chaque bloc placé sur le disque
    story, readblock_full (via le disk_info réel à 2 disques) retrouve exactement
    la (piste, secteur) du placement. Prouve que la structure que lira l'Oric —
    avec l'entrée save en tête qui déclenche le byte-swap big-endian — est correcte.
    C'est le cas que le harnais mono-disque ne pouvait pas couvrir (FINDING v0.21.0)."""
    checks = 0
    for interleave in (0, 1, 3, 5):
        for nsec in (1, 2, 16, 17, 18, 34, 100, 300, 600):
            geo = default_microdisc(tracks=41, sectors=17, config_track=1,
                                    config_sectors=2, interleave=interleave)
            p = place_story(nsec, geo)
            di = build_full_disk_info(p.config_track_map, interleave=interleave)
            for block, (t, s) in enumerate(p.blocks):
                got = readblock_full(block, di)
                assert got == (t, s), (
                    f"interleave={interleave} nsec={nsec} bloc={block}: "
                    f"placé en {(t, s)} mais readblock_full donne {got}")
                checks += 1
    print(f"OK: {checks} blocs vérifiés via disk_info COMPLET (save+story, walk multi-disque)")
    return checks


def disk_info_bytes(info, name_bytes=None):
    """Sérialise l'entrée disk_info (comme make.rb build_S1) :
    [taille, device, lastblock+1_hi, lastblock+1_lo, nbpistes] + octets/piste + nom(6)."""
    if name_bytes is None:
        name_bytes = [0, 0, 0, 0, 0, 0]   # nom neutre (6 octets)
    lb = info["last_block_plus_1"]
    return ([info["size"], info["device"], lb >> 8, lb & 0xff,
             len(info["track_bytes"])] + list(info["track_bytes"]) + list(name_bytes))


def _cli(argv):
    import sys
    if len(argv) < 3:
        print("usage: oric_disk.py <story.z*> <out.raw> [interleave]\n"
              "  construit une image BRUTE side-major (à convertir en MFM via "
              "dsk_raw2mfm.py) ; imprime les octets disk_info.")
        return 1
    story = open(argv[1], "rb").read()
    interleave = int(argv[3]) if len(argv) > 3 else 0
    geo = default_microdisc(tracks=41, sectors=17, config_track=1,
                            config_sectors=0, interleave=interleave)
    raw, info, p = build_disk(story, geo)
    open(argv[2], "wb").write(raw)
    di = disk_info_bytes(info)
    full = build_full_disk_info(p.config_track_map, interleave=interleave)
    print(f"story={len(story)}o -> {len(p.blocks)} blocs, image brute {len(raw)}o -> {argv[2]}")
    print(f"1ers blocs (bloc->piste,secteur): "
          + ", ".join(f"{n}->{p.blocks[n]}" for n in range(min(6, len(p.blocks)))))
    print(f"disk_info entrée story ({len(di)} octets) = " + " ".join(f"{b:02x}" for b in di))
    print(f"disk_info COMPLET ({len(full)} octets, préambule+save+story) = "
          + " ".join(f"{b:02x}" for b in full))
    return 0


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        sys.exit(_cli(sys.argv))
    _roundtrip_test()
    _disk_data_test()
    _full_disk_info_test()
