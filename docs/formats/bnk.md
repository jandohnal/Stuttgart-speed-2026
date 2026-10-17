---
type: file-format
format: viv, bnk, crd, spl
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: "GameData/Sounds/*.viv, *.bnk, *.spl"
count: "42 .viv, 4 .bnk, 86 .spl"
endianness: "BIGF big-endian, BNKl a CRDl little-endian, hodnoty v PT big-endian"
status: partial
tool: "tools/snd2wav.py (banky do WAV), tools/engine_sound.py (sady motorů pro hru)"
updated: 2026-10-17
---

# Zvukové banky (`.viv`, `.bnk`) a tabulky motoru

Zvuky originálu slouží jen jako lokální reference prototypu (D-011). Do hry pro vydání patří vlastní samply (D-007).

## Soubory

| Soubor | Obsah |
| --- | --- |
| `sd1a.viv` … `sdxc.viv` (20 sad) | zvuk motoru: banka `sdXY.bnk`, tabulky `.ect`, `.elt`, `.cct`, `.clt`, `default.cfg` (8 B), u `sd3a` i `.h` |
| `sd1a16.viv` … | úsporné varianty stejných sad: 16 kHz, 8 bit |
| `SND_coll.bnk`, `LilSND_coll.bnk` | nárazy, pneumatiky, povrchy, vítr (bez jmen) |
| `fesfx.bnk`, `lilfesfx.bnk` | zvuky menu (část stereo) |
| `track.viv` (593 bank), `zzzwzzz.viv` (65 bank) | okolí tratí (řeky …), déšť, průjezdy. Zatím nedávají zvuky, jiný tvar banky. |
| `<auto>.spl` (52 B) | ladění zvuku auta, 13 × i32, viz níže |

## BIGF (`.viv`)

| Offset | Typ | Obsah |
| --- | --- | --- |
| 0x00 | char[4] | `BIGF` |
| 0x08 | u32 BE | počet souborů |
| 0x10 | … | pro každý: u32 BE offset, u32 BE délka, jméno ukončené nulou |

## BNKl (EA banka, verze 4)

| Offset | Typ | Obsah |
| --- | --- | --- |
| 0x00 | char[4] | `BNKl` |
| 0x04 | u16 | verze (4) |
| 0x06 | u16 | počet pozic (např. 117) |
| 0x08 | u32 | délka hlavičky (= offset prvních dat) |
| 0x0C | u32 | celková délka dat |
| 0x10 | u32 × počet | offset hlavičky `PT` **relativně k té pozici tabulky**; 0 nebo 0xFFFFFFFF = prázdná pozice |

Více pozic může sdílet stejná data (stejný offset dat).

### Hlavička `PT`

`PT\0\0`, pak značky: bajt značky, bajt délky, hodnota big-endian. 0xFC–0xFE začínají podhlavičku (bez hodnoty), 0xFF konec.

| Značka | Význam |
| --- | --- |
| 0x80 | verze (1) |
| 0x82 | počet kanálů (chybí = 1) |
| 0x84 | vzorkovací frekvence (chybí = 22 050 Hz) |
| 0x85 | počet vzorků |
| 0x86, 0x87 | začátek a konec smyčky (ve vzorcích) |
| 0x88 | offset dat od začátku banky |
| 0xA0 | kodek: chybí = EA-XA ADPCM, 0x08 = PCM 16 bit LE, 0x09 = PCM 8 bit se znaménkem |
| 0x07 | **výchozí nota** (MIDI) nahraného vzorku; smyčky motoru 29–71 |
| 0x06, 0x0A, 0x0E, 0x10, 0x13 … | priorita, hlasitost a další (neurčeno) |

### EA-XA ADPCM (mono)

