---
type: idea
id: IDEA-012
title: "Analýza Porsche.exe pomocí REA + Ghidra (význam dat originálu)"
status: accepted        # idea | accepted | rejected | done
decision: D-023
created: 2026-10-19
related: [D-001, D-008, D-009, D-012, "docs/formats/sim.md", "docs/formats/crp.md"]
tags: [reverse-engineering, ghidra, rea, mcp, sim, tracks, sound, tools]
---

# Analýza Porsche.exe: REA + Ghidra

[REA – Reverse Engineer Anything](https://github.com/morluto/rea) (licence MIT) je MCP server, který dá Claude Code přístup k disassembleru a dekompilátoru (Ghidra, Hopper, IDA). Nerozbaluje datové soubory hry sám, ale umožní zjistit, **jak je hra čte a co jednotlivá pole znamenají**.

## Proč

| Otázka | Stav teď | Co přinese analýza exe |
| --- | --- | --- |
| Neznámá pole `.sim` (0x054, 0x058, 0x098, 0x0F0–0x144) | Hypotézy z porovnání aut a z NFS4 (Velocity) | Přesný význam podle toho, jak je používá fyzika |
| Přiřazení zvukových sad motoru (`sd*.viv`) k autům | Vybíráno poslechem (`game/scripts/main.gd`) | Tabulka přímo z exe |
| Formáty tratí `.key`, `.edg`, `.jnc`, `SimD`, profily soupeřů `.ais` | Neznámé | Struktura z načítacího kódu |
| Princip jízdního modelu, poškození, ramp plynu a řízení | Vlastní odhad | Pochopení principu jako podklad pro vlastní implementaci |

## Nástroje a požadavky (D-012: jen zdarma)

| Součást | Licence / cena | Poznámka |
| --- | --- | --- |
| REA (`npx rea-agents setup`) | MIT, zdarma | Registruje MCP server pro Claude Code. Node.js ≥ 22 |
| **Ghidra** | Zdarma (Apache 2.0) | Podporuje 32bit Windows PE na macOS arm64. Vyžaduje JDK 21 |
| Hopper, IDA Pro | **Placené** | Nepoužívat (D-012) |

Vše běží lokálně v Claude Code na Macu (z cloudového prostředí to nejde: chybí Ghidra a síťový přístup).

## Ochrana a právní hranice

### Ověření (19. 10. 2026)

| Soubor | Sestaveno | `.text` entropie | Čitelné řetězce | Závěr |
| --- | --- | --- | --- | --- |
| `Porsche.exe` | 5. 6. 2000 (oficiální patch EA) | 6,65 | ~9 700, 318 názvů tříd C++ (RTTI) | **Nešifrovaný**, vhodný k analýze |
| `nfs5.exe` | 21. 6. 2019 (komunitní patch) | 6,65 | ~6 200 | Nešifrovaný, stejný kód jako `Porsche.exe` |
| `PORSCHE.ICD` | 13. 3. 2000 (původní vydání) | **7,92** | žádné relevantní | **Šifrovaný SafeDisc → nepoužívat, neobcházet** |

Analyzovat se bude jen `Porsche.exe` (oficiální patch EA bez šifrování), takže se žádná ochrana neobchází.

### Co prozradily řetězce (bez dekompilace)
- Cesty k datům: `%s%s.sim`, `%sdefault.sim`, `%s%s.viv`, `%s%s16.viv`, `%szzzx%s.viv`, `%s.crp` → načítací funkce půjdou najít podle odkazů na tyto řetězce.
- **Parametry nastavení auta:** `.FRONTDOWNFORCE`, `.REARDOWNFORCE`, `.SUSPENSIONSTIFFNESS`, `.SUSPENSIONTRAVEL`, `.STEERINGTOE`, `.BRAKEBIAS`, `.FRONTTIREPRESSURE`, `.REARTIREPRESSURE`, `STEERINGRANGE0/1`, `RaceTires`, `RainTires`, `GearShift`. Kandidáti pro neznámá pole `.sim` (např. dvojice 0x10C/0x110 a 0x114/0x118 mohou být přední/zadní hodnoty).
- **Poškození:** `.DAMAGEZONES`, `.PARTDAMAGE`, `BODYWORKDAMAGE`, `BRAKESDAMAGE`, `SUSPENSIONDAMAGE`, `TIRESDAMAGE`, `COSMETICDAMAGE` + ceny oprav.
- **AI:** třídy `AIHigh_Opponent`, `AIHigh_Cop`, `AIHigh_Traffic`, stavy `AIState_Racing`, `AIState_Chase`, `AIState_Offroad`, `AIDataRecord_LineSpeed_t` (rychlost podle ideální stopy).
- Názvy tříd C++ (RTTI) výrazně usnadní orientaci v Ghidře.

### Pravidla
- Cílem je interoperabilita (čtení vlastních dat ve vlastní hře): do projektu se zapisují **jen popisy formátů, významy polí a principy**, nikdy přepsaný ani dekompilovaný kód originálu (D-001).
- Výstupy Ghidry (projekt, exporty, pseudokód) jen do `decomposed/` (D-008).

## Limity

- Dekompilovaný C++ z roku 2000 bez symbolů je pracný; pseudokód je potřeba interpretovat.
- Náročné na čas a tokeny → cílené otázky („najdi parser `.sim`“), ne „rozeber celou hru“.

## Pilotní úkol (příkaz pro Claude Code)

```
Pilot: ověř, jestli REA (https://github.com/morluto/rea, MIT) s Ghidrou pomůže rozluštit data NFS5. Jen bezplatné nástroje (D-012): Ghidra, ne Hopper/IDA Pro.

1. Instalace: zkontroluj Node.js ≥ 22 a JDK 21, nainstaluj Ghidru a REA (npx rea-agents setup, jen pro Claude Code, změny mi před schválením ukaž). Vše mimo náš repozitář.
2. Cíl: Porsche.exe z instalace hry (/Volumes/gloin/NFS - Porsche Unleashed - CHECK _INSTALL FIRST/), zkopíruj do sources/ (gitignored). Ověřeno 19. 10.: nešifrovaný oficiální patch EA (viz IDEA-012). PORSCHE.ICD je šifrovaný SafeDisc – nepoužívat a neobcházet.
3. Úkol: najdi kód, který načítá .sim (řetězce „CarData“, „.sim“, cesty Simulation), a zjisti, jak hra používá offsety 0x054, 0x058, 0x098, 0x0F0–0x144. Výsledek s mírou jistoty a adresami funkcí zapiš do docs/formats/sim.md; porovnej s hypotézami z NFS4 (Velocity), pokud už jsou.
4. Bonus, pokud to jde snadno: tabulka přiřazení zvukových sad motorů k autům (sd*.viv) a kde se načítá.
5. Pravidla: zapisuj jen popis principů a významy polí, žádný přepsaný ani dekompilovaný kód do našeho projektu (D-001). Výstupy Ghidry (projekt, exporty) jen do decomposed/.
6. Na konci shrň: kolik času to zabralo, co šlo dobře, co ne, a jestli doporučuješ REA použít i pro tratě (.key, .edg, .jnc, SimD).
```

## Výsledek pilotu (19. 10. 2026)

**Výsledek:** význam téměř všech polí `.sim` je určený z kódu, který je používá. Podrobnosti s adresami funkcí jsou v [docs/formats/sim.md](../docs/formats/sim.md#analýza-porscheexe-ghidra).
- Potvrzeno: 0x054 zpoždění řazení, 0x0F0 podíl přilnavosti vpředu, 0x0F4 součinitel přilnavosti, 0x104 brzdné zpomalení (m/s²), 0x108 podíl brzd vpředu, 0x10C/0x110 přítlak vpředu/vzadu (×0,001), 0x128/0x12C naklopení a náklon karoserie.
- Opraveno proti hypotézám:
  - 0x058 je účinnost převodu, ne setrvačnost motoru;
  - 0x098 je brzdění motorem, ne nedotáčivost;
  - 0x0F8 je přenos zatížení;
  - 0x114/0x118 je tlumení karoserie;
  - 0x11C je tuhost zavěšení;
  - 0x13C–0x144 jsou parametry AI.
- Bonus (zvukové sady): načítání je ve funkci 0x4ACC10. Jméno sady přichází z globálního záznamu hráče (0x658374, krok 0x580), který plní menu. Tabulka přiřazení zatím nenalezena.

**Čas:** asi 45 minut.
- **Instalace (~20 min):**
  - Ghidra 12.1.4 a OpenJDK 21 přes Homebrew.
  - Node 24 z nodejs.org do `~/.local/opt`: REA nepodporuje Node 25 a `brew install node@24` padal na zámku openssl.
  - REA 6.7.0 pro Claude Code. Registraci v `~/.claude.json` bylo nutné ručně doplnit o cestu k Node 24, `JAVA_HOME` a `GHIDRA_INSTALL_DIR`.
- **Analýza (~25 min):**
  - Úvodní analýza exe trvala 74 s.
  - Úplná dekompilace všech 5841 funkcí headless Ghidrou trvala asi 3 minuty.

**Co šlo dobře:**
- Nástup přes řetězce `%s%s.sim` vedl přímo na načítací funkci.
- Převody jednotek při načtení (×0,01, ×0,001, mph → m/s) okamžitě odhalily význam a škálu poloviny polí.
- Kód pro díly a nastavení auta (podle řetězců „Gear Box“, „Turbo“) určil význam dalších polí.
- Shoda s modelem NFS4 (Velocity) je vysoká, takže principy lze porovnávat.

**Co nešlo:**
- REA přes CLI importuje exe při každém dotazu znovu (každé volání ~74 s, snímek neobsahuje projekt Ghidry). Pro hledání použití polí byl mnohem efektivnější jednorázový výpis všech funkcí vlastním skriptem pro headless Ghidru a hledání v něm.
- MCP server REA bude v Claude Code k dispozici až po restartu, v pilotu se nepoužil.
- Přesná jednotka u řízení (0x0FC) a tabulka zvukových sad zůstaly otevřené.

**Doporučení:** pro tratě (`.key`, `.edg`, `.jnc`, `SimD`) a profily soupeřů `.ais` ano. Postup:
1. Najít načítací funkci podle řetězců s příponou.
2. Udělat jednorázový výpis dekompilace do `decomposed/ghidra/`.
3. Cíleně hledat offsety struktur.

REA (MCP po restartu) je vhodné na cílené dotazy (xrefs, jedna funkce), ne na plošné hledání.

## Další kroky (přijato jako D-023)

- [x] Ověření nešifrovaného kódu (`Porsche.exe` čitelný, `PORSCHE.ICD` šifrovaný)
- [x] Pilot: parser `.sim` a význam polí (kandidáti z řetězců výše)
- [ ] Při úspěchu: zvukové sady, formáty tratí, profily soupeřů
- [x] Zapsat jako rozhodnutí do `docs/decisions.md` (nástroj + pravidla pro používání výsledků) → D-023
