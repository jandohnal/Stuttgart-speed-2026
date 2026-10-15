---
type: file-format
format: sim
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: "GameData/Simulation/CarData/*.sim"
count: 86
size_bytes: 328
endianness: little
status: partial
tool: "tools/sim_dump.py"
updated: 2026-10-15
---

# Formát `.sim` – fyzikální parametry auta

Jeden soubor na verzi auta, pevná délka 328 B. Čísla jsou `float32` LE, pokud není uvedeno jinak.
Potvrzeno porovnáním 13 aut s různou koncepcí (motor vzadu/uprostřed/vpředu, turbo, pohon všech kol) a s reálnými technickými údaji.

## Pole

| Offset | Typ | Pole | Jednotka | Jistota | Příklad (356 A 1.6 / 996 Turbo) |
| --- | --- | --- | --- | --- | --- |
| 0x000 | char[32] | název verze | | jisté | `1956 356 A coupe 1.6L` |
| 0x040 | f32 | hmotnost | kg | jisté | 850 / 1540 |
| 0x044 | f32 | rozvor | mm | jisté | 2100 / 2350 |
| 0x048 | i32 | poloha motoru: 0 vzadu, 1 uprostřed, 2 vpředu | enum | jisté | 0 / 0 (914, Boxster, GT1 = 1; 928, 944 = 2) |
| 0x04C | i32 | přeplňování: 0 atmosférický, 1 turbo | bool | jisté | 0 / 1 |
| 0x050 | i32 | počet převodových stupňů vpřed | | jisté | 4 / 6 |
| 0x054 | i32 | doba řazení? 50.–70. léta 8, 90. léta 6, závodní 4–5 | | odhad | 8 / 6 |
| 0x058 | f32 | setrvačnost motoru? běžně 90, závodní 65–70, 928 100, 959 120 | | odhad | 90 / 90 |
| 0x05C | f32 | podíl momentu na přední nápravu (0 = pohon zadních kol) | % | pravděpodobné | 0 / 35 (959 = 30, 993 Carrera 4 = 40) |
| 0x060 | f32 | převod zpátečky | | jisté | -3.6 / -3.55 |
| 0x068 | f32[n] | převody 1.–n. stupně (n = 0x050) | | jisté | 3.09, 1.765, 1.13, 0.852 |
| 0x080 | f32 | stálý převod | | jisté | 4.428 / 3.44 |
| 0x084 | f32 | šířka pneumatiky | mm | jisté | 145 / 295 |
| 0x088 | f32 | profilové číslo | % | jisté | 70 / 30 |
| 0x08C | f32 | průměr ráfku | palce | jisté | 15 / 18 |
| 0x090 | f32 | maximální rychlost | mph | pravděpodobné | 100 / 190 |
| 0x094 | f32 | otáčky omezovače | ot/min | jisté | 5800 / 6700 |
| 0x098 | f32 | sklon k nedotáčivosti / stabilita: pohon 4 kol +5, motor vpředu 35, turbo 15, závodní 10 | | odhad | 23 / 20 |
| 0x09C | f32[] | křivka točivého momentu po 500 ot/min, ukončená nulou | lb-ft | jisté | max 81 (≈110 Nm) / 413 (≈560 Nm) |
| 0x0F0 | f32 | rozložení hmotnosti (vyšší = víc vzadu): 356 48.5, motor vpředu 44, pohon 4 kol −0.5 až −1 | | odhad | 48.5 / 46 |
| 0x0F4 | f32 | přilnavost, roste s výkonem; cabrio/targa o 0.05 nižší než coupe | | odhad | 1.15 / 2.0 (GT1 2.75) |
| 0x0F8 | f32 | ? (20–32.5), mění se jen u 964 C4 a 993 Turbo | | neznámé | 27.5 / 25 |
| 0x0FC | f32 | ovladatelnost / tuhost karoserie: cabrio/targa o 0.5 nižší než coupe, roste s výkonem | | odhad | 12 / 17 |
| 0x104 | f32 | síla brzd, roste s výkonem auta, pohon 4 kol +0.1–0.2 | | odhad | 6.5 / 10 (GT1 14) |
| 0x108 | f32 | ? (50–70), u pohonu 4 kol nekonzistentní (993 +5, 996 −7.5) | | neznámé | 60 / 65 |
| 0x10C | f32 | aerodynamický přítlak vpředu? 1 u silničních aut, 550 1.1, GT2 1.3, GT3 1.35, 935 1.75, GT1 2 | | odhad | 1 / 1 |
| 0x110 | f32 | aerodynamický přítlak vzadu? 1–1.1 běžně, spoiler (901 RS, turbo) 1.15–1.2, závodní 1.5–2.5 | | odhad | 1 / 1.15 |
| 0x114 | f32 | pár vpředu/vzadu (0x114 ≥ 0x118), klesá se sportovností: 85 → 70 | | neznámé | 85 / 75 |
| 0x118 | f32 | druhá hodnota páru 0x114 | | neznámé | 85 / 70 |
| 0x11C | f32 | přilnavost v zatáčce? cabrio/targa o 0.05–0.1 nižší, 0.6 → 1.5 | | odhad | 0.7 / 1 |
| 0x124 | f32 | světlá výška? 356 140, 911 120, 993 110, 996 100, závodní 50–70 | mm | odhad | 140 / 100 |
| 0x128 | f32 | ? klesá s výkonem 5 → 1 (náklon karoserie?) | | neznámé | 4.5 / 3 |
| 0x12C | f32 | ? klesá s výkonem 3.5 → 0.25 (náklon karoserie?) | | neznámé | 3.25 / 1.5 |
| 0x130 | f32 | 1, jen 928 1.1 | | neznámé | 1 / 1 |
| 0x134–0x13C | f32 | vždy 1 | | konstanta | 1 |
| 0x140 | f32 | ? (0.8–1.15), závodní < 1 | | neznámé | 1 / 1 |
| 0x144 | f32 | výkonová přirážka verze? S-90 1.075, GS a některé S 1.05 | | odhad | 1 / 1 |

