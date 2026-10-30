---
type: file-format
format: trackart
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: "FEData/TrackArt/*.fsh, FEData/Data/nfs5.trk"
count: "47 .fsh"
encoding: "FSH (SHPI), viz fsh.md"
status: decoded
tool: "tools/fsh2png.py (obecný převod FSH do PNG)"
updated: 2026-10-30
---

# Schémata tratí (`FEData/TrackArt`)

Obrázky tratí pro menu. Formát je obyčejné FSH (`docs/formats/fsh.md`), PNG jsou v `decomposed/FEData/TrackArt/<archiv>/` i s `index.json`. Pozice v `index.json` jsou jen polohy v atlasu FSH, ne na obrazovce.

## Sady pro každou trať

Tratě: alps, autobahn, canyon, castle, coastal, farmland (Normandie), foothills, forest, industrial. Některé archivy mají zkrácené názvy (`canySp`, `farmSp`, `foothiSp`, `industsp`).

| Archiv | Obrázky | Obsah |
| --- | --- | --- |
| `<trať>.fsh` | obrys (asi 260–450 × 100–220), jmenovka (asi 40–150 × 13), 2× `Fini` 16×16 | Velký obrys trati, žlutá čára s šedým stínem na průhledném pozadí. Jmenovka trati a dvě vlaječky (start a cíl) |
| `<trať>Sp.fsh` | 5× 256×192, `S`/`star` a `F`/`fin` 16×16 | První obrázek je mapa trati na tmavém podkladu silniční sítě. Další čtyři jsou snímky prostředí s průhlednou mapou přes ně a čtverečkem, který označuje místo snímku |
| `<trať>SpSm.fsh` | malá mapka (asi 125–195 × 80–130), `S` a `F` 16×16 | Malá bílá mapka se stínem |

Orientace a měřítko obrysů se mezi sadami liší (např. alps je v `alps.fsh` otočený oproti `alpsSp`), takže je nelze přímo položit na souřadnice trati.

## Monaco (Factory Driver)

`Monaco1`–`Monaco5`, `Monaco<n>Sp` a `monaco<n>SpSm` mají stejné sady jako ostatní tratě, jen vlaječky jsou 28×16. Jsou to okruhy testovací dráhy pro úlohy Factory Driveru.

| Archiv | Obsah |
| --- | --- |
| `MCLASS`, `MGOLD`, `MMOD` | Po jednom náhledu 192×144 (Prize Race) |
| `elements` | Značky `dotY` a `dot` 16×16 a vlajka 32×32, nejspíš pozice na mapě |
| `bk` | Pozadí obrazovky (`bkgr`, `TRvi`) |

## Kde je hra kreslí

- `FEData/Data/nfs5.trk` (binární, 17 880 B, nerozluštěný) je seznam tratí. U každé trati jsou interní název, zobrazovaný název, názvy archivů `…Sp` a `…SpSm` a pak soupeři s auty.
- `Layouts/missionmap.lay`: ovládací prvek `NFS5.FACTORYMAP` na `pos=192,186`, `size=252,188` (obrazovka 640×480), tedy velikost obrázků `Sp`.
- `Layouts/VictoryMessage.lay`: `NFS5.PRIZERACEMAP` na `pos=223,279`, `size=192,144`, tedy velikost `MCLASS`/`MGOLD`/`MMOD`.
- `FEData/Art/FDmaps.fsh` obsahuje jen ozdobný oblouk (`whpo`), mapu ne.

## Využití

Hlavní menu ukazuje vpravo nahoře obrys zvolené trati z `<trať>.fsh` (`000_*.png`, D-032), jmenovku kreslí vlastním písmem. Obrysy z `<trať>.fsh` a `<trať>SpSm.fsh` se hodí i jako minimapa v HUD. Polohu auta na nich je ale nutné zarovnat ručně (otočení a měřítko), nebo minimapu kreslit přímo z `_road.json`.
