---
type: analysis
updated: 2026-10-15
reference_game:
  title: "Need for Speed: Porsche 2000"
  alt_title: "Need for Speed: Porsche Unleashed"
  publisher: "Electronic Arts"
  year: 2000
  platform: "Windows (také PS1, GBA)"
target_platform: "macOS, Apple Silicon"
related: [decisions.md, plan.md, legal.md, data-inventory.md]
---

# Analýza

## 1. Co dělalo originál výjimečným

Atmosféru nesla cesta historií značky a pocit, že každé auto je jiné. Hra měla kolem 74 modelů z let 1948–2000 ([PSX DataCenter](https://psxdatacenter.com/games/P/N/SLES-02700.html)).

| Prvek | Originál | Pro remake |
| --- | --- | --- |
| Evolution | Kariéra napříč érami Classic, Golden, Modern. Nákup, prodej, vylepšování a opravy aut ([MobyGames](https://www.mobygames.com/game/1398)) | Jádro hry |
| Factory Driver | Mise testovacího jezdce: slalomy, testy trakce, doručení auta bez poškození, vyděšení spolujezdce ([RetroAchievements](https://retroachievements.org/game/14732)) | Levné na výrobu, zábavné. Do rané verze |
| Jízdní model | Na svou dobu realistický, každé auto se řídí jinak | Parametry pro každé auto zvlášť |
| Poškození | Ovlivňovalo výkon a stálo peníze na opravy ([GameRevolution](https://www.gamerevolution.com/?p=340585)) | Zachovat vazbu na jízdu a ekonomiku |
| Tratě | Otevřené silnice evropské krajiny, alternativní cesty, provoz, policie | Krajina a světlo tvoří atmosféru |
| Další režimy | Rychlý závod, honička s policií, volná jízda | Až po jádru |

Slabiny originálu k opravě: slabá umělá inteligence soupeřů, pop-up objektů ([The Pixel Empire](https://thepixelempire.net/need-for-speed-porsche-2000-ps-review.html)), paušální poškození bez ohledu na místo nárazu ([GameRevolution](https://www.gamerevolution.com/?p=340585)).

## 2. Volba enginu (macOS)

| Kritérium | Godot 4.6 | Unity 6 | Unreal 5 | Fork OpenNFS |
| --- | --- | --- | --- | --- |
| Mac | Nativní Metal na Apple Silicon od 4.4 ([Godot](https://godotengine.org/article/dev-snapshot-godot-4-4-dev-1/)) | Zralá podpora | Nativní od 5.2, s omezeními ([Epic](https://www.unrealengine.com/en-US/tech-blog/unreal-engine-5-2-brings-native-support-for-apple-silicon-and-other-developments-for-macos)) | OpenGL, na Macu zastaralé |
| Fyzika | Jolt, výchozí od 4.6 ([Cinevva](https://app.cinevva.com/news/2026-02-27-godot-4-6-released)) | PhysX, `WheelCollider` | Chaos Vehicles | Bullet |
| Licence | MIT, zdarma | Zdarma do limitu obratu | Poplatek nad limit tržeb | MIT |
| Náročnost | Nízká (GDScript/C#) | Střední (C#) | Vysoká (C++) | Velmi vysoká (C++) |
| Hodnocení | **doporučeno** | alternativa | přehnané | jen pro věrnou rekonstrukci |

Konvertory dat jsou samostatné nástroje (Python), výstup glTF/JSON čte jakýkoli engine.

## 3. Jízdní model

- Kola jako raycasty s pružinou a tlumičem.
- Model pneumatiky: boční a podélný grip podle prokluzu, elipsa přilnavosti.
- Přenos hmotnosti při brzdění a v zatáčce (rozdíl mezi zadomotorovým autem 50. let a moderním vozem).
- Motor s křivkou točivého momentu, převodovka, diferenciál. Parametry pro každé auto.
- Nastavitelní asistenti: stabilizace, pomoc při driftu, ABS.

Referenční hodnoty pro realistická auta dané éry: viz [formats/sim.md](formats/sim.md).

## 4. Kolize

- Auto: 1–3 konvexní obaly.
- Trať: statický trojúhelníkový mesh silnice, zjednodušené tvary okolí (svodidla, zdi, stromy).
- Soupeři a provoz: stejná fyzika, AI jede po ideální stopě.

## 5. Model poškození

| Vrstva | Implementace | Dopad |
| --- | --- | --- |
| Zóny | Předek, zadek, levý bok, pravý bok, střecha. „Zdraví“ klesá podle impulzu nárazu | Základ |
| Deformace | Posun vrcholů kolem místa nárazu podle síly a směru, s limitem | Vizuální |
| Odpadávající díly | Nárazníky, kapota, zrcátka jako samostatná tělesa po překročení prahu | Vizuální, aerodynamika |
| Mechanika | Předek: chlazení a výkon. Zavěšení: tah do strany. Světla: viditelnost v noci | Jízda |
| Ekonomika | Cena opravy podle zón v kariéře | Kariéra |

## 6. Umělá inteligence soupeřů

Originál má nastavení AI v čitelných CSV (viz [data-inventory.md](data-inventory.md)):
- osobnosti soupeřů (např. „Nemesis“) s parametry blokování, odstřižení, dohledu,
- „gumička“: násobič rychlosti podle vzdálenosti od hráče (×1,25 když hráč vede o 600 m, ×0,82 když ztrácí 600 m),
- rozestupy v koloně.

Mechaniky se dají převzít jako nápad, čísla jako výchozí hodnoty pro ladění.

Podrobný rozbor (ideální stopy `.lsp`, profily `.ais`, řízení `TRAFCFG`), srovnání s dnešními hrami a plán: [opponents.md](opponents.md).

## 7. Komunitní projekty

| Projekt | Využití |
| --- | --- |
| [OpenNFS](https://github.com/OpenNFS/OpenNFS) | Referenční kód čtení CRP/FSH (C++, MIT). NFS5: auta ~40 %, tratě ~5 % |
| [LibOpenNFS](https://github.com/dima424658/LibOpenNFS) | Čtení formátů jako knihovna |
| Discord „Classic Need for Speed“, #open_nfs | Autoři reverse engineeringu formátů |
| [NFSAddons](https://www.nfsaddons.com/forums/index.php?msg=35724) | Nástroje (CarSuite, fshtool), patche |
| [SilentPatch](https://github.com/CookiePLMonster/SilentPatchNFS90s/commit/0b8b7149f0cc0914c10c0ad6996636b9e6d726ce) | Spuštění originálu na moderním systému |
| [Wineskin NFS5](https://github.com/Seminioni/nfs5) | Originál na Macu jako živá reference |

Modely aut stažené z komunity nepoužívat: často jde o převzaté modely z jiných her.

## Zdroje

- [OpenNFS](https://github.com/OpenNFS/OpenNFS)
- [LibOpenNFS](https://github.com/dima424658/LibOpenNFS)
- [VG Resource – ripování modelů NFS5](https://archive.vg-resource.com/post-643542.html)
- [NFSAddons – nástroje NFS5](https://www.nfsaddons.com/downloads/nfspu/cars/porsche/1700/porsche-porsche-550-spyder-54-55.html)
- [NFSAddons – filtr CRP pro ZModeler](https://www.nfsaddons.com/downloads/nfspu/cars/koenig/1330/koenig-c62-race-version.html)
- [Godot 4.4 – Metal backend](https://godotengine.org/article/dev-snapshot-godot-4-4-dev-1/)
- [Godot 4.6 – Jolt jako výchozí](https://app.cinevva.com/news/2026-02-27-godot-4-6-released)
- [Epic – UE 5.2 a Apple Silicon](https://www.unrealengine.com/en-US/tech-blog/unreal-engine-5-2-brings-native-support-for-apple-silicon-and-other-developments-for-macos)
- [MobyGames](https://www.mobygames.com/game/1398)
- [PSX DataCenter](https://psxdatacenter.com/games/P/N/SLES-02700.html)
- [Force for Good – recenze](https://forceforgood.co.uk/racing/need-for-speed-porsche-2000/)
- [The Pixel Empire – recenze](https://thepixelempire.net/need-for-speed-porsche-2000-ps-review.html)
- [GameRevolution – recenze](https://www.gamerevolution.com/?p=340585)
- [RetroAchievements](https://retroachievements.org/game/14732)
