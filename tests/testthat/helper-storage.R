# The files are served from a local directory: the option
# cartiflette.endpoint_url points to it, DuckDB reading local paths and URLs
# the same way.

PATH_ARGS <- list(
  provider = "IGN",
  dataset_family = "ADMINEXPRESS",
  source = "EXPRESS-COG-CARTO-TERRITOIRE",
  year = 2022,
  borders = "DEPARTEMENT",
  crs = 4326,
  filter_by = "REGION",
  value = "11",
  territory = "metropole",
  simplification = 50
)

DEPARTEMENTS <- sf::st_sf(
  INSEE_DEP = c("75", "92", "971", "01"),
  INSEE_REG = c("11", "11", "01", "84"),
  AREA = c("metropole", "metropole", "guadeloupe", "metropole"),
  PAYS = rep("France", 4),
  POPULATION = c(2L, 1L, 1L, 1L),
  geometry = sf::st_sfc(
    sf::st_point(c(2.3, 48.8)), sf::st_point(c(2.2, 48.8)),
    sf::st_point(c(-61.5, 16.2)), sf::st_point(c(5, 46)),
    crs = 4326
  )
)

# Local directory standing for the S3 storage
local_storage <- function(env = parent.frame()) {
  storage <- withr::local_tempdir(.local_envir = env)
  withr::local_options(cartiflette.endpoint_url = storage, .local_envir = env)
  storage
}

# GeoJSON of the departements of a region (legacy layout: REGION=1)
write_geojson <- function(storage, region, year = 2022, region_in_path = region) {
  args <- utils::modifyList(PATH_ARGS, list(year = year, value = region_in_path))
  path <- file.path(
    storage, do.call(create_path_bucket, c(args, vectorfile_format = "geojson"))
  )
  dir.create(dirname(path), recursive = TRUE)
  sf::st_write(
    DEPARTEMENTS[DEPARTEMENTS$INSEE_REG == region, ], path,
    driver = "GeoJSON", quiet = TRUE
  )
  path
}

# Consolidated GeoParquet of departements, one row group per row, with a bbox
# column and the cartiflette:filter_columns metadata
write_consolidated <- function(storage, year, simplification = 50) {
  args <- PATH_ARGS[setdiff(names(PATH_ARGS), c("value", "filter_by", "territory"))]
  args <- utils::modifyList(args, list(year = year, simplification = simplification))
  path <- file.path(
    storage, do.call(create_path_consolidated, c(args, layout = "FRANCE_ENTIERE"))
  )
  dir.create(dirname(path), recursive = TRUE)
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbExecute(con, "LOAD spatial")
  df <- sf::st_drop_geometry(DEPARTEMENTS)
  df$wkt <- sf::st_as_text(sf::st_geometry(DEPARTEMENTS))
  duckdb::duckdb_register(con, "departements", df)
  filters <- '{"REGION": "INSEE_REG", "TERRITOIRE": "AREA", "FRANCE_ENTIERE": "PAYS"}'
  DBI::dbExecute(con, sprintf(
    "COPY (
      SELECT * EXCLUDE (wkt), ST_GeomFromText(wkt) AS geometry,
        struct_pack(xmin := ST_XMin(geometry), ymin := ST_YMin(geometry),
                    xmax := ST_XMax(geometry), ymax := ST_YMax(geometry)) AS bbox
      FROM departements
    ) TO '%s' (FORMAT parquet, ROW_GROUP_SIZE 1, KV_METADATA {'cartiflette:filter_columns': '%s'})",
    path, filters
  ))
  path
}

download <- function(...) {
  args <- utils::modifyList(
    list(borders = "DEPARTEMENT", filter_by = "REGION", simplification = 50),
    list(...)
  )
  do.call(carti_download, args)
}

# Names of the reading functions called during `code`
readers <- function(code) {
  calls <- character()
  read_parquet <- cartiflette:::read_parquet
  read_geojson <- cartiflette:::read_geojson
  testthat::with_mocked_bindings(
    code,
    read_parquet = function(...) {
      calls <<- c(calls, "read_parquet")
      read_parquet(...)
    },
    read_geojson = function(...) {
      calls <<- c(calls, "read_geojson")
      read_geojson(...)
    },
    .package = "cartiflette"
  )
  calls
}