Bajty 0x020–0x03F (konec názvu), 0x100 a 0x120 jsou u všech 86 aut nulové.

## Rozsahy neznámých polí (všech 86 aut)

Podklad pro určení zbývajících polí. Výstup: `decomposed/GameData/Simulation/cars.json`, klíč `unknown`.

| Offset | Min | Max | Různých hodnot |
| --- | --- | --- | --- |
| 0x054 | 4 (i32) | 8 | 4 |
| 0x058 | 65 | 120 | 6 |
| 0x098 | 10 | 35 | 9 |
| 0x0F0 | 44 | 48.5 | 9 |
| 0x0F4 | 1.1 | 2.75 | 32 |
| 0x0F8 | 20 | 32.5 | 5 |
| 0x0FC | 11.5 | 17 | 14 |
| 0x104 | 6.2 | 14 | 29 |
| 0x108 | 50 | 70 | 7 |
| 0x10C | 1 | 2 | 6 |
| 0x110 | 1 | 2.5 | 8 |
| 0x114 | 70 | 85 | 9 |
| 0x118 | 70 | 85 | 10 |
| 0x11C | 0.6 | 1.5 | 12 |
| 0x124 | 50 | 140 | 9 |
| 0x128 | 1 | 5 | 11 |
| 0x12C | 0.25 | 3.5 | 14 |
| 0x130 | 1 | 1.1 | 2 |
| 0x134, 0x138, 0x13C | 1 | 1 | 1 (konstanta) |
| 0x140 | 0.8 | 1.15 | 8 |
| 0x144 | 1 | 1.075 | 4 |

Poznámky:
- `default.sim` nese název `1998 996 Carrera 3.4L` a liší se od `996coupe34.sim` jen v polích 0x098, 0x0F8, 0x114, 0x124 a 0x12C. Vypadá jako výchozí/testovací šablona.
- Křivka momentu má 12–17 bodů, vždy pokrývá otáčky omezovače a za ukončovací nulou už jsou jen nuly.

## Porovnání dvojic

Dvojice aut, která se liší jedinou vlastností (výstup z `cars.json`, mění se jen uvedená pole):

| Rozdíl | Dvojice | Změněná pole |
| --- | --- | --- |
| coupe → cabrio/targa | 964, 993, 996 | 0x0F4 −0.05, 0x0FC −0.5, 0x11C −0.05/−0.1 (u 993 cabrio i 0x104 −0.25) |
| coupe → cabrio | 356 A 1.6 | 0x0FC −0.5, 0x128 +0.25 |
| zadní → všechna kola | 964, 993, 996 (coupe i cabrio) | 0x098 vždy 20 → 25, 0x0F0 −0.5 až −1; dále 964: 0x0F8 +2.5, 0x110 −0.1; 993: 0x108 +5; 996: 0x108 −7.5 |
| motor 1.3 → 1.6 l | 356 A coupe | jen 0x104 (7 → 6.5) |
| atmosférický → turbo | 944, 993 | 0x0F4 ↑, 0x104 ↑, 0x110 ↑, 0x114/0x118 −2.5, 0x12C ↓ |
| 3.0 → 3.3 l turbo | 930 | 0x0F4, 0x104, 0x11C ↑, 0x12C ↓ |

Závěry:
- Otevřená karoserie snižuje trojici 0x0F4, 0x0FC, 0x11C → jde o přilnavost/ovladatelnost (nižší tuhost karoserie).
- Pohon všech kol mění spolehlivě jen 0x098 (+5) a 0x0F0 (snížení) → nedotáčivost a posun hmotnosti dopředu.
- 0x10C a 0x110 se liší hlavně u závodních aut a aut se spoilerem → aerodynamika.
- Hodnoty jsou ručně laděné po krocích 0.05, 0.25 a 2.5, nejsou to fyzikální veličiny, ale koeficienty designérů.

## Další kroky

- Ověřit hypotézy proti chování v originále (Wine): změnit jedno pole v kopii `.sim` a sledovat jízdu.
- Až bude pole potvrzené, přidat ho do `tools/sim_dump.py` pod vlastním názvem; do té doby zůstává v `unknown`.
