---
type: plan
updated: 2026-10-16
current_phase: 1
phases:
  - id: 1
    name: "Data z originálu"
    status: in_progress
    gate: "Fyzika všech aut v JSON, textury v PNG, jedno auto v glTF jako vizuální reference"
  - id: 2
    name: "Prototyp jízdy"
    status: todo
    gate: "Jedno původní auto na jedné původní trati (D-009), jízdní pocit, kolize a poškození srovnatelné s originálem spuštěným přes Wine"
  - id: 3
    name: "První vlastní trať"
    status: todo
    gate: "Jedna kompletní trať ve stylu originálu, hratelná od startu do cíle"
  - id: 4
    name: "Hra a atmosféra"
    status: todo
    gate: "Hratelná verze na Macu: rychlý závod, mise, kariéra, soupeři, provoz, policie"
  - id: 5
    name: "Obsah a vydání"
    status: todo
    gate: "Sada fiktivních aut a tratí, veřejné vydání"
---

# Plán

Nejdřív se ověřují rizika (data, jízdní pocit), teprve potom se staví obsah.

**Pořadí (D-009):** fáze 2 ověří na jednom původním autě a jedné původní trati, že migrovaná hra funguje a je hratelná. Vlastní tratě a vlastní auta (fáze 3 a 5) začínají až po splnění milníku fáze 2.

## Fáze 1 – Data z originálu

- [x] Inventura instalace ([data-inventory.md](data-inventory.md))
- [x] Dekompresor EA RefPack ([tools/refpack.py](../tools/refpack.py)), ověřený na autě i trati
- [x] Částečné dekódování `.sim` ([formats/sim.md](formats/sim.md))
- [x] Zkopírovat assety hry do `sources/`
- [x] Převod všech `.sim` do `decomposed/GameData/Simulation/cars.json`
- [ ] Určit zbývající pole `.sim` (porovnáním aut s odlišnými vlastnostmi)
  - [x] Porovnání dvojic a hypotézy ([formats/sim.md](formats/sim.md#porovnání-dvojic))
  - [ ] Ověřit hypotézy v originále přes Wine
- [x] Převod textur FSH → PNG ([tools/fsh2png.py](../tools/fsh2png.py))
- [x] Parser geometrie auta v CRP → glTF (podle OpenNFS), všech 44 aut ([tools/crp2gltf.py](../tools/crp2gltf.py))
- [x] Převod CSV nastavení AI do JSON ([tools/ai_csv2json.py](../tools/ai_csv2json.py))
- [x] Exportér tratí CRP → glTF + data silnice `SimD`, zatím skidpad ([tools/track2gltf.py](../tools/track2gltf.py))
- [x] Exportér tratí: farmland (Normandie), úseky `SimD` a start/cíl z `_fstart.scn`
- [x] Objekty kolem trati: umístění z matice `tr`, značka v `Base` 0x44, vlastnosti z `animdefs.txt`, díly typu 4 a bez indexů ([formats/scn.md](formats/scn.md))
- [ ] Exportér tratí: ostatních 13 tratí, význam šířek `SimD`, spojení úseků (`.jnc`), předlohy z úloh (`_stNN.scn`), animace objektů
- [ ] Spustit originál na Macu přes Wine jako referenci

## Fáze 2 – Prototyp jízdy

- [x] Godot 4.7 projekt, Jolt ([game/](../game/README.md)), běží na Metalu, automatický jízdní test
- [x] Vybrat původní auto a původní trať pro prototyp (D-009): 356 A coupe 1.6 na skidpadu
- [x] Import auta z `decomposed/` (glTF) a parametrů z `cars.json` (načítání za běhu)
- [x] Import vybrané trati z `decomposed/` (glTF + data silnice `SimD`), kolize z geometrie
- [x] Skutečná trať pro jízdní pocit: farmland (Normandie), start na startovní čáře originálu
- [x] Raycast podvozek, model pneumatik, motor a převodovka z dat JSON (pneumatiky: skluz, rotace kol, setrvačnost motoru; 0–100 km/h 15,8 s proti reálným ~16 s)
- [ ] Doladit pneumatiky a řízení proti originálu přes Wine (přilnavost 0x0F4 a setrvačnost 0x058 jsou hypotézy), asistent řízení pro klávesnici hotový (F3); ABS (F4) a zadní přilnavost 1,12 naladěné podle ruční jízdy proti originálu (smyk zádí při brzdění v zatáčce); klávesy s náběhem pedálů a volantu jako v tehdejších hrách
- [x] HUD: kulatý rychloměr (s počítadlem km) a otáčkoměr v klasickém stylu (kreslené procedurálně, stupnice z dat auta, ručička s tlumenou setrvačností); otáčky motoru při řazení klesají a stoupají plynule (spojka)
- [x] Kolize s objekty kolem trati: sražitelné značky (dynamická tělesa s původní hmotností), ostatní statické
- [x] Poškození auta: zóny `dz` a posuny `vt` 0x8000 jako blend shapes, náraz podle impulsu, následky (sbíhavost a přilnavost kol, výkon motoru, odpor vzduchu, rejstřík řízení)
- [x] Odpadající díly (kapota, víko motoru, dveře, světla, značka, výfuk, zástěry) a kola: házení od 50 % rohu, upadnutí při 100 % rohu i boku
- [ ] Naladit poškození a jeho následky proti originálu (Wine); textury poškození; další vážné následky ([IDEA-006](../ideas/severe-damage-wheel-loss.md))
- [ ] Srovnávací jízdy s originálem přes Wine: zrychlení, brzdná dráha, rychlost v zatáčkách
- [ ] Rozhodnout definitivně o enginu (D-002)

## Fáze 3 – První vlastní trať

- [ ] Návrh trati ve stylu originálu (užší silnice)
- [ ] Pipeline Blender → glTF → Godot, kolizní vrstvy
- [ ] Světlo, obloha, mlha

## Fáze 4 – Hra a atmosféra

- [ ] Rychlý závod, mise testovacího jezdce, kariéra
- [ ] AI soupeřů, provoz, policie
- [ ] Zvuky motorů ze samplů (D-007)

## Fáze 5 – Obsah a vydání

- [ ] Sada fiktivních aut podle ér
- [ ] Další tratě
- [ ] Veřejné vydání

## Rizika

| ID | Riziko | Pravděpodobnost | Dopad | Záložní plán |
| --- | --- | --- | --- | --- |
| R-1 | Jízdní pocit neodpovídá originálu | střední | vysoký | Porovnávat s originálem přes Wine, ladit podle `.sim` |
| R-2 | Rozsah přeroste možnosti jednoho člověka | vysoká | vysoký | Malý rozsah: pár aut, pár tratí, jeden režim |
| R-3 | Zbývající pole `.sim` nejdou určit | střední | nízký | Doplnit z reálných technických údajů |
| R-4 | Výroba vlastních tratí je pomalá | vysoká | střední | Procedurální silnice podél křivky, sdílené sady objektů |
