---
type: idea
id: IDEA-011
title: "Distribuce hry: instalační balíček + vlastní data originálu (model OpenNFS)"
status: idea            # idea | accepted | rejected | done
created: 2026-10-18
related: [D-001, D-002, D-008, D-009, D-012, "docs/legal.md"]
tags: [distribution, packaging, export, import-wizard, macos, signing, legal]
---

# Distribuce: balíček hry + vlastní data originálu

Hra se šíří **bez jakýchkoli dat originálu**. Hráč si při prvním spuštění vybere svou instalaci NFS: Porsche 2000 / Porsche Unleashed, hra data převede a uloží do svého datového adresáře. Stejný model používá [OpenNFS](https://github.com/OpenNFS/OpenNFS): „OpenNFS does not bundle any EA intellectual property. A copy of the original games must be provided.“

## 1. Co obsahuje balíček

| Součást | V balíčku | Poznámka |
| --- | --- | --- |
| Engine (export Godotu), kód hry, shadery | ano | |
| Importér dat originálu (převodníky) | ano | Přepsané z Pythonu do hry, viz kap. 3 |
| Vlastní obsah (zvuky, UI, fiktivní auta, vlastní tratě) | ano | Až vznikne (D-004, D-005, D-007) |
| Modely, textury, tratě, zvuky originálu | **ne** | Vznikají až u hráče z jeho kopie |
| Názvy a loga Porsche v UI | **ne** napevno | Názvy aut číst z dat hráče (`.sim`), ne z kódu (D-001) |

## 2. První spuštění: průvodce importem

1. Obrazovka „Vyber složku s nainstalovanou hrou“ (nativní dialog Godotu `FileDialog` / `DisplayServer.file_dialog_show`). Volitelně i připojený obraz CD/ISO.
2. **Ověření:** kontrola známých souborů a jejich kontrolních součtů (tabulka v kódu). Rozpoznání verze: Porsche 2000 / Unleashed, jazyková verze, patch (3.5, mod verze). Neznámá verze → pokus o import s upozorněním.
3. **Převod** s ukazatelem průběhu: auta (CRP → glTF + damage.json), textury (FSH → PNG), tratě, fyzika (`.sim` → JSON), AI, zvuky (BNK → WAV / OGG).
4. Uložení do datového adresáře hry (`user://`; na macOS `~/Library/Application Support/<hra>/`), ne do balíčku aplikace (podepsaná `.app` je jen pro čtení).
5. Záznam o importu (verze, datum, kontrolní součty) → při dalším spuštění se import přeskočí. Tlačítko „Znovu importovat“ v nastavení.
6. Hra pak načítá data stejně jako teď z `decomposed/` (cesta `data_root` se přepne na `user://imported/`).

## 3. Převodníky: z Pythonu do hry

Současné nástroje v `tools/` jsou v Pythonu. Hráč Python mít nebude.

| Varianta | Výhody | Nevýhody |
| --- | --- | --- |
| **A. Port do GDScriptu** | Jeden jazyk, běží všude, kde běží hra | Dekomprese RefPack a parsování velkých tratí může být pomalé (jednorázově, s ukazatelem průběhu přijatelné) |
| **B. Port do C# (.NET)** | Výrazně rychlejší než GDScript | Export s .NET je větší, nutná podpora .NET v exportu pro macOS |
| **C. GDExtension v C++** | Nejrychlejší, možné převzít části LibOpenNFS (MIT) | Kompilace pro každou platformu, složitější sestavení |
| **D. Přibalit Python (PyInstaller) jako pomocný program** | Žádný přepis | Spouštění externích programů, podepisování dalších binárek, větší balíček |

**Doporučení:** A pro začátek (jednodušší, vše v projektu), kritické části (RefPack) případně později do C++. Python nástroje v `tools/` zůstanou jako vývojářská verze a referenční implementace; testy porovnají výstupy obou verzí.

Alternativa jako OpenNFS: číst formáty originálu přímo za běhu bez převodu. Současná architektura (glTF/JSON) ale počítá s převodem, jednorázový import je jednodušší.

## 4. Export a balení podle platformy

| Platforma | Výstup | Poznámky |
| --- | --- | --- |
| **macOS** | `.app` v `.dmg` (nebo `.zip`), universal / arm64 | Podpis a notarizace Apple vyžadují placený Apple Developer účet. Bez něj: ad-hoc podpis, Gatekeeper hráče varuje (otevření přes pravé tlačítko → Otevřít nebo `xattr -d com.apple.quarantine`). Pro okruh přátel stačí |
| **Windows** | `.exe` + `.pck` (nebo vložený pck), `.zip` | Bez podpisu SmartScreen varuje |
| **Linux** | binárka + `.pck`, případně AppImage / Flatpak | |

- Export přes šablony Godotu 4.7 (`godot --headless --export-release "<preset>" <výstup>`).
- **CI:** GitHub Actions sestaví všechny platformy při vytvoření tagu a nahraje do GitHub Releases.
- `export_presets.cfg` je teď v `.gitignore`; pro CI ho bude potřeba verzovat (bez tajných údajů pro podpis).

## 5. Právní a praktické náležitosti

- Repozitář je teď privátní. Pro veřejné vydání: samostatný veřejný repozitář nebo veřejná větev jen s kódem a vlastním obsahem (D-008 zůstává: data originálu nikdy).
- Licence vlastního kódu (např. MIT nebo GPL), soubor `LICENSE`.
- Prohlášení jako u OpenNFS: projekt není spojen s EA ani s Porsche AG; vyžaduje legálně vlastněnou kopii hry. **Neodkazovat** na stránky se stažením originálu.
- Názvy a zobrazení aut pocházejí z dat hráče; ve vlastním obsahu a propagaci (screenshoty, trailer) bez značek Porsche (D-001, `docs/legal.md`).
- Kredity: OpenNFS / LibOpenNFS a komunita za rozluštění formátů, OpenStreetMap a další zdroje podle použití.

## 6. Kvalita

- Automatický test importu na referenční instalaci (lokálně, mimo CI kvůli datům).
- Srozumitelné chyby: „chybí soubor X“, „nepodporovaná verze“, „nedostatek místa“.
- Velikost importovaných dat (odhad stovky MB) a doba importu zobrazit předem.

## Další kroky (pokud se nápad přijme)

- [ ] Tabulka známých souborů a kontrolních součtů pro verzi v `sources/`
- [ ] Port RefPack + `.sim` do GDScriptu jako první test rychlosti, porovnání s Pythonem
- [ ] Průvodce importem (výběr složky, ověření, průběh)
- [ ] Přepínání `data_root` na `user://imported/`
- [ ] Export preset pro macOS + první testovací `.dmg`
- [ ] CI pro sestavení a GitHub Releases
- [ ] Zapsat jako rozhodnutí do `docs/decisions.md`
