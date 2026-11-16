---
type: file-format
format: sky
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: ["GameData/Track/Sky/*.txt", "GameData/Track/Sky/*.bin", "GameData/Track/Sky/*.fsh"]
count: {txt: 17, bin: 19, fsh: 17}
status: partial
tool: ["tools/sky.py", "tools/fsh2png.py"]
output: ["decomposed/GameData/Track/<trať>/<trať>_sky.json", "decomposed/GameData/Track/Sky/<Trať>/*.png"]
updated: 2026-11-16
---

# Obloha originálu: `Sky/<Trať>.txt`, `.bin`, `.fsh`

Originál kreslí oblohu před scénou bez hloubky. Skládá se z **kopule** s vrstvami barevných map a mraků a z **prstence horizontu** s panoramatem krajiny. Rozluštěno z `Porsche.exe` (Ghidra, 15.–16. 11. 2026):

- `FUN_0045d800`: konstruktor oblohy,
- `FUN_0045fb80`: čtení `.txt`,
- `FUN_00459660`: čtení `.bin` (`CSkyCnfig`),
- `FUN_00459700`: převod starších verzí `.bin`,
- `FUN_0045b5a0`: `MultiSky`,
- `FUN_00460f40`: tvar kopule,
- `FUN_0045ec40` a `FUN_0045f1b0`: UV vrstev,
- `FUN_00459b50` a `FUN_00459d30`: `SkyHorizon`.

Soubor se hledá podle jména trati bez ohledu na velikost písmen (`farmland` → `Farmland.txt`, `forest.txt` vedle `Forest.bin`), jinak se vezme `default.*`.

## `.fsh` – textury

| Jméno | Rozměr | Význam |
| --- | --- | --- |
| `st1a`, `st1b` | 16×16, neprůhledné | barevná mapa oblohy, oblast počasí A a B (Monaco tmavé, noc) |
| `sc1a`, `sc2a`, `sc1b` … | 16×16 s alfou | další barevné mapy vrstev |
| `cc1a`, `cm1a`, `cc2a` … | 32×32, bílé s alfou | mraky (textura vrstvy). `flat` v `.txt` znamená bílou plochu |
| `horz` (`hor0`–`hor3`) | 256×256 s alfou | panorama krajiny v mřížce dlaždic, nad kopci průhledné. `hor<n>` přednostně pro úroveň výkonu `n` |
| `hzcl` | 16×2 | barvy horizontu: řádek 0 horní okraj, řádek 1 dolní, sloupec na segment prstence |
| `suna`, `fct1`, `noyz` | | slunce (jen Farmland), další mapy |

## `.txt` – vrstvy

Bloky `BEGIN` … `END` s hodnotami po řádcích (komentáře `#`). Každý blok obsahuje schopnost počítače (`HIGH`, `MEDIUM`, `LOW`), typ úrovně a „blokuje slunce“ (`YES`/`NO`). Typy:

- `basic`: jedna vrstva,
- `multinormal`, `multiadditive`, `multiattenuate`, `multimodulate`: tři vrstvy, míchání podle alfy, sčítáním, zeslabením nebo násobením,
- `freecloud`,
- `*water`: odraz pod vodou (kopule zrcadlená dolů, blok `.bin` 0xB3C),
- `additive`: už nepodporované.

Úroveň se vybírá podle schopnosti počítače (globální index, stejný jako u `hor<n>`).

Hodnoty `multi*` za každou oblast A a B (18 hodnot):

1. 3 barevné mapy,
2. 3 měřítka X,
3. 3 měřítka Y,
4. `move ratio`,
5. 3 rychlosti větru,
6. 3 směry větru (°),
7. rychlost zvlnění,
8. míra zvlnění.

Za oblastmi následují 3 textury mraků. Počet vrstev je počet textur mraků, které nejsou `none`. Vrstva *k* = mapa *k* × mrak *k*.

Hodnoty `basic` za každou oblast (10 hodnot): mapa, druhá mapa (vždy `none`), textura, měřítko X, měřítko Y, `move ratio`, rychlost větru, směr větru, rychlost zvlnění, míra zvlnění.

