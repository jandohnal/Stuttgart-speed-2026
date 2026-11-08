---
type: idea
id: IDEA-014
title: "Force feedback pro volant"
status: idea        # idea | accepted | rejected | done
created: 2026-11-05
related: [D-012, D-038]
tags: [input, wheel, force-feedback, godot]
---

# Force feedback pro volant

Volant ve hře funguje bez silové odezvy (D-038), Godot 4.7 má jen vibrace (`Input.start_joy_vibration`).

## Možnosti

| Cesta | Co obnáší | Stav |
| --- | --- | --- |
| Podpora přímo v Godotu | [PR godotengine/godot#114642](https://github.com/godotengine/godot/pull/114642) zpřístupňuje haptiku SDL (konstantní síla, periodické a podmíněné efekty). Stačilo by počkat a přejít na novou verzi. | Rozpracovaný návrh (draft, milník 4.x), v 4.7 není. |
| Vlastní rozšíření GDExtension nad SDL | Překlad pro macOS, Windows i Linux, volant se otevírá mimo vstup Godotu. V souladu s D-012. | Výrazně větší práce, bez volantu nejde ověřit. |

## Co by bylo potřeba ve hře

Výpočet síly z fyziky `Car`: vratný moment z bočních sil předních pneumatik, slábnoucí za vrcholem skluzu, a nárazy a povrch z `CarDamage` a dat silnice.

## Rizika

Na macOS je force feedback nejméně spolehlivý. Účinky je potřeba ladit na skutečném volantu.
