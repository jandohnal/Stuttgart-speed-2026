---
type: decisions
updated: 2026-10-15
format: "Každé rozhodnutí má ID, stav (accepted | proposed | superseded), kontext a důsledky."
---

# Rozhodnutí

## D-001 Duchovní nástupce, ne kopie
- **Stav:** accepted
- **Rozhodnutí:** Hra bude mít vlastní název (Stuttgart Speed). Zachovává hratelnost a atmosféru originálu, nekopíruje jeho obsah.
- **Důsledky:** Nepoužívají se loga, názvy ani tvary vozů Porsche. Mechaniky (kariéra napříč érami, mise testovacího jezdce) se přebírají jako nápad.

## D-002 Engine Godot 4.7
- **Stav:** proposed (potvrdit po prototypu jízdy, fáze 2)
- **Rozhodnutí:** Godot 4.7 (původně 4.6, 15. 10. 2026 přechod na tehdy aktuální 4.7.2), fyzika Jolt, renderer Forward+ přes Metal.
- **Důvod:** zdarma (MIT), nativní na Apple Silicon, nejrychlejší vývoj pro jednoho autora.
- **Alternativa:** Unity 6. Unreal 5 zamítnut kvůli náročnosti a slabší podpoře Macu.

## D-003 Vlastní jízdní model
- **Stav:** accepted
- **Rozhodnutí:** Raycast kola nad tuhým tělesem v Jolt, ne `VehicleBody3D`.
- **Důvod:** Charakter jednotlivých aut a „sim-cade“ pocit jde vyladit jen s plnou kontrolou nad modelem pneumatik a přenosem hmotnosti.

## D-004 Fiktivní auta
- **Stav:** accepted
- **Rozhodnutí:** Cílová auta hry jsou fiktivní designy inspirované érami (zadní motor 50. let, klínové tvary 70. let...).
- **Důsledky:** Fyzikální parametry originálu slouží jako reference pro realistické hodnoty dané éry. Výjimka pro první krok: viz D-009.

## D-005 Vlastní tratě ve stylu originálu
- **Stav:** accepted
- **Rozhodnutí:** Tratě se nekopírují. Zachovává se styl: evropská krajina, světlo, otevřené silnice, alternativní cesty. Silnice budou užší než v originálu.
- **Důsledky:** Cílové tratě jsou vlastní. Výjimka pro první krok: viz D-009, kvůli které je exportér alespoň jedné původní trati potřeba.

## D-006 Bez hudby
- **Stav:** accepted
- **Rozhodnutí:** Hra nebude mít hudbu z originálu ani licencovanou hudbu.

## D-007 Zvuky ze samplů
- **Stav:** accepted
- **Rozhodnutí:** Zvuky motorů se skládají z nasamplovaných smyček podle otáček a zátěže (granulární/crossfade syntéza). Zdroje: vlastní nahrávky nebo knihovny s licencí CC0/CC-BY.
- **Důsledky:** Několik typů motorů (např. plochý 4válec, plochý 6válec, turbo) sdílí více aut s jiným doladěním.

## D-008 Data originálu jen lokálně
- **Stav:** accepted
- **Rozhodnutí:** Repozitář je privátní. Veškeré assety z originální hry (a licencované modely) leží v `sources/`, vše rozbalené a převedené v `decomposed/`. Obě složky jsou v `.gitignore` a existují jen lokálně.
- **Důsledky:** Do gitu jde jen kód, nástroje, dokumentace a vlastní obsah. Nástroje čtou ze `sources/` a zapisují do `decomposed/` se stejnou strukturou podsložek.

## D-009 První krok s původním autem na původní trati
- **Stav:** accepted
- **Rozhodnutí:** Prototyp (fáze 2) se staví s jedním původním autem a na jedné původní trati z originální hry, převedenými do glTF ze `sources/` do `decomposed/`.
- **Cíl:** Ověřit, že migrovaná hra funguje a je hratelná. Teprve po splnění tohoto cíle se začne s vlastními tratěmi a vlastními auty.
- **Důvod:** Přímé srovnání s originálem. Stejné auto se stejnými parametry `.sim` na stejné trati umožní objektivně ladit jízdní model, kolize a poškození proti originálu spuštěnému přes Wine. Odpadá také tvorba vlastních assetů před ověřením hratelnosti.
- **Důsledky:**
  - Assety zůstávají jen lokálně v `decomposed/` (D-008). Godot projekt je načítá odtud a nic z nich necommituje.
  - Exportér auta (CRP → glTF) a exportér vybrané trati mají vysokou prioritu.
  - Fiktivní auta (D-004) a vlastní tratě (D-005) zůstávají cílem, ale práce na nich začne až po splnění milníku fáze 2 (hratelný prototyp s původním obsahem).
  - Volba konkrétního auta a trati: viz otevřená otázka v `docs/plan.md`.
