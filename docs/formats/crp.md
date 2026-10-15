---
type: file-format
format: crp
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: ["GameData/CarModel/*.crp", "GameData/Track/*.crp", "FEData/Models/*.crp"]
compression: "EA RefPack (QFS), magic 0x10FB"
status: "komprese, kontejner a geometrie aut hotové; tratě neznámé"
tool: ["tools/refpack.py", "tools/crp2gltf.py"]
updated: 2026-10-15
---

# Formát `.crp` – modely aut a tratí

## 1. Komprese (hotovo)

Soubor začíná `10 FB` + 3 B velikost rozbalených dat (big-endian), následuje proud RefPack.
`tools/refpack.py` rozbalí auto (`356a.crp`: 3 764 224 B) i trať (`alps.crp`: 6 168 576 B) s přesnou shodou deklarované velikosti.

## 2. Kontejner (hotovo pro auta)

Little-endian. Struktura podle CrpLib z [LibOpenNFS](https://github.com/OpenNFS/LibOpenNFS) (MIT), ověřená na všech 44 autech.

### Hlavička souboru

| Offset | Typ | Význam |
| --- | --- | --- |
| 0x00 | char[4] | `" raC"` (auto) nebo `"karT"` (trať), tj. obráceně `Car ` / `Trak` |
| 0x04 | u32 | bity 0–4 příznaky (0x1A), bity 5+ počet článků (356 A: 181) |
| 0x08 | u32 | počet položek „misc“ (356 A: 87) |
| 0x0C | u32 | offset tabulky článků v jednotkách 16 B (1 → 0x10) |

Za tabulkou článků následují rovnou položky misc.

### Položka (16 B)

| Offset | Typ | Význam |
| --- | --- | --- |
| 0x00 | u32 | když příznak & 1: horních 16 bitů ID (2 znaky), dolních 16 index; jinak celé ID (4 znaky) |
| 0x04 | u32 | bity 0–7 příznaky, bity 8+ délka dat v bajtech |
| 0x08 | i32 | počet prvků |
| 0x0C | u32 | offset **relativně k začátku položky**; když je délka 0, jde o seznam podpoložek a offset je v jednotkách 16 B |

### Článek (`Arti`) = jedna část auta

| ID | Index | Obsah |
| --- | --- | --- |
| `Name` | 0 | jméno části (`Body`, `HoodOut`, `WheelFront` ...) |
| `Base` | 0 | 0x0C počet úrovní; 0x44 info (GeomIndex, TypeIndex ... LevelIndex na +10); 0x64 seznam úrovní po 12 B (úroveň na +8) |
| `vt` | úroveň \| animace << 4 \| 0x8000 poškozené | vrcholy x, y, z, 1 (f32 ×4) |
| `nm` | dtto | normály (f32 ×4) |
| `uv` | úroveň | texturové souřadnice (f32 ×2) |
| `pr` | úroveň << 12 \| číslo dílu | díl (trojúhelníky jednoho materiálu) |
| `tr` | úroveň | matice 4×4 (f32), u aut jen posun (dveře, kapota, kola) |
| `$n` | úroveň | culling |
| `dz` | úroveň | zóny poškození |
| `ef` | | efekt (světlo, odlesk) – nemá geometrii |

Úrovně: 1–2 model do menu („fe“), 3–7 herní LOD („ig1–ig5“). TypeIndex ≠ 0 jsou varianty (styly, střecha cabrio, spoiler), LevelIndex >> 4 & 8 je řidič.

### Díl (`pr`)

| Offset | Typ | Význam |
| --- | --- | --- |
| 0x00 | i16 | fill mode (3) |
| 0x02 | i16 | 0x200 textura, \| 1 okno |
| 0x04 | i16 | index materiálu (`mt` v misc) |
| 0x08 | f32[4] | obalová koule |
| 0x28 | i32, i32 | počet info řádků, počet indexových řádků |
| 0x30 | 16 B × n | info: RMOffs, offset (B), délka (B), typ (0 vrcholy, 1 normály, 2 UV, 0x246E culling), úroveň, ref |
| … | 8 B × m | indexový řádek: index, typ (`vI` 0x4976 vrcholy, `uI` 0x4975 UV), offset do pole indexů |
| … | u8 × m × počet | indexy (1 bajt!) |

Index vrcholu = bajt + (offset info řádku typu 0) / 16, index UV = bajt + (offset typu 2) / 8. Každé 3 indexy tvoří trojúhelník. Levá a pravá polovina dílu bývají dva díly se stejnými UV, ale jiným materiálem.

### Misc

| ID | Obsah |
| --- | --- |
| `mt` | materiál: 0x10 jméno render metody (`CarExt`, `CarExtEnv`, `CarInt`, `CarWheel`, `CarWindow`), 0x28 index texturové stránky (od 0) |
| `sf` | vložený archiv SHPI ([fsh.md](fsh.md)), index = pořadí souboru v `.tpg` (od 0) |
| `RMth`, `BndP`, `Wndo` | render metody, ohraničující roviny, okna – nepoužito |

## 3. Textury aut

`<auto>.tpg` (INI) obsahuje `fileN=exterior.fsh ...` a sekce `[tpageN.details]` (šířka, výška, `sourcetpage`, `mirrortpage`). Stránky se číslují postupně, stránka se `sourcetpage` nemá vlastní soubor a je kopií zdrojové (u 356 A tpage2 = kopie tpage1 pro pravou stranu, kvůli vlastnímu poškození). Ostatní stránky berou soubory v pořadí.

Stránka je atlas 256×256 (nebo podle `.tpg`) složený z položek SHPI na jejich pozici (pole „pozice“ v hlavičce záznamu). Více položek na stejném místě jsou alternativy (styly, poškození), převod bere první. Soubory, které nejsou v `.crp` (`Suit`, `Head`, `Cabrio`), leží jako `.fsh` vedle něj.

Barva laku se v originále dobarvuje podle `.clr`, textury karoserie jsou šedé.

## 4. Převod do glTF (hotovo pro auta)

```
python3 tools/crp2gltf.py sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a/356a.gltf
```

- Výstup: `.gltf` + `.bin` + `<auto>_tpageN.png`, jeden uzel na část, primitiva podle texturové stránky.
- Jednotky jsou metry, osa Y nahoru, **předek auta je −Z** (glTF předpokládá +Z, v Godotu stačí otočit o 180°).
- Výchozí úroveň 1 (model do menu, cca 3 000 trojúhelníků), `--level 3` herní LOD, `--all` i varianty a řidič.
- Ověřeno: všech 44 aut se převede bez chyby; 356 A a 996 zkontrolované vizuálně v three.js (tvar, kola, světla, textury vlevo i vpravo sedí).
- Známé nedostatky: lak bez barvy (`.clr` se nepoužívá), u decalů může být zvolená jiná alternativní textura (tenké světlé pruhy na kapotě), poškozené vrcholy (0x8000) a animace se neexportují.

## 5. Tratě (k dopsání)

Bloky `CNK0`/`CNK1` (segmenty), `OBJE`/`OBJ0` (objekty), `MESH`, `CLIF`, `SHRU`, `Anim`, `SimD`, `SimT`, `Vis `, `Desc`. Nízká priorita (D-005).
