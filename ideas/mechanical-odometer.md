---
type: idea
id: IDEA-005
title: "Mechanické válečkové počitadlo kilometrů na tachometru"
status: accepted        # idea | accepted | rejected | done
created: 2026-10-17
related: [IDEA-004]
tags: [dashboard, hud, odometer, cockpit, atmosphere, shader]
---

# Mechanické válečkové počitadlo kilometrů

Ujeté kilometry se na tachometru nezobrazují digitálně, ale na klasickém mechanickém počítadle s otočnými válečky číslic. Válečky se pomalu a plynule otáčejí podle ujeté vzdálenosti, stejně jako ve skutečných autech dané éry.

## Chování (jako skutečný mechanismus)

- **Nejnižší váleček** (stovky metrů, u některých aut odlišený barvou) se otáčí **plynule** úměrně ujeté vzdálenosti. Číslice jsou vidět i v mezipoloze.
- **Vyšší válečky** stojí a pootočí se **jen při přechodu** nižšího válečku z 9 na 0 (přenos jako v mechanickém převodu). Přechod probíhá během poslední desetiny otáčky nižšího válečku, takže při přetočení 0999 → 1000 se otáčí několik válečků současně.
- **Drobné nepřesnosti:** válečky mírně nesedí přesně v řadě (zlomky milimetru), což přidává mechanický charakter. Volitelně jemné chvění při vysokých otáčkách motoru.
- **Denní počitadlo (trip):** druhé, kratší počitadlo s nulovacím tlačítkem. Nulování otočí válečky zpět na nulu (animace).

## Zdroj vzdálenosti

- Vzdálenost se počítá z **otáčení kol (pohon od převodovky)**, ne z pozice auta. Při protáčení kol na místě tedy počitadlo přičítá, při smyku s blokovanými koly ne, stejně jako u skutečného mechanického pohonu.
- Akumulace ve dvojité přesnosti (double), aby nevznikla chyba při velkých hodnotách.
- Jednotky podle auta a trhu: km nebo míle.

## Napojení na hru

- **Kariéra (Evolution):** každé auto má vlastní celkový nájezd uložený v uložené hře. Ojetá auta při nákupu ukazují svůj nájezd a cena může záviset na něm.
- **Mise:** např. „doruč auto s nájezdem pod X km“ nebo mise s denním počitadlem.
- **Kokpitový pohled:** počitadlo je vidět přímo v přístrojové desce. V HUDu z pohledu za autem jen jako volitelný detail.

## Vzhled podle éry

| Éra | Styl |
| --- | --- |
| 50.–60. léta | Bílé číslice na černých válečcích, patkové písmo, chromový rámeček, poslední váleček bílý s černými číslicemi |
| 70.–80. léta | Bílé číslice, bezpatkové písmo, poslední váleček červený nebo s červeným podkladem |
| 90. léta | Užší okénko, menší číslice, případně přechod k digitálnímu displeji (u nejnovějších aut možnost volby) |

Referenci k přístrojovým deskám originálu lze najít v `decomposed/GameData/DashHud/` (jen lokálně, D-008).

## Implementace v Godotu

- **Varianta A (shader):** jedna textura se svislým pásem číslic 0–9 (+ opakovaná 0 pro plynulý přechod). Každý váleček je obdélník, shader posouvá UV podle úhlu válečku. Přidat zakřivení a ztmavení na horní a dolní hraně okénka, aby to působilo jako válec. Levné a ostré v libovolném rozlišení.
- **Varianta B (3D):** skutečné válce s texturou číslic v modelu přístrojové desky. Lepší hloubka a odlesky v kokpitu, víc práce.
- **Logika:** `distance` → hodnota nejnižšího válečku `v0 = (distance / unit) mod 10` plynule. Pro každý vyšší váleček `i`: celá část `floor(distance / 10^i) mod 10` + přechodová frakce, pokud je nižší váleček v posledních 10 % otáčky a všechny nižší válečky ukazují 9.
- Snadno testovatelné samostatně (scéna jen s počitadlem a posuvníkem vzdálenosti).

## Další kroky (pokud se nápad přijme)

- [x] Prototyp válečků a přenosové logiky v samostatné scéně (`game/tests/odometer_test.tscn`; kresleno v `_draw()` místo shaderu, viz D-013)
- [x] Napojení na otáčky kol z jízdního modelu
- [ ] Ukládání nájezdu per auto v kariéře (zatím `user://odometer.cfg` mimo kariéru, D-013)
- [x] Varianty vzhledu podle ér (éra z roku auta v `cars.json`), jemné chvění válečků nad 75 % redline
- [x] Zapsat jako rozhodnutí do `docs/decisions.md` (D-013)
