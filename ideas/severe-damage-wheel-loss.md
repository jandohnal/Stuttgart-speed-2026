---
type: idea
id: IDEA-006
title: "Vážné následky poškození: utržení kola a další"
status: idea            # idea | accepted | rejected | done
created: 2026-10-17
related: ["docs/plan.md#fáze-2--prototyp-jízdy", "game/scripts/car_damage.gd"]
tags: [damage, physics, gameplay]
---

# Vážné následky poškození

První verze poškození (fáze 2) má mírné následky: sbíhavost a přilnavost kola na poškozeném rohu, ztrátu výkonu motoru, větší odpor vzduchu a menší rejstřík řízení. Uživatel chce následky realističtější než v originále a postupně je zesilovat.

## Návrhy

- **Utržení kola**: roh s poškozením 1,0 a další náraz nad mezí kolo odpojí. Paprsek kola se vypne, vizuál kola se převede na `RigidBody3D` (jako sražitelné objekty v `track_props.gd`) a auto si sedne na roh karoserie (kolize obalem karoserie už existuje).
- **Ohnutá náprava**: kromě sbíhavosti i odklon a vibrace řízení podle rychlosti.
- **Motor**: prasklé chlazení (u 356 vzduchem, tedy spíš poškozené dmychadlo) → přehřívání, pokles výkonu v čase, nakonec zhasnutí.
- **Převodovka**: po nárazu zezadu (motor vzadu) zaseknutý nebo vypadávající převod.
- **Brzdy**: poškozený roh brzdí nerovnoměrně (auto při brzdění táhne do strany).
- **Sklo**: prasklé čelní sklo (textura) jako vizuální signál vážného nárazu.

## Otevřené otázky

- Jak silné jsou následky v originále (srovnání přes Wine) a o kolik je chceme zesílit.
- Má jít poškození vypnout (jako v originále volba poškození)?
- Oprava: jen mezi závody, nebo i jako služba na trati (mise testovacího jezdce)?
