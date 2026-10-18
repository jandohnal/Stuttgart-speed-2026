---
type: file-format
format: flare.dat
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: "GameData/Render/flare.dat"
count: "1 soubor, 39 záznamů"
encoding: "binární, little-endian"
status: partial
tool: "tools/flare.py (→ decomposed/GameData/Render/flares.json)"
updated: 2026-10-19
---

# Záře světel (`GameData/Render/flare.dat`)

Tabulka vzhledu světelných září (flare): lampy, tunelová světla, výstražná světla, slunce a odlesky čočky. Tratě na ně odkazují ID z položek `ef` svých článků ([crp.md](crp.md#efekty-ef-článku)). Převod: `python3 tools/flare.py sources/GameData/Render/flare.dat decomposed/GameData/Render/flares.json`.

## Záznam (140 B)

Soubor je jen řada záznamů bez hlavičky (5 460 B = 39 × 140).

| Offset | Typ | Význam |
| --- | --- | --- |
| 0x00 | char[4] | ID **pozpátku** (`anrw` = `wrna`) |
| 0x04 | char[4] | textura vrstvy 1 pozpátku (`RALG` = `GLAR`), `null` = vrstva chybí |
| 0x08 | char[4] | textura vrstvy 2 |
| 0x1C | u32 | barva vrstvy 1, ARGB (`wrna` 0xFFFF4400 = oranžová) |
| 0x20 | u32 | barva vrstvy 2, ARGB |
| 0x34 | f32 | velikost vrstvy 1 |
| 0x38 | f32 | velikost vrstvy 2 |
| 0x4C | u32 | 4 u všech (?) |
| 0x50 | u32 | blikání: fáze (tiky) |
| 0x54 | u32 | blikání: svítí (tiky) |
| 0x58 | u32 | blikání: nesvítí (tiky); 0 a 0 = svítí stále |
| ostatní | | nuly |

Textury jsou v `GameData/Render/common.fsh` (`GLAR`, `SPIK`, `BLUR`, `SUNA`, `FLR0`; `lens` tam není). Jsou bílé, tvar dává alfa (kruhová záře). Vrstva 1 je jádro, vrstva 2 nejčastěji větší svatozář.

Blikání (hypotéza, sedí na všech blikajících): světlo svítí, když `(tik − fáze) mod (svítí + nesvítí) < svítí`. `wrna` a `wrnb` mají stejné časy, liší se jen fází 0 / 30, tedy blikají střídavě. Šipky `arwa`–`arwe` mají fáze 50, 40, 29, 21, 10, takže se rozsvěcují postupně (běžící šipka). Rychlost tiků není jistá; hra bere 60 tiků/s (výstražné světlo bliká jednou za sekundu). Jednotka velikosti také není jistá; hra bere 0,1 m (záře kozy 0,6 / 0,9 m).

## ID

Hodnoty všech 39 záznamů (barvy, velikosti, blikání) se do repozitáře neukládají. Z vlastní kopie hry je vypíše `tools/flare.py` do `decomposed/GameData/Render/flares.json`.

Význam podle nositelů: `wrna`/`wrnb` výstražná oranžová světla (kozy `SAWH`, kužely `PLON`, blikající cedule), `arwa`–`arwe` běžící šipky (`FLASHERS##`, `EndWall`, `CRASHLIGHTS`), `strg`/`stry`/`strb`/`strr`/`strp` pouliční lampy (zelenkavá výbojka, žlutá sodíková, modrá, červená, fialová), `lamp`, `lmpy`, `lpol` lampy, `tunb`/`tuno`/`tuny` tunelová světla, `bldy`, `cant` světla budov, `nred`/`fred` červená světla na jeřábech a kontejnerech (`fred` bliká), `helf`/`helr`/`helw` vrtulník a tunely, `swht` bílá, `trfg` semafor (zelená, bliká), `sun*` slunce a odlesky čočky (`flarepos.dat`: 14 floatů, nejspíš poloha odlesků na spojnici se sluncem), `aoll`, `docy`, `spot` zatím bez nositele.

## Související

- `<trať>.map` (text): hlavička `[header]` s `tint`, `ambient`, `interior`, `lightdecal` (4 čísla, první vždy 1,0). Monaco má `ambient` 0,30 a `tint` 1,80 (noc), farmland 0,70 a 0,73. Sekce `[sectionN]` se `startslice` / `endslice` a texturami `textureN.open` / `.covered` (4CC jako číslo, např. `TMS1`): nejspíš světelné obtisky na silnici zvlášť pod širým nebem a pod střechou. Zatím nerozluštěno.
- `GameData/Render/particle.ini`, `particle.dat`: zdroje částic (`ef` druhu 3), zatím nerozluštěno.
