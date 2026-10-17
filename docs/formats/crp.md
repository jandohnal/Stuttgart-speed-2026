---
type: file-format
format: crp
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: ["GameData/CarModel/*.crp", "GameData/Track/*.crp", "FEData/Models/*.crp"]
compression: "EA RefPack (QFS), magic 0x10FB"
status: "komprese, kontejner a geometrie aut hotové; tratě: skidpad"
tool: ["tools/archives.py", "tools/crp.py", "tools/crp2gltf.py", "tools/track2gltf.py"]
updated: 2026-10-15
---

# Formát `.crp` – modely aut a tratí

## 1. Komprese (hotovo)

Soubor začíná `10 FB` + 3 B velikost rozbalených dat (big-endian), následuje proud RefPack.
`tools/archives.py refpack` rozbalí auto (`356a.crp`: 3 764 224 B) i trať (`alps.crp`: 6 168 576 B) s přesnou shodou deklarované velikosti.

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
| `vt` | úroveň \| animace << 4 \| 0x8000 poškozené | vrcholy x, y, z, 1 (f32 ×4); s 0x8000 **posuny** vrcholů pro plně poškozené auto (x, y, z, 0), viz [Poškození](#poškození) |
| `nm` | dtto | normály (f32 ×4) |
| `uv` | úroveň | texturové souřadnice (f32 ×2) |
| `pr` | úroveň << 12 \| číslo dílu | díl (trojúhelníky jednoho materiálu) |
| `tr` | úroveň | matice 4×4 (f32, Direct3D, řádky = osy, posun ve floatech 12–14); u aut jen posun (dveře, kapota, kola), u objektů tratí úplné umístění (rotace, měřítko, poloha) |
| `$n` | úroveň | culling |
| `dz` | úroveň | zóny poškození: které vrcholy patří do které zóny, viz [Poškození](#poškození) |
| `ef` | | efekt (světlo, odlesk) – nemá geometrii |

Úrovně: 1–2 model do menu („fe“), 3–7 herní LOD („ig1–ig5“). TypeIndex ≠ 0 jsou varianty (styly, střecha cabrio, spoiler), LevelIndex >> 4 & 8 je řidič.

### Díl (`pr`)

| Offset | Typ | Význam |
| --- | --- | --- |
| 0x00 | u16 | typ primitivy: 3 = seznam trojúhelníků, 1 = pruh (triangle strip), 4 = seznam čtyřúhelníků |
| 0x02 | i16 | 0x200 textura, \| 1 okno |
| 0x04 | i16 | index materiálu (`mt` v misc) |
| 0x08 | f32[4] | obalová koule |
| 0x28 | i32, i32 | počet info řádků, počet indexových řádků |
| 0x30 | 16 B × n | info: RMOffs, offset (B), délka (B), typ (0 vrcholy, 1 normály, 2 UV, 0x246E culling), úroveň, ref |
| … | 8 B × m | indexový řádek: index, typ (`vI` 0x4976 vrcholy, `uI` 0x4975 UV), offset do pole indexů |
| … | u8 × m × počet | indexy (1 bajt!) |

Index vrcholu = bajt + (offset info řádku typu 0) / 16, index UV = bajt + (offset typu 2) / 8. U typu 3 tvoří každé 3 indexy trojúhelník. U pruhu (typ 1) tvoří trojúhelník každá trojice sousedních indexů, liché trojúhelníky mají prohozené první dva vrcholy (stejné pořadí oběhu) a trojúhelníky s opakovaným vrcholem se zahazují. Auta mají jen typ 3. Tratě mají pruhy v terénu: farmland 72 dílů, skidpad 13, často s počtem indexů nedělitelným třemi. Dokud se četly jako seznam, posunuly všechny další trojúhelníky téhož materiálu a v terénu byly díry a rubové plochy (ověřeno snímkem u řezu 1284). Pruh potvrzuje orientace: 91 % jeho trojúhelníků míří nahoru, při čtení jako seznam 50 %.

Typ 4 je seznam čtyřúhelníků: každé 4 po sobě jdoucí rohy jsou jeden čtyřúhelník (v rovině: odchylka 0–0,03 proti 0,22 u posunutých čtveřic), převádí se na trojúhelníky (a, b, c) a (a, c, d). Mají ho hlavně objekty knihovny (desky dopravních značek, krabice, postava, vrtulník v alps), farmland 28 dílů.

**Díly bez indexových řádků** (typ 3 i 4, délka položky jen 0x30 + 4 info řádky): vrcholy a UV jdou za sebou od offsetů v info řádcích 0 a 2 (např. `Sweeper`, typ 3, 252 + 240 vrcholů). Auto 356 má takové 2 trojúhelníky. Levá a pravá polovina dílu bývají dva díly se stejnými UV, ale jiným materiálem.

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

### Poškození

Každý díl auta má ke každé úrovni dvě položky:

- `vt` s indexem `0x8000 | úroveň`: posun každého vrcholu pro plně poškozené auto (stejný počet jako `vt` úrovně, w = 0, u 356 A 0–0,29 m; některé vrcholy 0). Nejsou to polohy.
- `dz` s indexem úrovně: přiřazení vrcholů do zón.

| Offset | Typ | Obsah |
| --- | --- | --- |
| 0x00 | u32 | počet zón v dílu (n) |
| 0x04 | n × (i32, i32, i32) | zóna, počet vrcholů, začátek v seznamu níže |
| 0x04 + 12 n | u32 × … | indexy vrcholů seskupené podle zón |

Délka = 4 + 12 n + 4 × počet vrcholů dílu (ověřeno na všech dílech 356 A). Poškozená poloha = vrchol + d(zóna) × posun, d ∈ ⟨0, 1⟩.

Zóny na 356 A (těžiště v glTF, předek −Z, vpravo +X); posuny míří dovnitř auta (71–100 % vrcholů zóny):

| Zóna | Místo | Těžiště (m) | Max. posun |
| --- | --- | --- | --- |
| 0 | předek vlevo | (−0,53; 0,49; −1,59) | 0,28 |
| 1 | předek uprostřed (kapota) | (−0,05; 0,61; −0,61) | 0,14 |
| 2 | předek vpravo | (0,54; 0,49; −1,59) | 0,29 |
| 3 | pravý bok | (0,62; 0,64; −0,18) | 0,16 |
| 4 | záď vpravo | (0,49; 0,50; 1,53) | 0,14 |
| 5 | záď uprostřed | (0,00; 0,61; 1,20) | 0,18 |
| 6 | záď vlevo | (−0,49; 0,50; 1,53) | 0,24 |
| 7 | levý bok | (−0,53; 0,68; −0,23) | 0,16 |
| 8 | střecha | (−0,16; 0,98; −0,12) | 0,07 |
| 9 | spodek | (0,00; 0,20; 0,08) | 0,18 |

Textury poškození jsou v FSH jako alternativní obrázky na stejném místě atlasu (zatím se nepoužívají).

## 4. Převod do glTF (hotovo pro auta)

```
python3 tools/crp2gltf.py sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a/356a.gltf
```

- Výstup: `.gltf` + `.bin` + `<auto>_tpageN.png`, jeden uzel na část, primitiva podle texturové stránky. Poškození: každý díl má morph target `dz<zóna>` pro každou svou zónu (posuny jen u vrcholů zóny, `mesh.extras.targetNames`, v Godotu blend shapes). `<auto>_damage.json`: zóny s těžištěm, počtem vrcholů a max. posunem a odpojitelné sestavy. 356 A: 51 z 64 uzlů má targety.
- Odpojitelné sestavy (`detachable` v `_damage.json`): kapota (`HoodOut`, `HoodIn`, `DecalHood`), víko motoru (`TrunkOut`, `TrunkIn`, `DecalTrunk`), dveře se zrcátkem po stranách (díly se stejným pivotem `tr`), poznávací značka a díly, které originál modeluje jako jeden mesh pro obě strany (`Light1` světla, `Light3` blinkry, `Light2` zadní světla, `SkirtF`, `SkirtR`, `Exhaust`). Ty se při exportu dělí podle strany trojúhelníku na uzly `_L` / `_R`. Sestava patří do zóny, ve které má nejvíc vrcholů; hmotnost je odhad. Levé a pravé kopie dílů se stejným jménem (dveře, kola) dostanou příponu `_L` / `_R`, aby byla jména uzlů unikátní.
- Jednotky jsou metry, osa Y nahoru, **předek auta je −Z** (stejně jako „dopředu“ v Godotu).
- **Souřadnice originálu jsou levotočivé (Direct3D).** Převod do glTF zrcadlí osu X (`crp.to_gltf`), tím se zároveň otočí pořadí vrcholů trojúhelníků na správnou stranu. Ověřeno: 96–99 % trojúhelníků aut souhlasí s uloženými normálami (před opravou 4 %), volant 356 A je vlevo (−0,29 m), všechny normály silnice skidpadu míří nahoru, vektor „doprava“ v `SimD` = dopředu × nahoru. Bez opravy byly modely zrcadlené (pravostranné řízení) a kolize trati v Godotu nefungovala (paprsek trefil rub trojúhelníku).
- Výchozí úroveň 1 (model do menu, cca 3 000 trojúhelníků), `--level 3` herní LOD, `--all` i varianty a řidič.
- Ověřeno: všech 44 aut se převede bez chyby; 356 A a 996 zkontrolované vizuálně v three.js (tvar, kola, světla, textury vlevo i vpravo sedí).
- Známé nedostatky: lak bez barvy (`.clr` se nepoužívá), u decalů může být zvolená jiná alternativní textura (tenké světlé pruhy na kapotě), textury poškození a animace se neexportují.

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

Články s `tr` jsou **objekty** s vlastní maticí; vrcholy mají v lokálních souřadnicích. Odpovídají jim cesty v misc `Desc` (`I:\NFS5Tracks\ModelLibrary\Objects\Smackable\…`). Jsou dvojího druhu:

- **Rozmístěné**: `tr` nese skutečnou polohu na trati (vodorovně dál než 50 m od počátku). Farmland 72: 66 dopravních značek (`OBJ0048R (1 curveleft_Rigid1_SGN)` …, značka SIGN), 4 ležící sloupy (`COLUMN_HORIZONTAL`, CLMH) a 2 animované „sweepery“ (SWEE, `Anim`/`Anqt`).
- **Předlohy**: v počátku, jen s malým posunem pivotu (úlomky bedny ±0,7 m, šipky 13 m nahoře). Kužel, auta provozu, nákladní auta, lidé, bedny, šipky, cílová čára, hydrant … Rozmisťují je úlohy (`GEOM_ELEMENT` v `<trať>_st*.scn`, [scn.md](scn.md)) a nejspíš provoz. Farmland 70, skidpad 70 (rozmístěné nemá žádné).

### `Base` článku (trať, 112 B; silnice 136 B)

| Offset | Typ | Význam | Příklad |
| --- | --- | --- | --- |
| 0x00 | u16 | příznaky: 0x0601 objekt, 0x0610 animovaný objekt, 0x0611 terén, 0x8601/0x8610 předloha | |
| 0x0C | i32 | počet úrovní detailu | silnice 3, ostatní 1 |
| 0x14 | f32[3] | obalový kvádr min | |
| 0x20 | f32[3] | obalový kvádr max | |
| 0x2C | f32[3] | střed | |
| 0x38 | f32 | 1.0 | |
| 0x3C, 0x40 | f32 | poloměr obalové koule (2×) | značka 1,94 m |
| 0x44 | char[4] | **značka objektu** = klíč do `animdefs.txt` (kolize, hmotnost, zvuk) a do `GEOM_ELEMENT` v `.scn` | `SIGN`, `CONE`, `SWEE`, `FNSH`, `CLMH`, `BUS` |

Terén a silnice mají značku prázdnou.

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

**Úseky:** `SimD` není vždy jedna souvislá silnice. Na farmlandu (Normandie) je nejdřív hlavní trasa (řezy 0–1671, 10,0 km), za ní 9 krátkých úseků (48–810 m), nejspíš alternativní cesty a zkratky. Hranici poznáme podle skoku mezi sousedními řezy (> 30 m, běžně ~6 m). Jak se úseky napojují, nejspíš popisuje `.jnc` (zatím nerozluštěno).

Ověřeno na skidpadu: střed řezů leží na středu asfaltu (geometrie `RD` má poloměr 215–232 m, tedy 17 m široký asfalt se středem 223 m), délka 234 řezů = 1 398 m = 2π · 223 m. Čtyři šířky jsou na skidpadu stejné (±10 m = sjízdná plocha včetně krajnic?), na farmlandu většinou 6 m, místy nesymetrické (např. 6; 6,29; 6; 3,15). Význam zatím neurčen.

### Start a cíl – `<trať>_fstart.scn`, `<trať>_bstart.scn`

Textové soubory s bloky `TRIGGER_ELEMENT` (a `GEOM_ELEMENT`, např. startovní brána). `fstart` platí pro jízdu dopředu, `bstart` pro jízdu pozpátku (start a cíl prohozené). Blok `TRIGGER_ELEMENT 5` má řádky:

| Řádek | Obsah |
| --- | --- |
| 1 | pozice (x, y, z) |
| 2 | báze, 9 čísel: dopředu, nahoru, doprava |
| 3 | parametry, první číslo je typ: 2 = start, 1 = cíl; čtvrté číslo je polovina šířky čáry? (farmland 19,2 / 23,9) |
| 4 | dva krajní body čáry (6 čísel) |
| 5 | ? (nuly) |

Farmland dopředu: start u řezu 56, cíl u řezu 1601, závod tedy vede po hlavní trase ve směru řezů (~9,3 km). Skidpad soubor `fstart` nemá.

### Převod do glTF

```
python3 tools/track2gltf.py sources/GameData/Track/skidpad.crp decomposed/GameData/Track/skidpad/skidpad.gltf
```

- Výstup: `.gltf` + `.bin` + `<trať>_road.json` (všechny řezy `SimD`, `segments` = úseky `{first, last, length_m, closed}`, `start`/`finish` z `_fstart.scn` s nejbližším řezem); textury jsou PNG z `fsh2png` ve stejné složce (chybí-li `index.json`, převedou se).
- Uzly ve skupinách `road`, `terrain`, `vegetation`, `objects`, `props` (rozmístěné objekty s maticí `tr`, jméno uzlu začíná pořadím `000 …`), `simd` (červený poloprůhledný pás podle `SimD` pro kontrolu), s `--library` i `library` (předlohy v řadě na z = −60 m).
- `<trať>_objects.json`: pro každý uzel `props` jméno, značka, typ kolize (`smackable`, `box`, `cylinder`, `none`, `static`), hmotnost a průjezdnost z `animdefs.txt`, poloha.
- Matice `tr` se zrcadlí stejně jako vrcholy: S·M·S se S = diag(−1, 1, 1, 1), tedy změna znaménka u prvků 1, 2, 3, 4, 8, 12. Těch 16 floatů čtených po sloupcích je přímo matice glTF.
- `--level` 0–3 (skidpad: 7 314 / 2 636 trojúhelníků pro úroveň 0 / 2).
- Metry, osa Y nahoru, osa X zrcadlená z levotočivých dat (viz výše, týká se i vektorů `SimD`). `Opaque` → neprůhledné, ostatní render metody → alpha MASK.
- Zkontrolováno renderem v Blenderu (pohled shora a zblízka): trať, pneumatikové zdi, pole, stromy, budovy i textury sedí.
- Farmland (Normandie, „French Farmland“): silnice 239, terén 367, vegetace 216, objekty 175, rozmístěné objekty 72, předlohy 70; 66 538 trojúhelníků, 244/245 textur, 1 995 řezů v 10 úsecích. Ve hře (Godot) ověřeno jízdou, snímky a nárazem do dopravní značky.
- Trojúhelníky otočené dolů (18 % vodorovných v terénu) jsou koruny stromů nad silnicí a střechy (materiály `cbb`, `shrb`, 3 m a víc nad silnicí), jsou tedy správně. Materiály jsou oboustranné.
- Zbývá: ostatních 13 tratí, význam `df`, šířek a příznaků `SimD`, animace (`Anim`, `Anqt`, snímky `vt` s indexem animace), předlohy z úloh (`.scn`), `Vis`, `CmAn`.
