ENDPOINT_URL <- "https://minio.lab.sspcloud.fr"
BUCKET <- "projet-cartiflette"
PATH_WITHIN_BUCKET <- "production"
# First vintage published as consolidated GeoParquet files. From this vintage
# on, no GeoJSON file is published: the API serves GeoJSON from the GeoParquet.
# Earlier vintages may have GeoJSON files (2022, former pipeline).
PARQUET_FIRST_YEAR <- 2025
# Default simplification (percentage of points removed). The GeoJSON files of
# the former pipeline only exist with 0 and 50: 50 is their default.
DEFAULT_SIMPLIFICATION <- 80
GEOJSON_DEFAULT_SIMPLIFICATION <- 50
DROM_RAPPROCHES <- "FRANCE_ENTIERE_DROM_RAPPROCHES"
ENGINES <- c("sf", "duckdb")
# Key of the GeoParquet metadata mapping each level usable in `filter_by` to
# its column in a consolidated file (e.g. BASSIN_VIE -> BV2022)
FILTER_COLUMNS_KEY <- "cartiflette:filter_columns"

# Base URL of the storage. The option `cartiflette.endpoint_url` points to
# another location, e.g. a local directory in the tests.
endpoint_url <- function() {
  getOption("cartiflette.endpoint_url", ENDPOINT_URL)
}
