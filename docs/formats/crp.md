---
type: file-format
format: crp
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: ["GameData/CarModel/*.crp", "GameData/Track/*.crp", "FEData/Models/*.crp"]
compression: "EA RefPack (QFS), magic 0x10FB"
status: "komprese hotová, kontejner částečně, geometrie neznámá"
tool: "tools/refpack.py"
updated: 2026-10-15
---

# Formát `.crp` – modely aut a tratí

## 1. Komprese (hotovo)

Soubor začíná `10 FB` + 3 B velikost rozbalených dat (big-endian), následuje proud RefPack.
`tools/refpack.py` rozbalí auto (`356a.crp`: 3 764 224 B) i trať (`alps.crp`: 6 168 576 B) s přesnou shodou deklarované velikosti.

## 2. Kontejner (částečně)

Little-endian. Čtyřznakové značky jsou uložené obráceně (`" raC"` = `"Car "`).

| Offset | Typ | Význam |
| --- | --- | --- |
| 0x00 | char[4] | `Car ` (auto) nebo `Trak` (trať) |
| 0x04 | u32 | ? (auto `0x16BA`, trať `0xDB1A`) |
| 0x08 | u32 | počet článků (auto 87, trať 286) |
| 0x0C | u32 | ? |
| 0x10 | article[n] | 16 B na článek: tag `Arti`, u32 typ (0x1A), u32 počet záznamů, u32 offset v jednotkách 16 B |

Článek ukazuje na tabulku 16bajtových záznamů. Záznam obsahuje dvouznakový typ (`vt`, `fs`, `n$`, `rp`, `uv` ...), počet prvků a offset dat. Pravděpodobně: `vt` vrcholy, `uv` texturové souřadnice, `rp` části/materiály.

V datech se dále vyskytují bloky `Base`, `Name`, `RMth`, `BndP`. U tratí navíc `CNK0`/`CNK1` (segmenty), `OBJE`/`OBJ0` (objekty), `MESH`, `CLIF` (útesy), `SHRU` (vegetace), `Anim`, `SimD`, `SimT`, `Vis `, `Desc`.

## 3. Geometrie (k dopsání)

Referenční implementace: [OpenNFS](https://github.com/OpenNFS/OpenNFS) (auta NFS5 ~40 %). Cíl: konvertor auta do glTF pro soukromou vizuální referenci. Geometrie tratí má nízkou prioritu (D-005).
