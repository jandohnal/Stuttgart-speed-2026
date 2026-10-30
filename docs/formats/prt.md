---
type: file-format
format: prt
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: "FEData/Data/nfs5.prt"
count: 1
size_bytes: 267840
endianness: little
status: mostly-known
tool: "tools/parts.py"
updated: 2026-10-19
---

# Formát `nfs5.prt` – katalog dílů (upgrady)

Katalog všech dílů obchodu originálu: 744 záznamů po 0x168 B, jeden na díl a řadu (stejný díl pro 356 A a 356 B je dvakrát). Který díl jde na které auto, neurčuje řada ani rok, ale **seznam ID v záznamu auta** v `nfs5.car` ([car.md](car.md#seznamy-dílů)). Rozluštěno 19. 10. 2026 z dat a rozboru `Porsche.exe` (D-023). Převodník `tools/parts.py` → `decomposed/FEData/Data/parts.json`, ve hře `game/scripts/car_parts.gd` (D-024).

## Záznam (0x168 B)

| Offset | Typ | Pole | Příklad |
| --- | --- | --- | --- |
| 0x00 | u16 | **ID dílu** (na něj odkazuje `nfs5.car`) | 13 |
| 0x04 | u32 | ID názvu v `FEData/Locale/festrings.csv` | 5124 = Stock Tires |
| 0x08 | char[30] | řada | „356A“, „911 (993)“, „GT1“ |
| 0x26 | u16 | **kategorie** (tabulka níže) | 2 |
| 0x28 | char[30] | **skupina** (jméno slotu): „Engine“, „Engine (Standard)“, „Turbo“, „Gear Box“, „Shifter“, „Spoiler“… U pneumatik prázdné | „Brakes“ |
| 0x46 | u16 | rok, od kterého díl obchod v kariéře nabízí | 1956 |
| 0x48 | u8[10] | **maska zón poškození**: 1 = díl se poškozuje ze zóny 0–9 ([damage-model.md](../damage-model.md)). Motor, převodovka, výfuk podle uložení motoru (vzadu 4–6, vpředu 0–2, uprostřed 3–7), brzdy, pružiny, tlumiče a pneumatiky rohy 0, 2, 4, 6, dveře boky 3, 7, spoiler záď 5 | 0,0,0,0,1,1,1,0,0,0 |
| 0x54 | f32 | změna hmotnosti, kg (laminát, uhlík záporně) | −65 |
| 0x58 | f32 | snížení maximální rychlosti, % (aerodynamika, díly) | 1 |
| 0x5C | u32 | cena | 900 |
| 0x60 | f32 | **odolnost** dílu při poškození, %: poškození dílu = průměr zón z masky × (1,5 − odolnost / 200); u lehkých dílů karoserie (kategorie 7) jiné hodnoty (−65…75), význam nejasný | 100 |
| 0xC0 | f32 | **účinek** c0; u převodovky stálý převod | 1,0 = sériový, 2,0 |
| 0xC4 | f32 | **účinek** c4 (zadní náprava u pneumatik a aerodynamiky, světlá výška u pružin) | |
| 0xC8 | i32 | typ pneumatik: 0 sériové, 1 do deště, 2 slick | |
| 0xEA | i16 | převodovka: počet stupňů vpřed | 4 |
| 0xEC | i16 | převodovka: zpoždění řazení (Shifter: přičítá se) | 8 |
| 0xF0 | f32[8] | převodovka: zpátečka, neutrál, 1.–6. stupeň | −3,6, 0, 3,09… |
| 0x110 | f32[21] | křivka momentu po 500 ot/min (lb-ft): celý motor ji nahradí, ostatní motorové díly přičtou její část | |

### Kategorie (0x26)

| Kód | Kategorie | Skupiny | Mění v `.sim` |
| --- | --- | --- | --- |
| 1 | motor | Engine, Engine (Standard), Turbo, Supercharger, Exhaust, Air Intake, Carbs, Flywheel, Computer Chip, Fuel Injector, Intercooler, Throttle Body | křivka momentu 0x09C, přeplňování 0x04C (jen skupina „Turbo“; exe hledá „Supercharged“, které v datech není) |
| 2 | brzdy | Brakes | 0x104 |
| 3 | převodovka | Gear Box, Shifter | 0x050, 0x054, převody 0x060–0x07C, stálý převod 0x080 |
| 4 | pružiny | Springs | 0x11C, 0x130, 0x0F4, 0x12C, 0x120 |
| 5 | tlumiče | Shocks | 0x114, 0x118, 0x0F4 |
| 6 | aerodynamika | Front Dam / Rear Dam, Spoiler | 0x10C, 0x110 |
| 7 | lehké díly karoserie | Hood, Doors, Body (Fiberglass / Carbon Fiber …), Bumpers | jen hmotnost |
| 8 | stabilizátory | Sway Bars | 0x11C, 0x0F4, 0x12C |
| 9 | pneumatiky | (bez jména) | 0x0F4, 0x0F0, typ pneumatik 0x1C0 |
| 10 | vzhled | Body (lak), Rims, Roof | nic (obchod skupinu „Body“ této kategorie nevypisuje) |

Každý díl navíc přičte 0x54 k hmotnosti a vydělí maximální rychlost (1 + 0x58 %).

## Jak díl mění fyziku (Porsche.exe 0x49CB50)

Popis principů, ne kód (D-001). Konstanty vzorců čte `tools/parts.py` přímo z exe (adresy jsou v nástroji) a ukládá je do `parts.json` → `formula`; v repozitáři nejsou (D-023).

- Auto má 20 slotů s namontovanými díly. Hra je projde po načtení `.sim` a díl s nenulovou kategorií použije.
- **Sériové díly jsou neutrální**: účinek 1,0, nulová hmotnost, křivka a změna vmax, převodovka shodná s `.sim`. Ověřeno pro všechna auta (`game/tests/parts_test`). `.sim` tedy popisuje sériové auto.
- **Motor:** skupina „Engine“ (výměna motoru) křivku momentu nahradí; ostatní motorové díly k ní přičtou pevný podíl své křivky. „Turbo“ nastaví přeplňování.
- **Brzdy, pružiny, tlumiče, stabilizátory:** hodnoty se násobí lineární funkcí účinku c0, která je pro c0 = 1 rovna jedné. Pružiny a stabilizátory zvyšují tuhost (0x11C), zmenšují náklon (0x12C) a zvyšují přilnavost (0x0F4); tlumiče zrychlí útlum (0x114/0x118) a zvýší přilnavost. Pružiny nastaví i 0x120 z c4.
- **Aerodynamika:** přítlak vpředu a vzadu se násobí 1 + c0, resp. c4 × malá konstanta.
- **Pneumatiky:** c0 (vpředu) a c4 (vzadu) se vztáhnou k aktuální přilnavosti 0x0F4 (počítají se poslední z ostatních dílů v pořadí slotů). Jejich průměr zvýší 0x0F4, poměr přední k zadní posune 0x0F0. Typ pneumatik (0xC8) se zapíše do 0x1C0.
- **Výjimky podle rodiny auta** (jméno `.ais`, v `nfs5.car` na 0x115): 959, 928, GT2 a GT3 díly ve fyzice ignorují; GT1, GT2, GT3 a 935 mají sériově závodní pneumatiky (typ 2).

### Typ pneumatik a povrch

Přilnavost kola se násobí faktorem z tabulky [povrch × typ pneumatik], zvlášť pro sucho (0x5D0D50) a déšť (0x5D0E4C), 21 povrchů. Na suchém asfaltu (povrch 1) mají slicky víc a pneumatiky do deště méně než sériové, v dešti si sériové a do deště pneumatiky vymění hodnoty. Na štěrku a trávě slicky ztrácí nejvíc. Hra zatím zná jen suchý asfalt: `parts.json` → `tyre_grip` je řádek povrchu 1 a `car.gd` násobí přilnavost poměrem faktoru zvoleného a sériového typu (u aut se sériovými slicky se tak nic nemění).

## Seznamy dílů aut

Seznam nabízených dílů (`nfs5.car` 0x32E) obsahuje i díly z pozdějších let (např. 356 1100 může dostat motor 1500 S z roku 1953). V kariéře originál nabízí díl až od roku v 0x46. Hra rok neomezuje (D-024).

## Stock / Sport ve hře (D-024)

- **Stock** = `.sim` beze změny.
- **Sport** = z každé skupiny (kategorie + jméno, bez pneumatik a vzhledu) jeden díl ze seznamu auta: motorové díly a výměna motoru podle největšího výkonu, brzdy, pružiny, tlumiče a stabilizátory podle největšího účinku c0, aerodynamika podle součtu c0 + c4, karoserie podle největší úspory hmotnosti, převodovka s nejvíce stupni, jejíž nejvyšší stupeň ještě dosáhne maximální rychlosti auta (při shodě kratší řazení a kratší převody), Shifter vždy.
- **Pneumatiky** se volí zvlášť: sériové, slick nebo do deště, pokud je seznam auta má.

Sady jednotlivých aut se do repozitáře neukládají. Z vlastní kopie hry je vypíše `python3 tools/parts.py sources/FEData decomposed/FEData/Data/parts.json --report`.
