# cartiflette <img src="https://raw.githubusercontent.com/InseeFrLab/cartiflette/main/cartiflette.png" align="right" height="110" alt="cartiflette" />

**Les fonds de carte officiels français, en une ligne de code.**

Contours officiels de l'IGN (ADMIN EXPRESS COG CARTO) enrichis des métadonnées de
l'Insee : communes, arrondissements municipaux, IRIS, départements, régions, bassins
de vie, zones d'emploi, unités urbaines, aires d'attraction des villes, avec ou sans
les DROM rapprochés de la métropole.

Ce package suit le [client Python](https://github.com/InseeFrLab/cartiflette/tree/main/python-package/cartiflette) :
mêmes arguments, mêmes fichiers, lus avec DuckDB.

## Installation

```r
# install.packages("remotes")
remotes::install_github("inseefrlab/cartiflette-r")
```

R 4.1 ou plus récent. Le package dépend de `duckdb` (≥ 1.5) et de `sf`. Au premier
appel, DuckDB télécharge ses extensions `httpfs`, `json` et `spatial`.

## Utilisation

```r
library(cartiflette)

departements <- carti_download(
  values = "France",
  borders = "DEPARTEMENT",
  filter_by = "FRANCE_ENTIERE_DROM_RAPPROCHES",
  year = 2026
)
plot(departements["POPULATION"])
```

- `borders` : niveau des contours (`COMMUNE`, `COMMUNE_ARRONDISSEMENT`,
  `IRIS` à partir de 2025, `DEPARTEMENT`, `REGION`, `BASSIN_VIE`,
  `ZONE_EMPLOI`, `UNITE_URBAINE`, `AIRE_ATTRACTION_VILLES`).
- `filter_by` et `values` : zone couverte, par exemple `filter_by = "REGION"` et
  `values = c("11", "84")`, ou `filter_by = "FRANCE_ENTIERE"` et
  `values = "France"`. Les IRIS se filtrent aussi par commune :
  `filter_by = "COMMUNE", values = "34172"`. Les codes de région sous 10
  s'écrivent indifféremment `1`, `"1"` ou `"01"`.
- `simplification` : part des points retirés, `0` (contours complets), `50` ou
  `80` (le plus léger, par défaut). Pour 2022, publié seulement en GeoJSON, le
  défaut est `50`.
- `year` : millésime du Code officiel géographique (année en cours par défaut).

Le résultat est un data frame `sf` (EPSG:4326).

## Filtrer : `where`

`where` garde les polygones qui vérifient une expression SQL DuckDB, sur leurs
attributs ou leur géométrie (fonctions `ST_*` de l'extension spatiale, coordonnées
en longitude, latitude) :

```r
# Communes de plus de 2 000 habitants d'Occitanie
carti_download(
  values = "76",
  borders = "COMMUNE",
  filter_by = "REGION",
  year = 2026,
  where = "POPULATION > 2000"
)

# Communes qui touchent une emprise (la Camargue)
carti_download(
  values = "France",
  borders = "COMMUNE",
  filter_by = "FRANCE_ENTIERE",
  year = 2026,
  where = "ST_Intersects(geometry, ST_MakeEnvelope(4.1, 43.3, 4.9, 43.75))"
)

# Communes dont le centre est à moins de 30 km du Capitole de Toulouse
carti_download(
  values = "France",
  borders = "COMMUNE",
  filter_by = "FRANCE_ENTIERE",
  year = 2026,
  where = "ST_Distance_Sphere(ST_Centroid(geometry), ST_Point(1.4442, 43.6047)) < 30000"
)
```

Sur le GeoParquet, le filtre est appliqué pendant la lecture : seules les parties
utiles du fichier sont téléchargées.

## Formats : GeoParquet d'abord

Chaque niveau est publié en GeoParquet dans un seul fichier, que DuckDB lit
partiellement : seules les parties correspondant aux valeurs demandées sont
téléchargées (environ 2 Mo pour les communes d'un département). Le package lit le
GeoParquet dès qu'il existe, même si `vectorfile_format = "geojson"` est demandé
(un avertissement l'indique). Pour les millésimes publiés seulement en GeoJSON
(2022), il le détecte et lit le GeoJSON.

Aucun fichier GeoJSON n'est publié à partir de 2025 : `force = TRUE`, qui force la
lecture du GeoJSON, ne vaut que pour les millésimes qui en ont (2022). Pour obtenir
du GeoJSON des millésimes récents, utiliser l'API :
`https://cartiflette-api.lab.sspcloud.fr/v1/geojson`.

## Rester dans DuckDB

Avec `engine = "duckdb"`, le résultat est une table paresseuse (`dbplyr`), pas encore
lue, pour continuer avec dplyr ou en SQL ; `to_sf()` la convertit ensuite :

```r
library(dplyr)

communes <- carti_download(
  values = c("11", "84"),
  borders = "COMMUNE",
  filter_by = "REGION",
  year = 2026,
  engine = "duckdb"
)
communes |>
  group_by(INSEE_REG) |>
  summarise(population = sum(POPULATION, na.rm = TRUE)) |>
  collect()

communes |>
  filter(POPULATION > 50000) |>
  to_sf()
```

L'argument `con` permet de passer sa propre connexion DuckDB, par exemple pour
joindre les contours à d'autres données.

## Proxy

Déclarer la variable d'environnement `https_proxy` : elle est transmise à DuckDB.

```r
Sys.setenv(https_proxy = "http://mon-proxy:8080")
```

## Tests

```r
devtools::test()
```

Les tests lisent des fichiers locaux, sauf un qui lit des fichiers publiés en
production (lecture seule, ignoré hors connexion).

## En savoir plus

- [Site de cartiflette](https://inseefrlab.github.io/cartiflette/) : exemples
  et cas d'usage.
- [Dépôt GitHub](https://github.com/InseeFrLab/cartiflette) : pipeline de production,
  client Python et documentation technique.
- [NEWS.md](NEWS.md) : les changements de chaque version.
