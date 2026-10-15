---
type: idea
id: IDEA-002
title: "LLM pro postavy a dialogy soupeřů"
status: idea            # idea | accepted | rejected | done
created: 2026-10-15
related: ["docs/analysis.md#6-umělá-inteligence-soupeřů", "docs/plan.md#fáze-4--hra-a-atmosféra"]
tags: [ai, opponents, llm, dialogue, personality]
---

# LLM pro postavy a dialogy soupeřů

LLM neřídí auto. Řízení obstarává klasická AI (ideální stopa + pravidla). LLM přidává vrstvu osobnosti: dialogy, reakce a nastavení strategie na vyšší úrovni.

## Proč LLM neřídí auto

- Řízení je smyčka 60 Hz a víc (plyn, brzda, volant). LLM odpovídá za stovky ms až sekundy, i lokálně.
- LLM pracuje s textem, ne se spojitými veličinami. Výsledek by byl pozdní a nepřesný.

## Architektura soupeřů

| Vrstva | Frekvence | Technologie | Úloha |
| --- | --- | --- | --- |
| Řízení | 60+ Hz | Klasická AI: sledování ideální stopy (pure pursuit), PID na rychlost | Plyn, brzda, volant |
| Taktika | 60 Hz | Pravidla + parametry osobnosti (podle CSV originálu: blokování, odstřižení, dohled, gumička) | Předjíždění, blokování, chyby |
| Strategie | jednou za několik sekund | LLM (volitelně) | Úprava parametrů taktiky: „agresivněji“, „šetři poškozené auto“, „blokuj hráče“ |
| Osobnost | mezi závody, v pauzách | LLM | Dialogy, provokace, reakce na výsledky |

Řízení a taktika zůstávají deterministické a laditelné. LLM jen mění jejich parametry nebo generuje text.

## Využití LLM

- **Postavy v kariéře a misích:** šéf testovacích jezdců, rival (obdoba postavy Billyho z originálu), mechanik.
- **Repliky před závodem a po něm:** podle výsledku, poškození auta a historie souboje s hráčem.
- **Týmové rádio / komentátor:** krátké reakce na události v závodě (předjetí, nehoda, poslední kolo).
- **Strategie soupeřů:** úprava parametrů osobnosti podle situace v závodě.

## Technologie

- Lokální malý model na Apple Silicon (např. přes llama.cpp). Bez závislosti na internetu a bez nákladů na API.
- Strukturovaný výstup (JSON) pro strategii, aby šly parametry spolehlivě načíst.
- Záložní předpřipravené repliky, pokud model není k dispozici nebo odpovídá pomalu.

## Alternativa: posilované učení pro řízení

- Neuronová síť naučená metodou pokus–omyl (příklad: Gran Turismo Sophy od Sony AI).
- Pro Godot existuje open-source plugin Godot RL Agents (trénink v Pythonu, export modelu do hry).
- Náročné: dlouhý trénink, obtížné ladění, rychlý soupeř nemusí být zábavný.
- Možné kombinace: klasická AI řídí, malá naučená síť dolaďuje jízdu na limitu (brzdné body).

## Rizika

- Velikost modelu a paměť vedle běžící hry.
- Nekonzistentní nebo nevhodné repliky, nutné omezit tón a délku.
- Latence: generovat jen tam, kde se na odpověď nečeká (menu, pauzy, mezi závody).

## Další kroky (pokud se nápad přijme)

- [ ] Nejdřív postavit klasickou AI soupeřů (nezávisle na tomto nápadu)
- [ ] Otestovat lokální model na Macu: rychlost a kvalita krátkých replik
- [ ] Navrhnout schéma JSON pro strategické parametry
- [ ] Zapsat jako rozhodnutí do `docs/decisions.md`
