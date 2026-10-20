---
type: file-format
format: sim
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: "GameData/Simulation/CarData/*.sim"
count: 86
size_bytes: 328
endianness: little
status: mostly-known
tool: "tools/sim_dump.py"
updated: 2026-10-19
---

# Formát `.sim` – fyzikální parametry auta

Jeden soubor na verzi auta, pevná délka 328 B. Čísla jsou `float32` LE, pokud není uvedeno jinak.
Potvrzeno porovnáním 13 aut s různou koncepcí (motor vzadu/uprostřed/vpředu, turbo, pohon všech kol) a s reálnými technickými údaji.

## Pole

Význam polí je od 19. 10. 2026 ověřený rozborem `Porsche.exe` (viz [Analýza Porsche.exe](#analýza-porscheexe-ghidra)). Sloupec **Převod při načtení** říká, jak hra hodnotu ze souboru přepočítá. Struktura v paměti má stejné offsety jako soubor (soubor se zkopíruje na začátek bloku 0x1C4 B). Sloupec **NFS4** je odpovídající parametr `carp.txt` (viz [Reference NFS4](#reference-nfs4-velocity)).

| Offset | Typ | Pole | Jednotka v souboru | Převod při načtení | Jistota | Příklad (356 A 1.6 / 996 Turbo) | NFS4 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0x000 | char[32] | název verze | | | jisté | `1956 356 A coupe 1.6L` | |
| 0x040 | f32 | hmotnost (díly z uhlíku/laminátu ji mění) | kg | | jisté | 850 / 1540 | mass (2) |
| 0x044 | f32 | rozvor | mm | ×0,001 → m | jisté | 2100 / 2350 | wheel_base (24) |
| 0x048 | i32 | poloha motoru: 0 vzadu, 1 uprostřed, 2 vpředu | enum | | jisté | 0 / 0 (914, Boxster, GT1 = 1; 928, 944 = 2) | – |
| 0x04C | i32 | přeplňování: 0 atmosférický, 1 turbo, 2 kompresor (díly) | enum | | jisté | 0 / 1 | – |
| 0x050 | i32 | počet převodových stupňů vpřed | | +2 (zpátečka a neutrál) | jisté | 4 / 6 | manual_number_of_gears (3) |
| 0x054 | i32 | **zpoždění řazení**; díl převodovky ho mění, hodnota < 5 = rychlé (závodní) řazení | tiky | | jisté | 8 / 6 | gear_shift_delay (4) |
| 0x058 | f32 | **účinnost převodu** (násobí sílu na kolech na všech stupních) | % | ×0,01 | vysoká | 90 / 90 | manual_gear_efficiency (9), jedna hodnota |
| 0x05C | f32 | podíl hnací síly na přední nápravu (0 = pohon zadních kol) | % | ×0,01 | jisté | 0 / 35 | front_drive_ratio (16) |
| 0x060 | f32 | převod zpátečky | | → poměr rychlost/otáčky | jisté | -3.6 / -3.55 | manual_gear_ratios (8) |
| 0x064 | f32 | neutrál (vždy 0) | | | jisté | 0 | |
| 0x068 | f32[n] | převody 1.–n. stupně (n = 0x050) | | → poměr rychlost/otáčky (převod × stálý převod × 60 / obvod kola), setup přičítá | jisté | 3.09, 1.765, 1.13, 0.852 | manual_velocity_to_rpm_ratio (7) |
| 0x080 | f32 | stálý převod | | setup přičítá | jisté | 4.428 / 3.44 | manual_final_gear (11) |
| 0x084 | f32 | šířka pneumatiky | mm | → obvod kola 0x148 | jisté | 145 / 295 | tire_specs (35, 36) |
| 0x088 | f32 | profilové číslo | % | → obvod kola | jisté | 70 / 30 | tire_specs |
| 0x08C | f32 | průměr ráfku | palce | → obvod kola | jisté | 15 / 18 | tire_specs |
| 0x090 | f32 | maximální rychlost (z ní se dopočítá odpor vzduchu 0x1B0) | mph | ×0,4464 → m/s; přítlak a díly motoru ji upraví | jisté | 100 / 190 | maximum_velocity (14) |
| 0x094 | f32 | otáčky omezovače | ot/min | | jisté | 5800 / 6700 | engine_redline_rpm (13) |
| 0x098 | f32 | **brzdění motorem** po uvolnění plynu (podíl momentu) | % | ×0,01 | vysoká | 23 / 20 | gas_off_factor (32) |
| 0x09C | f32[21] | křivka točivého momentu po 500 ot/min, ukončená nulou; díly motoru přičítají 0,67 × křivku dílu | lb-ft | | jisté | max 81 / 413 | torque_curve (10) |
| 0x0F0 | f32 | **podíl přilnavosti (zatížení) přední nápravy**; pneumatiky a tlak v nich ho mění, 959 má pevně 0,4675 | % | ×0,01 | jisté | 48.5 / 46 | front_grip_bias (25) |
| 0x0F4 | f32 | **součinitel přilnavosti** (síla kola = hmotnost × 9,8 × hodnota); mění ho pneumatiky, pružiny, stabilizátory, světlá výška a tlak | | | jisté | 1.15 / 2.0 | lateral_acceleration_grip_multiplier (30) |
| 0x0F8 | f32 | **přenos zatížení** mezi nápravami při zrychlení/brzdění i v zatáčce (děleno tuhostí 0x11C) | % | ×0,01 | vysoká | 27.5 / 25 | g_transfer_factor (33) |
| 0x0FC | f32 | **řízení**: rozsah natočení kol; při nízké rychlosti se rozsah zvětšuje (strop 20) | | | střední | 12 / 17 | minimum_steering_acceleration (27)? |
| 0x100 | f32 | sbíhavost (toe); v souboru 0, plní ji nastavení STEERING – TOE IN | | | vysoká | 0 | – |
| 0x104 | f32 | **maximální brzdné zpomalení**; díl brzd a poškození brzd ho mění | m/s² | | jisté | 6.5 / 10 | maximum_braking_deceleration (18) |
| 0x108 | f32 | **podíl brzdné síly vpředu**; nastavení BRAKE BALANCE posouvá o ±0,25 | % | ×0,01 | jisté | 60 / 65 | front_bias_brake_ratio (19) |
| 0x10C | f32 | **přítlak přední nápravy** (přičítá se k zatížení podle rychlosti); díl spoileru a nastavení DOWNFORCE FRONT ho násobí | | ×0,001 | jisté | 1 / 1 | aerodynamic_downforce_multiplier (31) |
| 0x110 | f32 | **přítlak zadní nápravy**; nastavení DOWNFORCE REAR | | ×0,001 | jisté | 1 / 1.15 | aerodynamic_downforce_multiplier (31) |
| 0x114 | f32 | tlumení podélného naklápění karoserie (podíl předchozí výchylky, který zůstává); díl tlumičů a tuhost ho snižují | % | ×0,01 | vysoká | 85 / 75 | – |
| 0x118 | f32 | tlumení příčného náklonu karoserie | % | ×0,01 | vysoká | 85 / 70 | – |
| 0x11C | f32 | **tuhost zavěšení**: dělí přenos zatížení; pružiny, stabilizátory a nastavení SHOCKS – STIFFNESS ji zvyšují | | | vysoká | 0.7 / 1 | – |
| 0x120 | f32 | zdvih pérování; v souboru 0, plní ho nastavení SHOCKS – TRAVEL a pružiny | mm | ×0,001 | vysoká | 0 | – |
| 0x124 | f32 | světlá výška; nastavení SHOCKS – RIDE HEIGHT přičítá | mm | ×0,001 → m | jisté | 140 / 100 | – |
| 0x128 | f32 | podélné naklopení karoserie na jednotku podélného zrychlení | | ×0,001 | vysoká | 4.5 / 3 | pitch_roll_factor (45) |
| 0x12C | f32 | příčný náklon karoserie na jednotku bočního zrychlení; tužší pružiny, stabilizátory a nižší podvozek ho snižují | | ×0,001 | vysoká | 3.25 / 1.5 | pitch_roll_factor (45) |
| 0x130 | f32 | rozdělení bočního přenosu zatížení mezi přední a zadní nápravu; díl pružin ho mění | | | střední | 1 / 1 | – |
| 0x134 | f32 | mez podélného naklopení karoserie | | | vysoká | 1 | – |
| 0x138 | f32 | mez příčného náklonu karoserie | | | vysoká | 1 | – |
| 0x13C | f32 | AI: měřítko rychlosti pro tabulku soupeře | | | střední | 1 | – |
| 0x140 | f32 | AI: násobitel z profilu soupeře (`.ais`) a obtížnosti | | | střední | 1 / 1 | – |
| 0x144 | f32 | AI: násobitel tabulky soupeře (verze S-90 1.075, GS 1.05) | | | střední | 1 / 1 | – |

Za koncem souboru (0x148–0x1C3) dopočítá hra pomocné hodnoty: obvod kola (0x148), převrácené otáčky omezovače (0x14C), tabulky pro každý stupeň (0x170–), součinitel odporu vzduchu z maximální rychlosti a momentu (0x1B0), hodnoty z rozvoru (0x1B4, 0x1B8), převrácenou přilnavost (0x1BC) a typ pneumatik (0x1C0: 2 = závodní u GT1, GT2, GT3, 935; mění ho díl pneumatik).

Bajty 0x020–0x03F (konec názvu), 0x064 (neutrál), 0x100 (sbíhavost) a 0x120 (zdvih) jsou u všech 86 aut nulové, plní je až hra.

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

## Korelace se známými vlastnostmi

Pearsonův korelační koeficient přes 85 aut (bez `default`). Výkon je odhadnutý z křivky momentu (max. moment × otáčky / 5252, hp). Éra je přibližný rok modelové řady. „Otevřená“ znamená cabrio, targa, speedster, convertible nebo roadster. Hodnoty |r| ≥ 0,7 jsou tučně.

| Pole | hmotnost | výkon | výkon/kg | vmax | motor vpředu | turbo | 4×4 | závodní | éra | pneumatika | otevřená |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0x054 | −0,59 | **−0,86** | **−0,81** | **−0,85** | 0,22 | −0,44 | −0,45 | −0,53 | **−0,74** | **−0,80** | 0,21 |
| 0x058 | 0,10 | −0,32 | −0,49 | −0,20 | 0,05 | −0,14 | 0,15 | −0,46 | −0,13 | −0,18 | 0,03 |
| 0x098 | 0,29 | −0,15 | −0,27 | −0,02 | **0,75** | −0,06 | 0,20 | −0,18 | 0,21 | 0,12 | 0,07 |
| 0x0F0 | **−0,77** | −0,61 | −0,47 | **−0,72** | −0,58 | −0,27 | −0,38 | −0,22 | **−0,86** | **−0,77** | 0,17 |
| 0x0F4 | **0,73** | **0,94** | **0,88** | **0,95** | 0,17 | 0,53 | 0,36 | 0,49 | **0,89** | **0,94** | −0,31 |
| 0x0F8 | 0,36 | −0,09 | −0,24 | 0,04 | 0,22 | −0,14 | 0,14 | −0,36 | 0,22 | 0,08 | 0,12 |
| 0x0FC | **0,87** | **0,82** | 0,67 | **0,94** | 0,19 | 0,41 | 0,46 | 0,26 | **0,96** | **0,93** | −0,35 |
| 0x104 | 0,67 | **0,92** | **0,87** | **0,92** | −0,00 | 0,47 | 0,40 | 0,56 | **0,84** | **0,91** | −0,25 |
| 0x108 | −0,06 | 0,17 | 0,21 | 0,11 | −0,56 | 0,03 | 0,28 | 0,26 | −0,05 | 0,04 | 0,06 |
| 0x10C | −0,06 | 0,62 | **0,81** | 0,39 | −0,06 | 0,38 | −0,08 | **0,83** | 0,19 | 0,36 | −0,17 |
| 0x110 | 0,15 | **0,77** | **0,90** | 0,57 | −0,07 | 0,55 | 0,03 | **0,78** | 0,38 | 0,55 | −0,23 |
| 0x114 | −0,54 | **−0,85** | **−0,82** | **−0,84** | 0,09 | −0,43 | −0,35 | −0,53 | **−0,70** | **−0,84** | 0,23 |
| 0x118 | **−0,74** | **−0,85** | **−0,76** | **−0,93** | −0,12 | −0,47 | −0,35 | −0,35 | **−0,85** | **−0,90** | 0,31 |
| 0x11C | 0,52 | **0,90** | **0,90** | **0,83** | 0,03 | 0,54 | 0,26 | 0,63 | 0,68 | **0,84** | −0,34 |
| 0x124 | −0,40 | **−0,79** | **−0,81** | **−0,74** | 0,13 | −0,40 | −0,25 | −0,61 | −0,63 | −0,67 | 0,28 |
| 0x128 | −0,43 | **−0,83** | **−0,85** | **−0,80** | 0,17 | −0,30 | −0,33 | **−0,70** | −0,67 | **−0,76** | 0,25 |
| 0x12C | −0,65 | **−0,91** | **−0,88** | **−0,93** | −0,14 | −0,47 | −0,32 | −0,58 | **−0,83** | **−0,89** | 0,31 |
| 0x140 | 0,07 | −0,35 | −0,46 | −0,19 | 0,13 | −0,33 | −0,04 | −0,46 | −0,11 | −0,23 | 0,09 |
| 0x144 | −0,35 | −0,24 | −0,13 | −0,21 | −0,12 | −0,17 | −0,16 | 0,02 | −0,38 | −0,29 | 0,16 |

Většina polí silně koreluje s „výkonností“ auta (výkon, vmax, pneumatika, éra), protože designéři ladili hodnoty po řadách. Samotná korelace s výkonem proto význam pole neurčí. Rozhodují pole, která reagují na jedinou vlastnost: 0x098 a 0x0F0 na motor vpředu, 0x10C a 0x110 na závodní auta a spoilery, 0x0F4, 0x0FC a 0x11C na otevřenou karoserii (viz [Porovnání dvojic](#porovnání-dvojic)).

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
- Pohon všech kol mění spolehlivě jen 0x098 (+5) a 0x0F0 (snížení) → nedotáčivost a posun přilnavosti dozadu (méně vpředu).
- 0x10C a 0x110 se liší hlavně u závodních aut a aut se spoilerem → aerodynamika.
- Hodnoty jsou ručně laděné po krocích 0.05, 0.25 a 2.5, nejsou to fyzikální veličiny, ale koeficienty designérů.

## Reference NFS4 (Velocity)

Zdroj: projekt Velocity / [HighStakesRE](https://github.com/e-rk/HighStakesRE) (dříve `e-rk/velocity`) – rekonstrukce jízdního modelu NFS4 High Stakes v Godotu (soubory `core/car/performance.gd` a `core/car/handling_model_re.gd`). Formát `carp.txt` je v konvertoru [speedtools](https://github.com/e-rk/speedtools) (`speedtools/carp_data.py`). Oba projekty jsou pod **GPL-3**. Slouží jen jako reference pro význam a rozsahy parametrů, žádný jejich kód se do projektu nepřebírá (D-012).

Testy Velocity používají data naměřená v originále na autě **B911** (911 Turbo, generace 993). Totéž auto je v NFS5 jako `993Tcoupe36`, takže hodnoty lze porovnat přímo. Hodnoty B911 níže jsou dopočítané z testovacích CSV Velocity (`tests/handling-model/data/`).

`carp.txt` je textový soubor s dvojicemi řádků „název (index)“ a hodnota. Pořadí indexů 0–80 je pevné. NFS4 simuluje v ticích 1/32 s a vstupy má v bajtech 0–255 (řízení ±128).

| NFS4 parametr (index) | Jak ho model používá | Jednotka / rozsah | B911 |
| --- | --- | --- | --- |
| mass (2) | dělí tah kol (efektivní převod = převod × účinnost / (10 × hmotnost)) | kg | 1275 |
| manual_number_of_gears (3) | počet stupňů | | |
| gear_shift_delay (4) | po přeřazení se odpočítává čítač, dokud neklesne na 0, a motor zatím netáhne. Hodnota < 5 = rychlejší pokles otáček při řazení (závodní auto) | tiky 1/32 s | |
| shift_blip_in_rpm (5), brake_blip_in_rpm (6) | při podřazení přičte k otáčkám meziplyn podle stupně. Brake blip platí při sešlápnuté brzdě (> 65/255), shift blip jinak. Shift blip 1. stupně zvedá otáčky i ve vzduchu | ot/min na stupeň | |
| torque_curve (10) | moment po 500 ot/min, lineární interpolace | | |
| engine_minimum_rpm (12), engine_redline_rpm (13) | rozsah otáček | ot/min | |
| maximum_velocity (14) | z ní a z momentu při vmax se dopočítá aerodynamický odpor (∝ v³) | m/s | |
| front_drive_ratio (16) | podíl tahu na přední kola | 0–1 | |
| has_abs (17) | omezí podélnou sílu kola na jeho přilnavost | bool | |
| maximum_braking_deceleration (18) | brzdná síla = pedál × hodnota, rozdělená podle (19). Se spoilerem se přičítá v × přítlak | m/s² | ≈ 11,85 |
| front_bias_brake_ratio (19) | podíl brzdy vpředu, omezený na 0,30–0,75. Při ztrátě přilnavosti +0,05 | 0–1 | ≈ 0,63 |
| gas_increasing/decreasing_curve (20, 21) | v rekonstrukci nepoužité, plyn má pevnou rampu 16/255 za tik (0 → plný za 0,5 s) | | |
| brake_increasing/decreasing_curve (22, 23) | rychlost změny brzdy za tik podle aktuální úrovně (8 pásem po 32/255) | 1/255 za tik | náběh 64, 32, 16, 8, …; uvolnění 32 |
| wheel_base (24) | podle komunity bez vlivu | | |
| front_grip_bias (25) | přilnavost přední nápravy = celková × hodnota, zadní × (1 − hodnota) | 0–1 | ≈ 0,45 |
| minimum_steering_acceleration (27) | škáluje úhel natočení kol a jeho dvojnásobek omezuje boční sílu kola. Pod 13,4 m/s bez plynu se strop dělí čtyřmi | | |
| turn_in_ramp (28), turn_out_ramp (29) | rychlost změny polohy volantu za tik: k cíli (in), resp. zpět k nule při puštění nebo protisměru (out) | 1/128 rejdu za tik | 16 / 32 (plný rejd za 0,25 s, návrat za 0,125 s) |
| lateral_acceleration_grip_multiplier (30) | základní přilnavost kola = gravitace × hodnota × povrch. Celkové podélné zrychlení se jí zase dělí | bezrozměrné (jako μ) | |
| understeer_gradient (80) | boční síla předních kol × 0,8 × hodnota, zadních × 1,4 / hodnota. Vyšší hodnota posouvá boční sílu dopředu | bezrozměrné | |
| aerodynamic_downforce_multiplier (31) | nad 10 m/s násobí přilnavost kol (1 + v × hodnota). Zadní kola mají ×1,5 (se spoilerem při brzdění ×1,75). Zároveň tlačí karoserii k zemi | 1/(m/s) | ≈ 0,0024 |
| gas_off_factor (32) | po uvolnění plynu (cílové otáčky < otáčky z rychlosti) působí brzdná síla motoru = tah × hodnota | | |
| g_transfer_factor (33) | přesun přilnavosti mezi nápravami = podélné zrychlení × hodnota (+ složka sklonu). Odečítá se vpředu a přičítá vzadu. Při brzdění je přesun ×0,75, při přetížení pohonu ×0,5, na mokru ±10 % | | |
| turning_circle_radius (34) | omezuje úhlovou rychlost ve stáčení podle rychlosti (hlavně ve smyku a v malé rychlosti) | m | |
| tire_specs, slide_*, push_factor, low/high_turn_factor, pitch_roll_factor (35–46) | v rekonstrukci nepoužité | | |
| spoiler_function_type (47) | auto má aktivní spoiler (přídavný přítlak při brzdění) | bool | |
| engine_tuning … tire_factor (60–66) | ladicí faktory nastavení. V rekonstrukci je použit jen tire_factor (pevně 1,0) | ≈ 1 | |

## Analýza Porsche.exe (Ghidra)

Rozbor z 19. 10. 2026 (pilot [IDEA-012](../../ideas/exe-analysis-rea-ghidra.md)): `Porsche.exe` z oficiálního patche EA (5. 6. 2000, SHA-256 `32c208e5…5b70`, nešifrovaný), Ghidra 12.1.4 přes REA 6.7.0 a headless Ghidru. Výstupy Ghidry (projekt, pseudokód) jsou jen v `decomposed/ghidra/`. Sem se zapisují jen významy polí a principy, žádný dekompilovaný kód (D-001).

Funkce (adresy ve `Porsche.exe`, vlastní názvy):

| Adresa | Co dělá | Použitá pole |
| --- | --- | --- |
| 0x49C6C0 | načte `<auto>.sim` (nebo `default.sim`) do bloku 0x1C4 B a převede jednotky (tabulka [Pole](#pole)). V jednom zjednodušeném režimu hry navíc rozvor ×0,8, tlumení karoserie ×0,83 a přilnavost ×1,25 | vše |
| 0x49CB50 | použije namontované díly a nastavení auta, dopočítá pomocné hodnoty ([prt.md](prt.md#jak-díl-mění-fyziku-porscheexe-0x49cb50)) | díly: motor/turbo/kompresor → 0x09C a 0x04C; brzdy → 0x104; převodovka → 0x054 a převody; pružiny → 0x11C, 0x130, 0x0F4, 0x12C, 0x120; tlumiče → 0x114/0x118, 0x0F4; stabilizátory → 0x11C, 0x0F4, 0x12C; aerodynamika → 0x10C/0x110; pneumatiky → 0x0F4, 0x0F0, 0x1C0 |
| 0x4A1900 | statické zatížení a přilnavost kol, přenos zatížení a přítlak | 0x0F0, 0x0F4, 0x0F8, 0x10C, 0x110, 0x11C, 0x130, 0x1C0 |
| 0x49F160 | jeden krok jízdního modelu: řízení, brzdy, rozdělení hnací síly | 0x05C, 0x0F4, 0x0FC, 0x100, 0x104, 0x108 |
| 0x49E440 | motor a převodovka (otáčky, brzdění motorem, řazení) | 0x054, 0x05C, 0x094, 0x098, 0x1B0 |
| 0x4A20D0 | síly jednoho kola | 0x0F4, 0x0FC, 0x1C0 |
| 0x499A70 | pohyb karoserie (naklápění, náklon, pérování) | 0x114–0x138 |
| 0x49CA30, 0x40B650 | AI soupeřů (`.ais`) | 0x13C, 0x140, 0x144 |

Principy (popis, ne kód):
- **Motor a převodovka jsou stejné jako v NFS4.** Otáčky se mění pevnými kroky za tik (+250, −100, ±50). Hnací síla = moment × poměr rychlost/otáčky × účinnost (0x058) / hmotnost × 0,1, tedy stejný vzorec jako NFS4 gear_effective_ratio. Při podtáčení (otáčky motoru nad otáčkami z rychlosti) brzdí motor silou −moment × 0x098. Hodnota 0x054 < 5 zapíná rychlejší pokles otáček při řazení stejně jako v NFS4. Odpor vzduchu se dopočítá z momentu při maximální rychlosti / v³ (0x1B0), stejně jako NFS4 longitudal_drag_coefficient.
- **Přilnavost kola** = hmotnost × 9,8 × 0x0F4 × faktor povrchu (tabulka podle typu pneumatik 0x1C0 a povrchu). Přední kola dostanou podíl 0x0F0, zadní 1 − 0x0F0 (po polovině na kolo).
- **Přenos zatížení:** podélné i boční zrychlení / 9,8 × 0x0F8 × 0,2 / 0x11C přesouvá zatížení z přední nápravy na zadní a zpět. Boční přenos se mezi přední a zadní nápravu dělí podle 0x130. Tužší zavěšení (0x11C) přenos zmenšuje.
- **Přítlak:** nad 5 m/s se k zatížení předních kol přičítá 0x10C × rychlost × (1 − poškození × 0,005), k zadním 0x110 × totéž. Nastavení DOWNFORCE násobí oba koeficienty a zároveň snižuje maximální rychlost.
- **Brzdy:** brzdná síla = pedál × 0x104 × (1 − poškození brzd × 0,005), omezená úměrně rychlosti. Přední náprava dostane podíl 0x108, zadní zbytek.
- **Pohon:** podíl 0x05C jde na přední kola a dělí se podle zatížení kol, zbytek na zadní.
- **Řízení:** úhel kol = vstup (±127) ± sbíhavost 0x100, násobený faktorem z 0x0FC. Do určité rychlosti se rozsah zvětšuje a nad 80 se zmenšuje s rychlostí. Přesnou jednotku 0x0FC se nepodařilo určit.
- **Karoserie:** naklopení = 0x128 × podélné zrychlení, náklon = 0x12C × boční zrychlení. Obojí je omezené mezemi 0x134/0x138 a tlumené 0x114/0x118: v každém kroku zůstává podíl předchozí výchylky.

Řetězce v exe: nastavení `.FRONTDOWNFORCE`, `.REARDOWNFORCE`, `.BRAKEBIAS`, `.SUSPENSIONSTIFFNESS`, `.SUSPENSIONTRAVEL`, `.STEERINGTOE`, `.FRONTTIREPRESSURE`, `.REARTIREPRESSURE`, díly `Engine`, `Turbo`, `Supercharged`, `Gear Box`. Výjimky podle jména auta: GT1, GT2, GT3 a 935 mají závodní pneumatiky; 959 má pevné 0x0F0.

## Hypotézy z NFS4 – výsledek ověření

| Pole | Hypotéza (NFS4) | Výsledek z exe |
| --- | --- | --- |
| 0x054 | gear_shift_delay | **potvrzeno** (stejný práh < 5, mění ho díl převodovky) |
| 0x0F0 | front_grip_bias | **potvrzeno** (podíl přilnavosti přední nápravy) |
| 0x104 | maximum_braking_deceleration | **potvrzeno** |
| 0x108 | front_bias_brake_ratio | **potvrzeno** (nastavení BRAKE BALANCE) |
| 0x0F4 | lateral_acceleration_grip_multiplier | **potvrzeno** (součinitel přilnavosti × m × 9,8) |
| 0x10C / 0x110 | aerodynamic_downforce_multiplier | **potvrzeno** a škála sedí: ×0,001 → 0,001–0,0025, B911 v NFS4 0,0024. Hodnota 1 tedy není „bez přítlaku“ |
| 0x098 | understeer_gradient | **vyvráceno** → gas_off_factor (brzdění motorem) |
| 0x0FC | minimum_steering_acceleration | částečně: jde o řízení, přesný vztah nejistý |
| 0x128 / 0x12C | pitch_roll_factor | **potvrzeno** (naklopení a náklon karoserie) |
| 0x130–0x144 | ladicí faktory | **vyvráceno**: 0x130 rozdělení bočního přenosu, 0x134/0x138 meze náklonu, 0x13C–0x144 parametry AI |
| 0x058 | (setrvačnost motoru) | **vyvráceno** → účinnost převodu (manual_gear_efficiency) |
| 0x0F8 | – | g_transfer_factor (přenos zatížení) |
| 0x114 / 0x118 | (zdvih tlumičů) | tlumení naklápění a náklonu karoserie |
| 0x11C | – | tuhost zavěšení |

## Návrhy testů v prototypu

Význam polí je ověřený z exe. Testy už neslouží k určení polí, ale k ověření, že je náš model používá ve správném měřítku. Každý test mění jedno pole v kopii dat (ne v `decomposed/`) a porovnává telemetrii (F2).

| Pole | Změna | Měření | Očekávání |
| --- | --- | --- | --- |
| 0x0F4 | ×0,8 / ×1,2 | maximální boční zrychlení na skidpadu (kruh R 50 m) | změna boční g úměrná hodnotě |
| 0x104 | 6,5 / 10 / 14 | brzdná dráha 100–0 km/h | zpomalení ≈ hodnota m/s², dokud nezačne omezovat přilnavost |
| 0x108 | 50 / 70 | která náprava při plném brzdění zablokuje první (bez ABS) | 70 → přední, 50 → zadní |
| 0x0F0 | 44 / 48,5 | poměr směrových úhlů přední/zadní nápravy v ustálené zatáčce | nižší hodnota → víc nedotáčivosti |
| 0x098 | 10 / 35 | zpomalení po uvolnění plynu na 3. stupeň | úměrné hodnotě |
| 0x10C / 0x110 | 1 / 2 | boční g na skidpadu při 60 a 150 km/h | rozdíl roste s rychlostí |

## Postřehy pro jízdní model

Principy modelu NFS4 relevantní pro naše problémy. Je to jen popis, žádný převzatý kód. Odkazy na náš kód: `game/scripts/car.gd`.

- **Náběh řízení (turn_in/turn_out ramp).** Volant se u klávesnice nepřepíná skokem, ale mění se konstantní rychlostí k cíli. Návrat k nule je **dvakrát rychlejší** než náběh (B911: plný rejd za 0,25 s, návrat za 0,125 s). Při přechodu zleva doprava se nejdřív použije rychlost návratu. Výsledný úhel kol se dál zmenšuje s rychlostí (nad ~40 m/s až na 1/1,5) a při velkém směrovém úhlu auta. U nás je jediná rychlost `steer_rate` (4 rad/s) pro oba směry. Oddělit náběh a návrat je levná změna, která zlepší „vracení“ volantu po puštění klávesy.
- **Náběh plynu.** NFS4 má pevnou lineární rampu 0 → plný za 0,5 s bez ohledu na rychlost. Hlavní ochrana proti prokluzu je v tom, že tah na 1. stupeň je shora omezený (strop tahu podle stupně). Naše `throttle_rise_time` (0,4 s → 0,15 s podle tempa) je podobná, NFS4 navíc omezuje sílu na nízkých stupních.
- **gas_off_factor.** Brzdění motorem není konstantní moment. Je to záporný tah motoru při daných otáčkách × faktor, takže roste s převodem a s křivkou momentu. Naše `engine_brake` (podíl max. momentu × otáčky / omezovač) má podobný tvar, rozdíl je v závislosti na převodovém stupni.
- **g_transfer_factor (přenos zatížení).** NFS4 nepočítá zatížení kol z pružin. Přilnavost přední a zadní nápravy posouvá o (podélné zrychlení × faktor). Přesun se zpožďuje o jeden krok, protože se počítá ze zrychlení předchozího kroku. Při brzdění je tlumený (×0,75), při prokluzu pohonu poloviční. Výsledkem je předvídatelné „přenesení váhy“ bez kmitání pérování. U nás vychází přenos z fyziky zavěšení (Jolt) a je citlivější na kmitání. Tlumení přesunu při brzdění je principem, který stojí za vyzkoušení, pokud se auto při prudkém brzdění v zatáčce točí.
- **Brzdné křivky.** Brzda nenabíhá lineárně. Rychlost náběhu závisí na tom, jak je už sešlápnutá: první osmina rychle (64/255 za tik), pak čím dál pomaleji (32, 16, 8…). Uvolnění má konstantní rychlost. Klepnutí na klávesu tedy dá rychle jemné přibrzdění a plná brzda přijde až po držení. Naše `brake_rise_time` 0,6 s je lineární. Progresivní tvar by ukázal stejný princip („ťuknutí jen přibrzdí“) s rychlejší první reakcí.
- **Rozdělení brzd a ztráta přilnavosti.** Při smyku se brzdná síla posune o 5 % dopředu. To stabilizuje auto, protože zadní kola méně blokují. Odpovídá to naší `abs_slip_rear` a `brake_front_bias` (0,58). Hodnotu `brake_front_bias` lze brát přímo z 0x108 (ověřeno v exe).
- **Vyvážení boční síly (understeer_gradient).** Boční síla vpředu se násobí 0,8 × UG, vzadu 1,4 / UG. Jediné číslo tak posouvá vyvážení mezi přední a zadní nápravou bez změny celkové přilnavosti. NFS5 tento parametr v `.sim` nemá: vyvážení řídí jen podíl přilnavosti 0x0F0 a přenos zatížení 0x0F8 / 0x11C / 0x130.
- **NFS5 oproti NFS4 (z exe).** Model motoru a převodovky je převzatý skoro beze změny. Přilnavost se ale počítá ze zatížení kol: statický podíl 0x0F0, přenos podle zrychlení (0x0F8 / tuhost 0x11C) a přítlak podle rychlosti. NFS4 posouvá jen „přilnavost“. Pro náš model z toho plyne, že přenos zatížení bez simulace pružin (zrychlení × faktor / tuhost) stačí na chování originálu.

## Další kroky

- Prototyp (`game/scripts/car.gd`, `Car._derive_from_data`) od 19. 10. 2026 bere přímo z dat:
  - 0x104 jako zpomalení v m/s²;
  - 0x108 jako podíl brzd vpředu;
  - 0x058 jako účinnost převodu;
  - 0x098 jako brzdění motorem (výsledky v `game/README.md`).

  Zbývá převést přítlak 0x10C/0x110 (×0,001 × rychlost, má ho i silniční auto) a 0x0F0 / 0x0F4 kalibrací ([driving-model.md](../driving-model.md#jak-zpracovat-naměřená-data)).
- `tools/sim_dump.py`: přejmenovat pole se stupněm „jisté“ a „vysoká“ z `unknown` na pojmenované klíče (zatím neprovedeno).
- Jednotku 0x0FC (řízení) a vztah 0x13C–0x144 k AI lze dořešit cíleným rozborem 0x49F160 a 0x40B650.
- Ověřit chování v originále (Wine) testy výše.
