---
type: idea
id: IDEA-013
title: "Statická rekompilace Porsche.exe (originál 1:1 v prohlížeči a nativně na macOS)"
status: idea            # idea | accepted | rejected | done
created: 2026-11-02
related: [D-001, D-008, D-009, D-012, D-023, IDEA-012]
tags: [recompilation, web, wasm, webgpu, reference, physics]
---

# Statická rekompilace Porsche.exe

Inspirace: [Underground 2 Revived](https://nfsu2.xyz/) ([th0mk/nfsu2-web](https://github.com/th0mk/nfsu2-web), MIT), fork [NFSU2Recomp](https://github.com/TalhaMudo/NFSU2Recomp) (MIT). Postup podle N64: Recompiled a XenonRecomp.

## Jak to dělá NFSU2 Web

1. Lifter v Pythonu (Capstone) převede předem každou funkci `SPEED2.EXE` z x86 do C. Nic se neemuluje.
2. C se zkompiluje do WebAssembly (wasi-sdk), nebo nativně pro macOS.
3. Runtime znovu implementuje to, co hra volá: Windows, Direct3D 9 nad WebGPU, DirectSound nad Web Audio (AudioWorklet), DirectInput a vlákna jako Web Workery nad sdílenou pamětí.
4. Server v Rustu servíruje stránku, modul a herní data a propojuje hráče.
5. Funguje jen s jedním konkrétním exe (kontrola SHA-256). Vygenerované C a modul se necommitují, repozitář obsahuje jen lifter a runtime.

Výsledek: fyzika, AI i herní módy jsou přesně originál, protože běží původní kód. Navíc 120 fps, widescreen, ovladače a síťová hra.

## Rozbor `Porsche.exe` (2. 11. 2026)

Oficiální patch z 5. 6. 2000, nešifrovaný (D-023).

| | Zjištění |
| --- | --- |
| Formát | PE, 32bitové x86, linker MSVC 6.0, 2,1 MB, sekce `.text` asi 1,7 MB |
| Funkce | asi 5 840 (výpis Ghidry v `decomposed/ghidra/`) |
| Grafika | Vrstva EA **THRASH**: 36 funkcí (`init`, `setvideomode`, `talloc`, `settexture`, `setstate`, `drawtrimesh`, `drawtristrip`, `drawquad`, `drawsprite`, `pageflip`, `lockwindow`, `readrect` ...). Hra kreslí jen přes ni. Direct3D 7 je až v ovladači `dx7z.dll` (není v `sources/`) |
| Ostatní importy | 238 funkcí: KERNEL32, USER32, ADVAPI32 (registry), WINMM (časovače, joystick), DDRAW (2), DINPUT (1), DSOUND (2), WSOCK32 (síťová hra). Dál RAS, TAPI, ICMP a updater EA `mrbupd.dll`, které se dají vypnout |
| Zvláštnosti | Sekce `PACODE` (7 KB) je pravděpodobně ručně psaný assembler. Stopy instrukcí `cpuid`, `rdtsc`, MMX a 3DNow! (přes `cpuid` se asi volí cesta podle procesoru). Hodně matematiky na x87 |

## Výhody proti NFSU2

- Menší exe a méně funkcí.
- Místo celého Direct3D stačí znovu napsat 36 funkcí THRASH nad WebGPU nebo Metalem. `dx7z.dll` není potřeba.
- Jediná pevná verze exe a žádné DRM se neobchází (`PORSCHE.ICD` se nepoužívá).

## Rizika

- Lifter NFSU2Recomp je psaný na jedno exe. Musel by se upravit (tabulky skoků, volací konvence, CRT z MSVC 6).
- Věrnost fyziky závisí na tom, jak přesně lifter napodobí x87 (80bitová přesnost, zaokrouhlování).
- `PACODE` a cesty pro MMX/3DNow!: buď je lifter převede, nebo se vynutí obyčejná cesta pro x87.
- Časování smyčky (`timeSetEvent`, `rdtsc`) se musí zachovat.
- Odhad práce: měsíce, ne týdny (NFSU2 Web stavěl na hotovém rekompilátoru).

## Vztah k pravidlům a ke Stuttgart Speed

- Je to jiný cíl než Stuttgart Speed: přesný originál, ne vlastní hra nad daty originálu.
- Narazí to na D-001 a D-023 (kód originálu se nepřepisuje, dekompilát nepatří do repozitáře). Vygenerované C by patřilo jen do `decomposed/` (D-008), do repozitáře jen vlastní lifter a runtime. Vyžaduje nové rozhodnutí, nejspíš i samostatný repozitář.
- Jen pro osobní použití (D-009), bez veřejného webu s daty originálu.
- Užitek pro Stuttgart Speed: běžící rekompilát jako přesné měřítko. Záznam telemetrie originálu (rychlosti, zrychlení, smyky, poškození) by šlo použít k ladění `car.gd` místo odhadů a místo Wine.
- Vše zdarma (D-012): Capstone (BSD), wasi-sdk (Apache 2.0), lifter NFSU2Recomp (MIT).

## První krok, pokud se přijme

Ověřit lifter NFSU2Recomp na `Porsche.exe`: kolik funkcí se převede a přeloží a co se v `PACODE` a x87 rozbije. Bez runtime, jen jako měření.
