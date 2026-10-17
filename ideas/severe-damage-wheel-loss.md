---
type: idea
id: IDEA-006
title: "Vážné následky poškození: utržení kola a další"
status: accepted        # idea | accepted | rejected | done
created: 2026-10-17
related: [D-010, "docs/plan.md#fáze-2--prototyp-jízdy", "game/scripts/car_damage.gd"]
tags: [damage, physics, gameplay]
---

# Vážné následky poškození

První verze poškození (fáze 2) má mírné následky: sbíhavost a přilnavost kola na poškozeném rohu, ztrátu výkonu motoru, větší odpor vzduchu a menší rejstřík řízení. Uživatel chce následky realističtější než v originále a postupně je zesilovat.

## Hotovo (17. 10. 2026, `car_damage.gd`, `car.gd`)

- **Odpadající díly původního modelu**: světla, blinkry, zadní světla, zástěry, výfuk a značka odpadnou při 100 % své zóny, dveře při 100 % boku.
- **Díly na pantech**: kapota a kryt motoru se uvolní nad 50 % předku / zádi a utrhnou při nárazu z 100 km/h, dveře se uvolní nad 50 % předku nebo zádi nebo po tvrdém nárazu a v zatáčkách se otevírají a zavírají.
- **Kola**: házení od 50 % poškození rohu, upadnutí při 100 % rohu i příslušného boku.

## Návrhy

- **Nárazníky a blatníky**: v modelech originálu jsou součástí meshe karoserie a pod nimi nic není. Pro vlastní auta (D-004) modelovat od začátku jako oddělené díly s kotevními body, vnitřními plochami a mezí utržení.
- **Aerodynamika volných dílů**: uvolněná kapota by se při rychlosti zvedla proudem vzduchu, otevřené dveře by vzduch přivíral.
- **Ohnutá náprava**: kromě sbíhavosti i odklon a vibrace řízení podle rychlosti.
- **Motor**: prasklé chlazení (u 356 vzduchem, tedy spíš poškozené dmychadlo) → přehřívání, pokles výkonu v čase, nakonec zhasnutí.
- **Převodovka**: po nárazu zezadu (motor vzadu) zaseknutý nebo vypadávající převod.
- **Brzdy**: poškozený roh brzdí nerovnoměrně (auto při brzdění táhne do strany).
- **Sklo**: prasklé čelní sklo (textura) jako vizuální signál vážného nárazu.

## Otevřené otázky

- Jak silné jsou následky v originále (srovnání přes Wine) a o kolik je chceme zesílit.
- Má jít poškození vypnout (jako v originále volba poškození)?
- Oprava: jen mezi závody, nebo i jako služba na trati (mise testovacího jezdce)?
