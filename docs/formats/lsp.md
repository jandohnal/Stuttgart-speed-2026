---
type: file-format
format: lsp
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: "GameData/Track/racer/work/<trať>0.lsp, <trať>1.lsp; GameData/Track/<trať>_forward.key, _backwards.key"
count: "30 .lsp, 28 .key"
status: partial_decoded
tool: "tools/ai_lines.py"
output: "decomposed/GameData/Track/<trať>/<trať>_ai.json"
updated: 2026-10-29
---

# Ideální stopy soupeřů (`.lsp`) a klíče tratí (`.key`)

## `.lsp` – ideální stopa

Dva soubory na trať (`<trať>0.lsp`, `<trať>1.lsp`) ve složce `racer/work`. Little-endian:

| Offset | Typ | Obsah |
| --- | --- | --- |
| 0x00 | int32 | verze, vždy 1 |
| 0x04 | 2 × float32 na bod | bod stopy pro **každý řez SimD** v pořadí řezů: (−x, z) v osách glTF z `track2gltf.py` |

- Počet bodů = počet řezů `slice_count` v `_road.json` u všech 15 tratí (ověřeno, `tools/ai_lines.py` to kontroluje).
- Výška chybí, bod leží na řezu. Odchylka podél silnice je do 2–6 m (zhruba rozestup řezů), boční odchylka od středu řezu je stopa.
- Na rovných úsecích je stopa často přesně ve středu (na farmlandu 1272 z 1995 řezů), v zatáčkách se posouvá o 1–4 m. Místy vychází 20–37 m od středu řezu (foothills, Monte Carlo). V Monte Carlu (monaco1, řezy 310–321) to je skutečná trasa varianty: vede vedlejší ulicí, zatímco řezy SimD pokračují do zátarasu. Řidič AI proto bere stopu bez omezení na šířku řezů a s 935 tudy projede (ověřeno 29. 10. 2026).
- V Monte Carlu (monaco1) u řezů 74–87 vede stopa 0 13–15 m od středu řezu ulicí, kterou varianta uzavírá zátarasy (auto AI narazí do `SAWHORSE_RIGID06` u řezu 81); stopa 1 tam jede 6–7 m od středu volně. U řezů 306–324 jsou obě stopy stejné. Stopy tedy možná patří k různým variantám trati.
- Skidpad má obě stopy celé ve středu.

**Stopa 0 a 1:** korelace bočních odchylek na hlavním úseku 0,1–0,96 podle trati. Hypotézy: stopa pro jízdu vpřed a vzad (`_forward` / `_backwards` u `.key` tomu odpovídá), nebo dvě stopy pro předjíždění. Ověřit v `Porsche.exe` (D-023).

## `.key` – klíče po úsecích trati

`<trať>_forward.key` a `<trať>_backwards.key` (Monte Carlo `Monaco1_forward.key` …, skidpad žádný), vždy 3208 B:

| Offset | Typ | Obsah |
| --- | --- | --- |
| 0x00 | int32 | verze, vždy 1 |
| 0x04 | int32 | počet klíčů včetně závěrečného (13–90) |
| 0x08 | (int32, float32) × počet | index řezu (rostoucí, od 0), hodnota |
| … | | zbytek do 3208 B (400 párů) jsou staré nepoužité hodnoty |

- Poslední klíč je zarážka (100000, 600), u `industrial_backwards` (100000, 398,8).
- Hodnoty 149–600, kvantované (např. 309,3; 402,5; 454,7 se opakují), strop 600.
- **Význam neznámý.** Podle rozsahu a stropu nejspíš tempo nebo rychlostní limit soupeřů pro úsek od daného řezu (jednotka nesedí na m/s ani km/h). Ověřit v exe.

## Výstup `tools/ai_lines.py`

`<trať>_ai.json`: `lines` = dvě pole bočních odchylek (m, + doprava podle vektoru `right` řezu), `keys` = `{forward, backwards}` jako páry `[řez, hodnota]`. Boční odchylka místo souřadnic, aby stopa seděla i na 3D řezech (stoupání, náklon).
