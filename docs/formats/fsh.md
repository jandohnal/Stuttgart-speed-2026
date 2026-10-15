---
type: file-format
format: fsh
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: ["GameData/CarModel/*.fsh", "GameData/Track/*.fsh", "GameData/Track/Sky/*.fsh", "GameData/DashHud/*.fsh", "GameData/Render/*.fsh", "FEData/**/*.fsh"]
count: 553
endianness: little
status: done
tool: "tools/fsh2png.py"
output: "decomposed/<cesta bez přípony>/NNN_<jméno>.png + index.json"
updated: 2026-10-15
---

# Formát `.fsh` – archiv textur (SHPI)

Všech 553 souborů se převede bez chyby na 10 425 obrázků.

## Obal

15 souborů (hlavně textury tratí, např. `Track/skidpad.fsh`) je celých zabalených v RefPack (`10 FB`, viz [crp.md](crp.md)). Po rozbalení mají stejný formát jako ostatní.

## Hlavička archivu

| Offset | Typ | Význam |
| --- | --- | --- |
| 0x00 | char[4] | `SHPI` |
| 0x04 | u32 | velikost souboru |
| 0x08 | u32 | počet položek *n* |
| 0x0C | char[4] | ID adresáře (`GIMX` ...) |
| 0x10 | {char[4] jméno, u32 offset}[n] | adresář položek |

## Položka

Položka je řetězec záznamů. Každý záznam má 16bajtovou hlavičku:

| Offset | Typ | Význam |
| --- | --- | --- |
| 0x00 | u8 | typ záznamu |
| 0x01 | u24 | vzdálenost k dalšímu záznamu téže položky (0 = poslední, data sahají k další položce nebo konci souboru) |
| 0x04 | u16 | šířka (u palety počet barev) |
| 0x06 | u16 | výška |
| 0x08 | i16[2] | střed (center x, y) |
| 0x0C | i16[2] | pozice na obrazovce (x, y) |

Řádky pixelů nemají zarovnání. První záznam je obrázek, za ním následují paleta a přílohy.

### Typy obrázků

| Typ | Pixel | Počet (obrázků) |
| --- | --- | --- |
| 0x7B | 8 bit, index do palety | 6 058 |
| 0x7D | 32 bit, B G R A | 1 947 |
| 0x7E | 16 bit, A1 R5 G5 B5 | 1 437 |
| 0x6D | 16 bit, A4 R4 G4 B4 | 671 |
| 0x78 | 16 bit, R5 G6 B5 | 89 |
| 0x7F | 24 bit, B G R | 1 |
| 0x80 + typ | stejný formát, pixely zabalené v RefPack (0xFB, 0xF8, 0xED) | 222 |

### Palety a přílohy

| Typ | Obsah | Kde |
| --- | --- | --- |
| 0x2A | paleta 32 bit B G R A, alfa 0–255 | auta, tratě (2 964×) |
| 0x29 | paleta 16 bit R5 G6 B5, bez alfy | menu, `FEData` (3 090×) |
| 0x2D | paleta 16 bit A1 R5 G5 B5 | 4× (`License*.fsh`) |
| 0x6F | text (metadata, zakončený nulou) | 496× |
| 0x7C | oblast / hotspot (`Laye` v kronice) | 218×, zatím se jen zapisuje do `index.json` jako typ |

## Výstup nástroje

`python3 tools/fsh2png.py sources decomposed` projde celý strom (asi 2 minuty). Pro každý soubor vznikne složka se jménem souboru:

- `NNN_<jméno>.png` – RGBA PNG (NNN = pořadí v archivu, jména se opakují),
- `index.json` – jméno, typ, komprese, rozměry, střed, pozice, paleta a text každé položky.

Mipmapy se nepřevádějí, bere se jen plné rozlišení.

## Poznámky

- Dva obrázky 0x7D mají alfu všude 0 (`Track/coastal.fsh` `walk`, `Track/Sky/default.fsh` `horz`). Jsou tak uložené ve zdroji, nejde o chybu převodu.
- Textury aut jsou ve složkách `CarModel/<auto>D` a `<auto>L` (pravděpodobně detail/low).
