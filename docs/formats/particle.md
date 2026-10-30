---
type: file-format
format: particle.ini
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: "GameData/Render/particle.ini (+ particle.dat, particle.fsh)"
count: "1 soubor, 62 systémů"
encoding: "text, INI (latin1)"
status: partial
tool: "tools/particles.py (→ decomposed/GameData/Render/particles.json)"
updated: 2026-10-30
---

# Částicové systémy (`GameData/Render/particle.ini`)

Textový popis 62 částicových systémů: kouř komínů, pára, vodopády a peřeje, fontány, hydranty, jiskry svářečů a oceláren, výbuch bedny, výfuk auta a jiskry. Textury jsou v `particle.fsh` (18 obrázků 16–64 px, převádí `fsh2png.py` do `decomposed/GameData/Render/particle/`). `particle.dat` je binární, nejspíš totéž ve formátu pro hru (nerozluštěno). Převod: `python3 tools/particles.py sources/GameData/Render/particle.ini decomposed/GameData/Render/particles.json`.

## Struktura

`[header]` s `numSystems=62`, pak sekce `[system#000]` … `[system#061]`. Každá má 35 klíčů (`randlifetime` jen dvě), pořadí klíčů se mezi sekcemi liší.

| Klíč | Význam | Jistota |
| --- | --- | --- |
| `name` | jméno (opakuje se: 3× `Sparks`, 2× `WelderSparks` …) | jisté |
| `tag` | ID systému, čtyři znaky little-endian (`1263685715` = `SPRK`). Klíč zdrojů částic `ef` druhu 3 v tratích (`HYDR`, `CSF1`, `BEXP`, `TRSH`, [crp.md](crp.md#efekty-ef-článku)) | jisté |
| `matid` | textura v `particle.fsh`, čtyři znaky **big-endian** (`1397772875` = `SPRK`); všech 62 existuje | jisté |
| `inUse` | 1 u všech | |
| `numparticles` | počet částic (11–50) | pravděpodobné |
| `blendmode` | 0 / 1 / 2; jiskry `SPRK` 0, `SMOK` 1, textury na černém pozadí (SMX1, SPRK) → nejspíš sčítání | odhad |
| `emit.x/y/z` | počáteční rychlost (jiskry 0,06–0,1 nahoru, vodopády desítky) | odhad, jednotka neznámá |
| `randemit.x/y/z` | náhodný rozptyl rychlosti | odhad |
| `startsize`, `endsize` | velikost na začátku a konci života | pravděpodobné |
| `overallsize`, `overallspeed` | 0 / 1, příznaky? | neznámé |
| `lifetime`, `randlifetime` | životnost (4–650), nejspíš tiky | odhad |
| `weight`, `randweight` | gravitace (záporná u kouře a páry stoupá) | pravděpodobné |
| `startrotation`, `endrotation`, `randrotation` | rotace | pravděpodobné |
| `numstates`, `color.0`–`color.3` | barvy v průběhu života, ARGB se znaménkem (`-1` = bílá neprůhledná, `16750848` = `#00ff9900` průhledná oranžová) | jisté |
| `numframes`, `framespeed` | animace textury (1 snímek u všech) | |
| `flags`, `airFriction`, `zbias`, `periodOn`, `periodOff`, `primeTicks`, `volumeScalePct` | | neznámé |

## Jiskry

| # | tag | Částic | Velikost | Váha | Barvy |
| --- | --- | --- | --- | --- | --- |
| 0, 32 | `SMOK` | 20 | 0,3 → 1,0 | 0,1 | bílá → černá (kouř po jiskrách?) |
| 2 | `SPRK` | 47 | 0,15 → 0,25 | 0,3 | bílá → průhledná oranžová `#ff9900` |

Hra bere ze `SPRK` počet a barvy jisker auta (D-028). Rychlost a životnost má vlastní, protože jednotky nejsou ověřené.
