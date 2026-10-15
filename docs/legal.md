---
type: legal-notes
updated: 2026-10-15
disclaimer: "Orientační přehled, ne právní rada."
---

# Právní mantinely

## Pravidla pro repozitář

Repozitář je privátní. Data originální hry a licencované modely smí být jen lokálně ve složkách `sources/` (původní assety) a `decomposed/` (rozbalené). Obě jsou v `.gitignore`. Tabulka platí pro obsah, který se commituje, a pro případné budoucí zveřejnění.

| Obsah | Commit do gitu | Poznámka |
| --- | --- | --- |
| Vlastní kód enginu a hry | ano | |
| Nástroje, které čtou data z kopie hry uživatele | ano | Stejný model jako [OpenNFS](https://github.com/OpenNFS/OpenNFS) |
| Popis formátů souborů | ano | Výsledek vlastní analýzy |
| Fiktivní auta a vlastní tratě | ano | |
| Modely, textury, tratě, zvuky a hudba z originálu, i upravené | **ne**, jen `sources/` a `decomposed/` | Autorské dílo EA, šíření porušuje práva (riziko DMCA) |
| Licencované nebo rozpoznatelné modely vozů Porsche | **ne**, jen `sources/` | Porsche si nárokuje i tvary vozů a názvy (911, Carrera, Boxster...) |
| Věrně obtažená geometrie trati originálu | **ne** | Odvozené dílo |
| Číselné parametry z originálu převzaté do vlastních aut | s rozmyslem | Používat jako referenci pro realistické hodnoty éry, ne kopírovat tabulky |

## Kdo vlastní co

- **EA:** kód, modely, textury, tratě, zvuky, hudba původní hry. Status abandonware na tom nic nemění.
- **Porsche AG:** jméno, logo, názvy modelů a charakteristické tvary vozů. Porsche je uvádí jako chráněné ([porsche.com](https://www.porsche.com/uk/trademarksandotheriprs)) a vymáhá je ([Carscoops – Porsche vs. Singer](https://www.carscoops.com/?p=2988628)). V EU byly zrušeny dva zapsané průmyslové vzory 911 ([Rollits](https://rollits.com/news/articles/the-pitfalls-of-an-iconic-design)), ochrana známky a proti nekalé soutěži ale trvá.
- **Nikdo:** herní mechaniky, žánr, struktura režimů, reálná krajina.