Rámec 15 B = 28 vzorků: bajt hlavičky (horní nibble index koeficientů 0–3, dolní nibble posun − 8), 14 B nibblů (horní napřed). Koeficienty (/256): (0, 0), (240, 0), (460, −208), (392, −220). `s = ((nibble << 28) >> posun + c1·h1 + c2·h2 + 128) >> 8`, ořez na 16 bit. Rámec s hlavičkou 0xEE: dva vzorky historie a 28 vzorků PCM 16 bit BE (61 B). Ověřeno: velikosti dat sedí na 15 B / 28 vzorků, poměr energie rozdílů k energii signálu 0,002–0,25 (šum ≈ 2).

Převod: `python3 tools/snd2wav.py sources/GameData/Sounds decomposed/GameData/Sounds` → `decomposed/GameData/Sounds/<archiv>/<banka>/<pozice>.wav` + `index.json` (frekvence, smyčka, značky). 46 souborů, 702 bank, 1 453 zvuků, vynecháno 20 stereo zvuků menu.

## Tabulky motoru (`CRDl`: `.ect`, `.elt`, `.cct`, `.clt`)

| Offset | Obsah |
| --- | --- |
| 0x00 | `CRDl` |
| 0x04 | u16 2, u16 25600, u16 20, u16 15, u32 500, u32 200, u16 100, u16 40, u32 300, u32 100 (význam neurčen; mřížka 20 × 15?) |
| 0x20 | 2 skupiny × 4 bajty: **pozice v bance + 1** (0 = nic) |
| 0x128 … | bloky s váhami prolínání (dvojice 64/0, 60/4 …) a křivkou 128 kroků 127 → 0 (neurčeno) |

Výklad z obsahu (sd1a): `*lt` mají v obou skupinách 4 smyčky v celém rozsahu not (41, 51, 57, 59) → **pod plynem** (load); `*ct` mají volnoběh (nota 29) a méně smyček → **bez plynu** (coast). `e*` = pohled zvenku, `c*` = z kokpitu. Dvě skupiny tabulky mají stejné noty (nejspíš dvě složky zvuku, např. výfuk a mechanika).

`tools/engine_sound.py decomposed/GameData/Sounds` zapíše pro každou sadu `engine.json`: smyčky „load“ a „coast“ (z `elt` a `ect`) a otáčky, při kterých jsou nahrané. Otáčky z noty: frekvence noty = frekvence zážehů, čtyřválec zapaluje dvakrát za otáčku, ot/min = f × 30. Pro `sd1a` vychází volnoběh 1 310 a smyčky 2 620–7 410 ot/min, což sedí na 356 (omezovač 5 800). U jiných sad vychází přes 14 000, převod noty na otáčky je tedy u každé sady jiný (neurčeno).

## `.spl` (ladění zvuku auta)

13 × i32, hodnoty 0–255. Neobsahuje číslo sady: přiřazení auta k sadě `sdXY` je zřejmě ve spustitelném souboru hry. Liší se podle motoru (356 A coupe 1.6: 76, 50, 72, 0, 63, 128, 91, 233, 80, 104, 25, 220, 30; turbo motory mají jiná poslední tři pole). Pro 356 A je zvolená sada `sd1a` (nejnižší noty, volnoběh 29), poslechem ve hře potvrzeno 17. 10. 2026.

## Zvuky auta v `SND_coll.bnk` (vybrané podle signálu, poslechem potvrzeno 17. 10. 2026)

| Použití | Pozice | Proč |
| --- | --- | --- |
| pískání pneumatik | 46 (43, 47, 48) | smyčky 1,5 s, ustálené, noty 63–66 |
| vítr | 42 | ustálená šumová smyčka 2,1 s |
| náraz lehký / těžký | 52, 56 / 49, 51, 55 | jednorázové, prudký nástup, doznění 25–40 dB |
| sklo | 119, 120 | jednorázové, vysoké frekvence |
| odpadnutí dílu | 61 | delší náraz |
| drhnutí | 99 | ustálený 1,4 s |

## Zbývá

Mřížka `CRDl` (prolínání podle otáček a zátěže), převod noty na otáčky u ostatních sad, přiřazení aut k sadám, banky okolí (`track.viv`), stereo zvuky, význam ostatních zvuků v `SND_coll.bnk` (povrchy, další nárazy).
