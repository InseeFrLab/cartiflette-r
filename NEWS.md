# cartiflette 0.2.0

Réécriture complète, alignée sur le client Python 0.4.0 : le package lit les
fichiers du nouveau _pipeline_ (millésimes 2023 à 2026 en GeoParquet) avec DuckDB.

## Ajouté

- Lecture du **GeoParquet** consolidé (un fichier par niveau) avec DuckDB : seuls
  les groupes de lignes utiles sont téléchargés. Il est lu dès qu'il existe :
  toujours à partir de 2025, après une vérification par requête HEAD pour les
  années antérieures. Les **GeoJSON** (2022, un fichier par valeur) sont lus
  ensemble par DuckDB quand il n'y a pas de GeoParquet.
- `vectorfile_format = "auto"` (défaut) ; `"geojson"` lit le GeoParquet s'il
  existe, avec un avertissement, sauf `force = TRUE` pour les millésimes qui ont
  des fichiers GeoJSON.
- `borders = "IRIS"` (à partir de 2025), filtrable notamment par commune.
- `filter_by = "FRANCE_ENTIERE_DROM_RAPPROCHES"` : DROM rapprochés de la
  métropole, zoom sur l'Île-de-France.
- Argument `where` : expression SQL DuckDB sur les attributs ou la géométrie
  (`ST_Intersects`, `ST_Distance_Sphere`…), appliquée pendant la lecture.
- `engine = "duckdb"` : table paresseuse dbplyr, et `to_sf()` pour la convertir.
- Argument `con` pour passer sa propre connexion DuckDB.
- Les codes de région sous 10 s'écrivent `1`, `"1"` ou `"01"`.
- Proxy lu dans `https_proxy`.
- Tests (testthat) sur des fichiers locaux.

## Modifié

- **Simplification par défaut à 80** (part des points retirés), 50 pour les
  millésimes publiés seulement en GeoJSON (2022). La simplification s'écrit
  `0`, `50` ou `80`, plus `"0.0"`.
- `carti_download()` reprend les arguments du client Python : `values` est
  obligatoire, `filter_by` vaut `"REGION"` par défaut, `year` l'année en cours.
- Dépendances : `duckdb` (≥ 1.5), `sf`, `DBI`, `jsonlite`, `curl` ; `dplyr`
  n'est plus nécessaire.

## Supprimé

- `download_vectorfile_url_single()` et `create_url_download()`, qui
  construisaient des liens vers des fichiers GeoJSON qui ne sont plus publiés
  (`create_path_bucket()` et `create_path_consolidated()` donnent les chemins).
  `download_vectorfile_url_all()` reste, déprécié, comme alias de
  `carti_download()`.
