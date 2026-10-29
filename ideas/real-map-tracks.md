---
type: idea
id: IDEA-001
title: "Tratě podle reálných map (Alpy, Normandie)"
status: idea            # idea | accepted | rejected | done
created: 2026-10-15
related: [D-005, "docs/plan.md#fáze-6--případné-veřejné-vydání"]
tags: [tracks, terrain, procedural, openstreetmap, dem]
---

# Tratě podle reálných map

Tratě by se generovaly z otevřených geografických dat (průběh silnice + výškový model terénu) a pak se ručně dolaďovaly kvůli hratelnosti. Výsledek je „inspirovaný místem“, ne jeho přesná kopie. Je to vlastní obsah v souladu s D-005 (tratě ve stylu originálu, užší silnice).

## Datové zdroje

| Vrstva | Zdroj | Rozlišení | Licence / poznámka |
| --- | --- | --- | --- |
| Průběh silnice | OpenStreetMap | vektor | ODbL, nutné uvést zdroj. Osa, typ, šířka, mosty, tunely |
| Terén (celá Evropa) | Copernicus DEM GLO-30 | 30 m | Otevřená data. Pro okolní krajinu |
| Terén Francie | IGN RGE ALTI | 1 m | Otevřená licence (Etalab), uvést zdroj |
| Terén Švýcarsko | swisstopo swissALTI3D | 0,5 m | Otevřená data, uvést zdroj |
| Letecké snímky | IGN BD ORTHO, swisstopo SWISSIMAGE | do 0,1–0,5 m | Předloha pro textury a rozmístění objektů |
| Využití území | OpenStreetMap | vektor | Les, pole, zástavba, voda → rozmístění vegetace a budov |

**Nepoužívat:** fotorealistické 3D dlaždice Google Maps. Licence zakazuje ukládání a extrakci.

Před použitím ověřit aktuální licenční podmínky každého zdroje.

## Pipeline

1. Výběr úseku silnice na mapě (ideálně 5–15 km s výrazným charakterem).
2. Skript stáhne osu silnice z OSM a výškový model pro okolí (buffer kolem trasy).
3. Procedurální generování silnice podél křivky: nastavitelná šířka, krajnice, svodidla, náklon v zatáčkách.
4. Terén z výškového modelu, zarovnaný a vyhlazený podél silnice (výškový model s rozlišením 30 m je pro samotnou silnici příliš hrubý).
5. Rozmístění vegetace a budov podle využití území. Budovy jako obecné modely v regionálním stylu.
6. Ruční doladění v Blenderu nebo Godotu: zkrácení, úpravy zatáček, dominanty, světlo.
7. Export do glTF → Godot.

## Nástroje

- **BlenderGIS:** doplněk pro Blender, import výškového modelu a OSM.
- **Vlastní Python skript v `tools/`:** OSM + výškový model → křivka silnice + mesh terénu → glTF.
- **Terrain3D:** doplněk pro Godot na velké terény.

## Kandidátní regiony

| Region | Charakter | Hodí se pro |
| --- | --- | --- |
| Alpy | Serpentiny průsmyků, tunely, galerie, velké převýšení | Technické tratě, auta 50.–60. let |
| Normandie | Úzké silnice mezi živými ploty (bocage), pobřežní útesy, vesnice, sady | Rychlé plynulé zatáčky, atmosféra blízká originálu |

## Rizika

- Reálné silnice nejsou automaticky zábavné: dlouhé nudné úseky, nepravidelné poloměry zatáček. Nutná úprava kvůli hratelnosti.
- Hrubý výškový model vyžaduje vyhlazování podél silnice.
- Nutnost uvádět zdroje dat v titulcích hry.

## Další kroky (pokud se nápad přijme)

- [ ] Vybrat 2–3 konkrétní úseky silnic v Alpách a Normandii
- [ ] Prototyp skriptu OSM + výškový model → glTF na jednom úseku
- [ ] Zapsat jako rozhodnutí do `docs/decisions.md` a upravit fázi 3 v `docs/plan.md`
