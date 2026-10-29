---
type: inventory
updated: 2026-10-15
machine_readable: ../data/inventory.yaml
---

# Inventura dat originální hry

Strojově čitelná verze: [data/inventory.yaml](../data/inventory.yaml).

Nejcennější data jsou čitelná hned: fyzika 86 verzí aut a nastavení AI soupeřů v CSV s komentáři designérů. Modely a tratě jsou v kontejneru `.crp`. Kompresi i geometrii aut už umíme převést do glTF, tratě zbývají.

| Kategorie | Data | Kde a kolik | Stav | Použití |
| --- | --- | --- | --- | --- |
| hned | Fyzika aut | `Simulation/CarData/*.sim`, 86 | částečně dekódováno ([sim.md](formats/sim.md)), převedeno do `decomposed/GameData/Simulation/cars.json` | Reference pro jízdní model |
| hotovo | AI soupeřů | `Simulation/AI/*.csv`, 6 | převedeno do JSON, ověřeno proti `.bin` ([ai-csv.md](formats/ai-csv.md)) | Logika a výchozí čísla |
| hned | Textové konfigurace | `.tpg`, `.clr`, `.map`, `.scn`, `animdefs.txt` | čitelné | Atmosféra, objekty |
| rozbalit | Kontejner `.crp` | 44 aut, 15 tratí, 8 menu | komprese hotová ([crp.md](formats/crp.md)) | Krok k geometrii |
| hotovo | Textury `.fsh` | 553 souborů, 10 425 obrázků | převedeno do PNG ([fsh.md](formats/fsh.md)) | Reference vzhledu |
| rozbalit | Zvuky `.viv`/`.bnk` | 42 archivů | známý formát | Jen reference |
| rozbalit | Hudba, videa | 28 skladeb, 12 videí | známý formát | Nepoužije se |
| hotovo | Geometrie aut | `.crp`, 44 | převedeno do glTF ([crp.md](formats/crp.md)) | Vizuální reference |
| částečně | Geometrie tratí | `.crp`, 15 | skidpad převeden do glTF + data silnice ([crp.md](formats/crp.md)) | Reference stylu, předloha silnice |
| dopsat | `.edg`, `.jnc`, `.rho`, `.cop`, `.spl` | trati, AI, zvuk | neznámé | Vzory pro AI a zvuk |
| částečně | Stopy a profily AI | `Track/racer/work/*.lsp` 30, `Track/*.key` 28, `AICarData/*.ais` 22, `AI/TRAFCFG.DAT` | převedeno do JSON, stopy ověřené, význam `.key` a tabulek `.ais` je hypotéza ([lsp.md](formats/lsp.md), [ais.md](formats/ais.md)) | Soupeři (D-026) |
