---
type: inventory
updated: 2026-10-15
machine_readable: ../data/inventory.yaml
---

# Inventura dat originální hry

Strojově čitelná verze: [data/inventory.yaml](../data/inventory.yaml).

Nejcennější data jsou čitelná hned: fyzika 86 verzí aut a nastavení AI soupeřů v CSV s komentáři designérů. Modely a tratě jsou v kontejneru `.crp`. Jeho kompresi už umíme rozbalit, geometrie ale zbývá dopsat.

| Kategorie | Data | Kde a kolik | Stav | Použití |
| --- | --- | --- | --- | --- |
| hned | Fyzika aut | `Simulation/CarData/*.sim`, 86 | částečně dekódováno ([sim.md](formats/sim.md)), převedeno do `decomposed/GameData/Simulation/cars.json` | Reference pro jízdní model |
| hned | AI soupeřů | `Simulation/AI/*.csv`, 7 | čitelné | Logika a výchozí čísla |
| hned | Textové konfigurace | `.tpg`, `.clr`, `.map`, `.scn`, `animdefs.txt` | čitelné | Atmosféra, objekty |
| rozbalit | Kontejner `.crp` | 44 aut, 15 tratí, 8 menu | komprese hotová ([crp.md](formats/crp.md)) | Krok k geometrii |
| hotovo | Textury `.fsh` | 553 souborů, 10 425 obrázků | převedeno do PNG ([fsh.md](formats/fsh.md)) | Reference vzhledu |
| rozbalit | Zvuky `.viv`/`.bnk` | 42 archivů | známý formát | Jen reference |
| rozbalit | Hudba, videa | 28 skladeb, 12 videí | známý formát | Nepoužije se |
| dopsat | Geometrie aut | `.crp` | neznámé | glTF reference |
| dopsat | Geometrie tratí | `.crp` | neznámé | Nízká priorita |
| dopsat | `.key`, `.edg`, `.jnc`, `.lsp`, `.rho`, `.cop`, `.ais`, `.spl` | trati, AI, zvuk | neznámé | Vzory pro AI a zvuk |
