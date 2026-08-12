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


if __name__ == "__main__":
    _roundtrip_test()
