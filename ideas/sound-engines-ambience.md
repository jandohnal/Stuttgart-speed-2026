---
type: idea
id: IDEA-004
title: "Zvuky motorů a prostředí: zdroje a implementace"
status: idea            # idea | accepted | rejected | done
created: 2026-10-16
related: [D-007, D-008, IDEA-001]
tags: [audio, engine-sound, ambience, sfx, licensing, godot]
---

# Zvuky motorů a prostředí

Rozšiřuje D-007 (zvuky motorů ze samplů). Zvuky se poskládají z existujících knihoven (část zdarma), vlastních nahrávek a případně procedurální syntézy. Zvuky z originální hry slouží jen jako lokální reference v `decomposed/` (D-008).

## 1. Zvuky motorů

Pro hru jsou potřeba **smyčky při konstantních otáčkách**, zvlášť pod plynem a bez plynu, ideálně po 500–1000 ot/min. Běžné nahrávky průjezdů se nehodí.

| Zdroj | Typ | Licence / cena | Poznámka |
| --- | --- | --- | --- |
| [BOOM Library – Cars V8](https://www.adorama.com/boom-library-cars-v8-sound-effects-library-download/p/bby1130676), [Everyday Cars](https://bigbearsound.com/products/boom-library-boom-everyday-cars) | Profesionální knihovny pro hry | Placené, royalty-free | Ověřit, že obsahují smyčky po otáčkách |
| [Magic Sound Effects – Car Engines](https://www.artstation.com/marketplace/p/Ap8g3/car-engines-sound-pack-vol-2) | Menší balíčky | Placené, levnější | |
| [Sonniss GDC Game Audio Bundle](https://rekkerd.org/sonniss-releases-gdc-2026-game-audio-bundle/) | Roční výběr profesionálních knihoven (2026: ~7,5 GB), i starší ročníky | Zdarma, royalty-free, bez uvedení autora | Motorové smyčky nejsou zaručené |
| [engine-sim](https://github.com/GDCorner/engine-sim) | Procedurální simulace spalovacího motoru | Open source, licenci ověřit | Jen Windows. Použití: nahrát vlastní smyčky pro konkrétní konfiguraci (plochý 4/6válec, vzduchem chlazený) |
| Vlastní nahrávky | Ruční rekordér, mikrofon u výfuku a v motorovém prostoru | Vlastní | Ideálně na válcové zkušebně. Tip: VW Brouk (vzduchem chlazený plochý 4válec) zní podobně jako auta 50. let, snadno k nahrání na srazech veteránů |

Knihovny obsahují hlavně moderní auta. Pro historické motory budou vlastní nahrávky nebo engine-sim nejspíš nutné.

### Další zvuky aut
Pískání pneumatik, povrchy (štěrk, tráva, mokro), vítr podle rychlosti, řazení, prskání výfuku, nárazy (plech, sklo, svodidla), odpadávající díly.

## 2. Zvuky prostředí

| Zdroj | Licence | Poznámka |
| --- | --- | --- |
| [Freesound](https://freesound.org) | Podle zvuku: CC0 (bez podmínek), CC-BY (uvést autora), CC-BY-NC (**ne** komerčně) | Obrovské množství terénních nahrávek: moře, vítr v listí, ptáci, řeky |
| Sonniss GDC bundly | Royalty-free, bez uvedení autora | Kvalitní profesionální ambienty |
| [BBC Sound Effects](https://www.diyphotography.net/the-bbc-sound-effects-archive-is-now-free-to-download-with-over-33000-files/) | Podle dostupných znalostí jen osobní, vzdělávací a výzkumné použití (ověřit) | 33 000+ nahrávek, výborná příroda. Pro soukromý prototyp ano, pro vydání ne |
| Vlastní terénní nahrávky | Vlastní | Nejčistší právně, jedinečná atmosféra (Alpy, pobřeží) |

Potřebné kategorie: les, louka, pobřeží a moře, řeka, vodopád, vesnice, vítr, ptáci (ráno a večer), cvrčci (noc), déšť, vzdálená doprava, zvony, zvířata.

## 3. Implementace v Godotu

- **Motor:** prolínání smyček podle otáček a zátěže, ladění výšky (crossfade/granulární syntéza). Vlastní přehrávač nebo `AudioStreamGenerator`.
- **Zóny prostředí:** `Area3D` se smyčkou na pozadí, plynulé prolínání mezi zónami.
- **Bodové zdroje:** řeka, vodopád, moře jako `AudioStreamPlayer3D`. U tratí podle reálných map (IDEA-001) automatické rozmístění podle vodních ploch a využití území z OpenStreetMap.
- **Náhodné jednorázové zvuky:** ptáci, větve, pes v náhodných intervalech a pozicích, aby se prostředí neopakovalo.
- **Akustika:** dozvuk v tunelech a pod mosty (audio sběrnice s reverbem, přepnutí v `Area3D`), Dopplerův jev, hluk větru podle rychlosti.
- **Denní doba a počasí:** různé sady zvuků ráno, večer a v noci, déšť.

## Licenční pravidla

- Ke každému zvuku evidovat zdroj a licenci (např. `assets/audio/LICENSES.md` nebo CSV).
- CC-BY-NC a BBC jen do soukromých verzí, ne do vydání.
- Zvuky z originální hry jen v `decomposed/`, nikdy necommitovat.

## Další kroky (pokud se nápad přijme)

- [ ] Stáhnout Sonniss GDC bundly a projít vozidla a ambienty
- [ ] Prototyp přehrávače motoru se smyčkami podle otáček v Godotu
- [ ] Vybrat zdroj smyček pro první typ motoru (knihovna, engine-sim, vlastní nahrávka)
- [ ] Šablona evidence licencí zvuků
- [ ] Zapsat jako rozhodnutí do `docs/decisions.md`
