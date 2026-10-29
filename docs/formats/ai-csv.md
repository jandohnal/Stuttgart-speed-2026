---
type: file-format
format: ai-csv
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: "GameData/Simulation/AI/*.csv + *.bin"
count: 6
status: done
tool: "tools/ai_csv2json.py"
output: "decomposed/GameData/Simulation/AI/<soubor>.json"
updated: 2026-10-15
---

# Nastavení AI – CSV a jejich `.bin`

Šest tabulek z Excelu s komentáři designérů. Ke každé existuje zkompilovaná binární verze, kterou čte hra.

## Formát `.bin`

Proud `int32` LE bez hlavičky, hodnoty jdou v pořadí, v jakém stojí v CSV:

- první hodnota je `Verbose Mode`,
- čísla za řádkem `!FIXED` jsou fixní řádová čárka 16.16, **useknutá** (0.975 → 63897), za `!INT` celá čísla (výchozí režim),
- symboly (`Symbol:,high,2`) se nahradí číslem, `N/A` = 0,
- `FileSize` v CSV = počet hodnot v `.bin`,
- text, popisky a komentáře se nekompilují.

`tools/ai_csv2json.py` z rozparsovaných dat znovu sestaví tento proud a porovná ho s `.bin`.

## Soubory

| CSV | `.bin` | Hodnot | Obsah | Shoda s `.bin` |
| --- | --- | --- | --- | --- |
| `glue.csv` | `GLUE.BIN` | 22 | „gumička“: násobič rychlosti soupeře podle vzdálenosti od hráče (600 m před … 600 m za), 1.25 → 0.82 | přesná |
| `hhglue.csv` | `hhglue.bin` | 22 | totéž pro jiný režim (hot pursuit / head-to-head?), 1.3 → 0.8 | přesná |
| `prsonal.csv` | `prsonal.bin` | 127 | 9 osobností × 14 vlastností (0 low, 1 medium, 2 high, 3 extreme) | **liší se**, viz níže |
| `SCRIPTS.CSV` | `SCRIPTS.BIN` | 505 | 9 osobností × 7 akcí hráče × 4 kroky (reakce, čas s) | přesná |
| `SPREAD.CSV` | `SPREAD.BIN` | 55 | cílové časy kola tratí 0–10, tabulky rozptylu rychlosti soupeřů (jednotlivý závod, knockout, 3 časové tabulky s interpolací) | přesná |
| `tuning.csv` | `tuning.bin` | 140 | rozestupy v koloně (sloty A–F), násobiče podle auta a obtížnosti, tratě (celkově, v noci), počasí, upgrady | přesná |

### Osobnosti (`prsonal`)

Vlastnosti: blocking distance, cutoff distance, lookahead, swervyness, braking, road rage, driving skill, acceleration, wipe-out frequency, cornering ability, best line ability, rear-end tendency, aggression, cop collision firmness. Popisy od designérů jsou v JSON pod `trait_descriptions`.

`prsonal.bin` je zkompilovaný z jiné revize CSV: osobnosti 0–4 se liší ve 37 ze 127 hodnot, policie (10) a provoz (11) sedí přesně. JSON proto bere hodnoty z `.bin` (to čte hra) a odlišné hodnoty z CSV uvádí v `csv_traits`. `SCRIPTS.CSV` a `SPREAD.CSV` (které s `.bin` sedí) jmenují osobnosti 1–4 Blurrr, Zippy, JetBoy, Menace, `prsonal.csv` Bullit, Frost, Ranger, Chump.

### Akce a reakce (`SCRIPTS`)

Akce hráče: collision, opp wizzed by, human block opp, opp block human, opp pass human, human pass opp, human honk. Reakce: `SPEED_BURST`, `HONK_HORN`, `HARD_BRAKE`, `SWIPE`, `ATTACK`, `PAUSE`, `REAR_END`, `SWERVE`, `MOVE_AWAY`, `WIPE_OUT`, `CRAZY_HORN` (+ `INIT`, `END`, `DEBUG1–4`).

## Poznámky

- Kódy aut v `tuning.csv` (`MSLK`, `BMWZ`, `F550`, `MCF1` …) a jména tratí (Snowy, Celtic, …) pocházejí z NFS4 High Stakes. Tabulky byly převzaty a hra je zřejmě používá jen podle pořadí.
- `TRAFCFG.DAT` (108 B) + `TRAFCFG.DES` (popis polí) jsou jiný formát: regulátory řízení AI, převádí `tools/ais2json.py`, viz [ais.md](ais.md#trafcfgdat-a-trafcfgdes).
- Pro naši hru jsou cenné hlavně myšlenky: gumička podle vzdálenosti, osobnosti jako sada 0–3 vlastností, skriptované reakce na akce hráče, rozestupy v koloně.
