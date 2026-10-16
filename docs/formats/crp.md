---
type: file-format
format: crp
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: ["GameData/CarModel/*.crp", "GameData/Track/*.crp", "FEData/Models/*.crp"]
compression: "EA RefPack (QFS), magic 0x10FB"
status: "komprese, kontejner a geometrie aut hotové; tratě: skidpad"
tool: ["tools/refpack.py", "tools/crp.py", "tools/crp2gltf.py", "tools/track2gltf.py"]
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
- Jednotky jsou metry, osa Y nahoru, **předek auta je −Z** (stejně jako „dopředu“ v Godotu).
- **Souřadnice originálu jsou levotočivé (Direct3D).** Převod do glTF zrcadlí osu X (`crp.to_gltf`), tím se zároveň otočí pořadí vrcholů trojúhelníků na správnou stranu. Ověřeno: 96–99 % trojúhelníků aut souhlasí s uloženými normálami (před opravou 4 %), volant 356 A je vlevo (−0,29 m), všechny normály silnice skidpadu míří nahoru, vektor „doprava“ v `SimD` = dopředu × nahoru. Bez opravy byly modely zrcadlené (pravostranné řízení) a kolize trati v Godotu nefungovala (paprsek trefil rub trojúhelníku).
- Výchozí úroveň 1 (model do menu, cca 3 000 trojúhelníků), `--level 3` herní LOD, `--all` i varianty a řidič.
- Ověřeno: všech 44 aut se převede bez chyby; 356 A a 996 zkontrolované vizuálně v three.js (tvar, kola, světla, textury vlevo i vpravo sedí).
- Známé nedostatky: lak bez barvy (`.clr` se nepoužívá), u decalů může být zvolená jiná alternativní textura (tenké světlé pruhy na kapotě), poškozené vrcholy (0x8000) a animace se neexportují.

## 5. Tratě (ověřeno zatím jen na `skidpad`)

Stejný kontejner (`"karT"`), stejné články `Arti` s `Name`, `Base`, `vt`, `uv`, `pr`, `tr`. Parser je společný v `tools/crp.py`.

### Rozdíly proti autům

| Co | Auta | Tratě |
| --- | --- | --- |
| Úrovně detailu | 1–2 menu, 3–7 hra | 0–3, **0 = nejdetailnější** |
| `vt` index | úroveň \| animace << 4 \| 0x8000 | úroveň \| snímek animace << 4 (animované objekty mají až 46 snímků) |
| Normály `nm` | ano | **ne** – dopočítávají se |
| Materiál `mt` +0x28 | index texturové stránky | **4znakové jméno textury** v `<trať>.fsh` (skidpad 107/107, alps 203/204) |
| Render metody | `CarExt`, `CarInt` … | `Opaque`, `Normal`, `FakeSort`, `NormMatState`, `FullAmbMatState` |
| Textury | atlasy | jednotlivé obrázky, opakují se (tiling) |
| `df` | – | 4 B na index dílu, význam neznámý (příznaky / povrch?) |

### Články

Podle jména: `RD…` silnice, `CNK…` krajina po úsecích (v závorce obsah, např. `GRDRAILNPOST_LOD0`, `TREE11_LOD0`), `MESH`, `FARMMID`, `HILL` terén, `tree`, `OAK`, `SHRUB(S)`, `TREEWALL` vegetace, ostatní objekty.

Články s `tr` jsou **knihovna objektů** (kužele, auta, lidé, šipky …): leží v počátku s nulovým posunem a ve hře se rozmisťují jinde (pozice zatím neznámé). Odpovídají jim cesty v misc `Desc` (`I:\NFS5Tracks\ModelLibrary\Objects\Smackable\…`). Skidpad: 70 článků, 41 z nich má geometrii.

### Misc

| ID | Obsah |
| --- | --- |
| `SimD` | řezy silnice po ~6 m, 80 B na řez (tabulka níže) |
| `SimT` | skidpad 1 × u32 (234 = počet řezů?), alps 4 položky |
| `Vis ` | boxy viditelnosti (alps 275 × 24 B) |
| `CmAn` | kamery (`camera00` …), 6340 B |
| `Desc` | cesty ke zdrojovým modelům knihovny objektů |
| `sn` | jméno souboru textur (`skidpad.fsh`) |

### `SimD` – řez silnice (80 B)

| Offset | Typ | Význam | Skidpad |
| --- | --- | --- | --- |
| 0x00 | i32 | ? | 0 |
| 0x04 | f32[3] | pozice středu silnice (m) | kružnice r = 223,4 m |
| 0x10 | f32[3] | vektor nahoru | (0, 1, 0) |
| 0x1C | f32[3] | vektor dopředu (směr jízdy) | |
| 0x28 | f32[3] | vektor doprava | |
| 0x34 | i32[3] | příznaky | 98304, 1, 1 |
| 0x40 | f32[4] | šířky (m) | 10, 10, 10, 10 |

Ověřeno na skidpadu: střed řezů leží na středu asfaltu (geometrie `RD` má poloměr 215–232 m, tedy 17 m široký asfalt se středem 223 m), délka 234 řezů = 1 398 m = 2π · 223 m. Čtyři šířky jsou na skidpadu stejné (±10 m = sjízdná plocha včetně krajnic?); jejich rozlišení vyžaduje trať s nesymetrickou silnicí.

### Převod do glTF

```
python3 tools/track2gltf.py sources/GameData/Track/skidpad.crp decomposed/GameData/Track/skidpad/skidpad.gltf
```

- Výstup: `.gltf` + `.bin` + `<trať>_road.json` (všechny řezy `SimD`); textury jsou PNG z `fsh2png` ve stejné složce (chybí-li `index.json`, převedou se).
- Uzly ve skupinách `road`, `terrain`, `vegetation`, `objects`, `simd` (červený poloprůhledný pás podle `SimD` pro kontrolu), s `--library` i `library` (objekty v řadě na z = −60 m).
- `--level` 0–3 (skidpad: 7 314 / 2 636 trojúhelníků pro úroveň 0 / 2).
- Metry, osa Y nahoru, osa X zrcadlená z levotočivých dat (viz výše, týká se i vektorů `SimD`). `Opaque` → neprůhledné, ostatní render metody → alpha MASK.
- Zkontrolováno renderem v Blenderu (pohled shora a zblízka): trať, pneumatikové zdi, pole, stromy, budovy i textury sedí.
- Zbývá: ostatních 14 tratí, význam `df`, šířek a příznaků `SimD`, rozmístění knihovny objektů, animace, `Vis`, `CmAn`.