## `.bin` – `SkyCnfig`

Má 0x71DC B a verzi 9. `Monaco.bin` a `default.bin` mají verzi 7 a 3 544 B. Hra je při načtení doplní výchozími hodnotami. `*_lightning.bin` mají jiný formát (blesky, zatím nerozluštěné).

| Offset | Typ | Význam |
| --- | --- | --- |
| 0x00 | u32 | verze |
| 0x04 | f32 | natočení prstence (otáčky) |
| 0x08 | u32 | posun sloupce `hzcl` pro segment 0 |
| 0x0C, 0x10 | u32 | dlaždice `horz`: sloupce, řádky (4×2, Monaco 4×1) |
| 0x14, 0x18 | f32 | spodní okraj prstence a jeho výška (Farmland −60,2 a 115,7) |
| 0x1C | 16 × (u8 dlaždice, u8 zrcadlit) | dlaždice segmentů prstence |
| 0x3C | f32 × 4 | kopule: natočení (otáčky), šířka, zakřivení, výška (Farmland 0,65; 1 092; 0,0002; 115,5) |
| 0xB3C | f32 × 4 | kopule pro `*water` (výchozí 0; 1 000; −0,0002; −75) |
| 0xCE4 | f32 | měřítko kopule |
| 0xCEC | 4 × 15 f32 | barvy 0–254 pro oblasti A/B (význam zatím neurčen) |
| 0xDDC | 400 × (u32 řez, f32) | **prolnutí oblasti A → B podle řezu `SimD`** (`FUN_0045a2c0`), −1 = konec |
| 0x1A5C | 400 × 12 × 4 B | tabulka podle řezu, 11 hodnot (zatím neurčeno) |
| 0x655C | 400 × (u32 řez, u8) | tabulka podle řezu (zatím neurčeno) |

**Prstenec** má 16 rovných segmentů o poloměru 400 kolem kamery, od okraje `base` do `base + height` (relativně k výšce kamery). Roh segmentu *k* leží na (sin θ, cos θ) · 400, kde θ = natočení + *k*/16 otáčky. Segment ukazuje svou dlaždici `horz` (u přes dlaždici, při zrcadlení obráceně; v od 0,01 nahoře do 0,98 dole). Vrcholy tónují barvy `hzcl`.

**Kopule** je čtvercová mřížka 16×16 vrcholů o straně `šířka`, natočená o natočení. Výška je `y = výška − zakřivení · (x² + z²)`. Okraj kopule (Farmland 55,9) se kryje s horním okrajem prstence (55,5).

**UV vrstev**: index mřížky × 1/měřítko (měřítko a vítr se prolínají mezi A a B), plus:

- vítr `rychlost · 0,00025 · (sin, cos)(−směr)` za tik,
- posun s pohybem kamery (1/`move ratio`),
- náhodné zvlnění vrcholů (rychlost, míra).

## Převod a hra

`tools/sky.py` zapíše ke každé trati `<trať>_sky.json`: složku textur, `.txt` po úrovních a oblastech, prstenec, kopuli a prolnutí podle řezu. Tento soubor a textury jdou do balíčku trati pro web (`tools/pack_web.py`).

Hra (`game/shaders/original_sky.gdshader`, `game/scripts/original_sky.gd`, D-045) kreslí kopuli i prstenec ve sky shaderu po paprscích z kamery. Úroveň je `HIGH`, s nízkou kvalitou `MEDIUM`. `OriginalSky` sleduje řez kamery a nastavuje prolnutí A → B.

Odchylky a hypotézy:

- Barevná mapa pokryje kopuli jednou při měřítku 1. Při 15 opakováních (jedno na buňku mřížky) byla obloha zrnitá. Pravděpodobně jde o pozdější krok výpočtu UV, který zatím není ověřený.
- Zvlnění je napodobené sinusem.
- Vrstvy se skládají přes alfu (`multinormal`).
- Barvy 0xCEC a tabulky podle řezu kromě prolnutí se nepoužívají.
- Směr slunce v datech oblohy není. Slunce zůstává ze scény, `suna` se kreslí ve směru světla.
