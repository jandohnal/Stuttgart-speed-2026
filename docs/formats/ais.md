---
type: file-format
format: ais
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: "GameData/Simulation/AICarData/*.ais; GameData/Simulation/AI/TRAFCFG.DAT + .DES"
count: "22 .ais, 1 TRAFCFG"
status: partial_decoded
tool: "tools/ais2json.py"
output: "decomposed/GameData/Simulation/AICarData/ais.json, decomposed/GameData/Simulation/AI/trafcfg.json"
updated: 2026-10-29
---

# Profily aut soupeřů (`.ais`) a řízení AI (`TRAFCFG`)

## `.ais`

Jeden soubor na rodinu aut (`356`, `356A`, `901`, `935`, `Gt1` … + `default.ais` = kopie 944 s jinou tabulkou B), vždy 304 B:

| Offset | Typ | Obsah |
| --- | --- | --- |
| 0x00 | char[32] | jméno rodiny („Porsche 356A Family“, „Porsche 935 Racecar“) |
| 0x20 | float32 × 24 | tabulka A: roste 8 → 30 a dál drží 30 |
| 0x80 | float32 × 40 | tabulka B: klesá, první hodnota podle výkonu auta (356 59,8; 993 72,7; 959 89,7; 935 a GT1 99,4), konec u všech ≈ 14 |
| 0x120 | 16 B | nuly |

Hypotézy (ověřit v exe, funkce 0x49CA30 a 0x40B650 čtou `.ais` i pole `.sim` 0x13C–0x144):
- **A = dohled v metrech podle rychlostního pásma.** Strop 30 je `max_lookahead` z TRAFCFG, minimum 8 je blízko `min_lookahead` 12. Závodní auta dosahují stropu později.
- **B = nejvyšší rychlost (m/s) podle ostrosti zatáčky.** Index 0 = rovinka, index 39 = nejostřejší zatáčka. B[0] je nad skutečnou maximální rychlostí aut (356 A: 59,8 m/s proti ≈ 44 m/s, 935: 99,4 proti ≈ 94), takže nejde o vmax, spíš o limit, který na rovince neomezuje. Ostré zatáčky mají všechna auta stejné (≈ 14–17 m/s), liší se střední část podle podvozku.
- Pole `.sim` 0x13C (měřítko rychlosti pro tabulku), 0x140 (násobič z profilu a obtížnosti) a 0x144 (násobič tabulky, S-90 1,075) tabulky zřejmě škálují pro konkrétní verzi auta.

## `TRAFCFG.DAT` a `TRAFCFG.DES`

`.DES` je binární popis editoru (jména, typy a komentáře polí), `.DAT` 27 hodnot int32, `Fixed` = 16.16.

| Pole | Hodnota | Význam podle `.DES` |
| --- | --- | --- |
| `latvelcalc_lookahead` | 4 | o kolik řezů dopředu počítat boční rychlost |
| `min_lookahead`, `max_lookahead` | 12, 30 | metry dohledu pro cílový směr |
| `look_ahead_factor` | 0,7 | rychlost → počet řezů dohledu |
| `skid_value` | 11,0 | výpočet smyku přední / zadní nápravy |

Dvě sady „AI physics parameters“, **in control** a **out of control**:

| Pole | In control | Out of control | Význam |
| --- | --- | --- | --- |
| `dlpos_to_dlvel` | 8,0 | 0 (nepoužito) | odchylka boční polohy → požadovaná boční rychlost |
| `max_dlvel` | 32,0 | 16,0 | max. požadovaná boční rychlost |
| `dlvel_to_clacc` | 8,0 | 8,0 | odchylka boční rychlosti → boční zrychlení |
| `dangle_to_dav` | 1,25 | 0,625 | odchylka úhlu → požadovaná úhlová rychlost |
| `max_dav` | 0,8 | 0,8 | max. úhlová rychlost |
| `dav_to_aa` | 5,0 | 10,0 | odchylka úhlové rychlosti → úhlové zrychlení |
| `vel_limit_range` | 20,0 | 10,0 | pod touto rychlostí se boční a úhlová rychlost omezují |
| `lat_vel_limit_factor` | 0,13 | 0,32 | omezení boční rychlosti (rychlost / range × faktor) |
| `ang_vel_limit_factor` | 0,013 | 0,013 | omezení úhlové rychlosti |

(`max_clacc` 24 a `max_aa` 0,8 jsou v `.DES` označené NOT USED.)

**Co z toho plyne:** auta AI (soupeři i provoz) v originále neřídila volantem a pneumatikami. Dokud byla „v kontrole“, hra je posouvala kaskádou regulátorů přímo na boční polohu a natočení podle stopy. Druhá sada s měkčími hodnotami platila po ztrátě kontroly (náraz, smyk). Rozdíl proti hráči tak byl zásadní a laditelný jen čísly v těchto tabulkách.
