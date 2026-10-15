---
type: plan
updated: 2026-10-15
current_phase: 1
phases:
  - id: 1
    name: "Data z originálu"
    status: in_progress
    gate: "Fyzika všech aut v JSON, textury v PNG, jedno auto v glTF jako vizuální reference"
  - id: 2
    name: "Prototyp jízdy"
    status: todo
    gate: "Fiktivní auto na testovací trati, jízdní pocit srovnatelný s originálem spuštěným přes Wine"
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
- [ ] Spustit originál na Macu přes Wine jako referenci

## Fáze 2 – Prototyp jízdy

- [ ] Godot 4.6 projekt, Jolt
- [ ] Fiktivní vzorové auto (jednoduchý model)
- [ ] Raycast podvozek, model pneumatik, motor a převodovka z dat JSON
- [ ] Kolize a zóny poškození, deformace meshe
- [ ] Testovací trať (skidpad, slalom)
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
