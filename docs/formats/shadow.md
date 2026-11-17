---
type: format
updated: 2026-11-17
---

# Stíny v originálu

Originál nepočítá stíny za běhu: nemá stínové mapy ani stencil stíny. Všechny stíny ve hře jsou textury připravené předem. Zjištěno rozborem `Porsche.exe` (Ghidra, REA, 17. 11. 2026) a dat, porovnáno se snímky originálu.

| Stín | Kde v datech | Jak vznikne |
| --- | --- | --- |
| Stín auta na zemi | `GameData/CarModel/Shadow.fsh` | Průhledná textura pod autem, viz níže |
| Ztmavení kolem kol | díly `WheelShadow*` v `.crp` aut ([crp.md](crp.md)) | Vrstvený díl modelu s tmavou texturou |
| Stín stromů a mostů na zemi | plochy s příznakem `Base` 0x0040 a texturou `sh80` (`Shadow#`, `Ltreeshade#`) v `.crp` tratí ([crp.md](crp.md)) | Průhledný obtisk nad terénem |
| Světlo a stín na trati | textury tratí | Namalované přímo v texturách. Tratě nemají normály, hra je za běhu neosvětluje |
| Stín stromů a lamp na autě | `<trať>.env` + `<trať>.map` ([map.md](map.md)) | Obtisk promítnutý na auto podle řezu trati |

Nerozluštěné zůstávají efekty `ef` druhu 4 (`Shadow#` na farmlandu, [crp.md](crp.md#efekty-ef-článku)). Podle názvu patří ke stínovým plochám trati, jejich účel zatím není známý.

## Stín auta (`Shadow.fsh`)

Archiv SHPI ([fsh.md](fsh.md)) s jediným obrázkem `Shad` 64×64, typ 0x7D (32 bitů). Je to černý půlkruh, alfa slábne k okraji. Funkce načítání společných textur aut (`FUN_00443760`) skládá cestu `%s%s.fsh` z tabulky `shadow`, `intglass`, `suit`, `head`, `cabrio` (0x5CDAFC). Stín je první položka. Z něj se vytvoří průhledný materiál, který se kreslí pod autem. Na snímcích originálu je pod autem vždy stejná měkká tmavá skvrna se zakulacenými konci. Nemění tvar podle karoserie ani podle směru slunce. Pravděpodobně jde o dva protilehlé půlkruhy roztažené na půdorys auta. Přesný tvar geometrie a odsazení od podvozku zatím rozluštěné nejsou.

## Nepoužité volby stínů v exe

`Porsche.exe` obsahuje stopy rozpracovaných skutečných stínů, které vydaná hra nepoužívá:

- Klíčová slova nastavení `SHADOWMAPPING` a `DETAILEDSHADOWS` v tabulce voleb grafiky (plní ji kód na 0x4B13BA, záznamy jméno, číslo volby 0x52 / 0x53, proměnná). Proměnné 0x657D94 a 0x657D98 se zapisují jen v této tabulce, kód je nikde nečte.
- Volby `Graphics.ShadowMapping` a `Graphics.DetailedShadows` a texty 10217 (`detailed shadows`) a 10218 (`shadow mapping`) v `FEData/Locale/festrings.csv`. Layout `advgraphics.lay`, ke kterému texty patří, je nepoužívá, v menu nejsou.
- Třída `R3DShadowMapTextureLayer` (RTTI). Továrna texturových vrstev (0x449B70) ji vytvoří pro typ vrstvy 0x8102. Kód tento typ nikde přímo nepoužívá. Zda ho vyžaduje některý datový soubor, zatím nebylo ověřeno.

Řetězce `data.dropshadow`, `data.hasshadow`, `data.noshadow` a `stencilshape1`–`9` patří k menu (stín písma a tvary prvků), ne ke 3D scéně.

## Důsledky pro hru

Věrnost originálu nevyžaduje stíny počítané za běhu: stačí skvrna pod autem, ztmavení kol, plochy `sh80` a obtisky `.env` (D-044). Stíny slunce v Godotu (D-014, D-019) jsou vylepšení proti originálu. Volba LOW QUALITY proto kreslí jako originál, bez stínů za běhu (D-048).
