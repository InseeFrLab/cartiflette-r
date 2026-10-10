# User-facing format names -> format of the files stored by cartiflette
FORMATS <- c(geojson = "geojson", parquet = "parquet", geoparquet = "parquet")

#' Format of the stored files matching a user-facing format name
#'
#' @param vectorfile_format `"geojson"`, `"parquet"` or `"geoparquet"` (case
#'   insensitive).
#' @return `"geojson"` or `"parquet"`.
#' @examples
#' cartiflette:::standardize_format("GeoParquet")
#' @noRd
standardize_format <- function(vectorfile_format) {
  format <- FORMATS[tolower(vectorfile_format)]
  if (is.na(format)) {
    stop(
      "Unsupported format '", vectorfile_format, "': cartiflette files are ",
      "available as 'geojson' or 'parquet'",
      call. = FALSE
    )
  }
  unname(format)
}

# Value as a string, without scientific notation (34172, not 3.4172e+04)
as_value <- function(value) {
  if (is.numeric(value)) {
    return(format(value, scientific = FALSE, trim = TRUE))
  }
  as.character(value)
}

#' Values to try, in order, in the path of a file
#'
#' Region codes below 10 (DROM) are accepted as 1, "1" or "01": files from
#' 2025 onwards use the official code ("01"), older files the unpadded one
#' ("1").
#'
#' @param filter_by Level used to select the polygons (e.g. "REGION").
#' @param value Requested value.
#' @return Character vector of the spellings to try, the preferred one first.
#' @noRd
value_candidates <- function(filter_by, value) {
  value <- as_value(value)
  if (toupper(filter_by) == "REGION" && grepl("^[0-9]+$", value) &&
    as.integer(value) < 10) {
    return(c(sprintf("%02d", as.integer(value)), as.character(as.integer(value))))
  }
  value
}

#' Path of a cartiflette GeoJSON file within the S3 storage
#'
#' The pipeline no longer produces GeoJSON files (one file per value of
#' `filter_by`): this layout is kept to read the files already published
#' (2022). It must not change.
#'
#' @param provider Provider of the data, "IGN".
#' @param dataset_family Dataset family, "ADMINEXPRESS".
#' @param source Source label, "EXPRESS-COG-CARTO-TERRITOIRE".
#' @param year Vintage.
#' @param borders Level of the polygons (e.g. "DEPARTEMENT").
#' @param crs EPSG code.
#' @param filter_by Level used to split the files (e.g. "REGION").
#' @param value Value of `filter_by` (e.g. "11").
#' @param vectorfile_format "geojson" or "parquet".
#' @param territory "metropole" for every published file.
#' @param simplification Simplification level, 0 or 50.
#' @param filename Name of the file without extension, "raw".
#' @param bucket Bucket of the files.
#' @param path_within_bucket Prefix within the bucket, "production" for the
#'   published files.
#' @return Path "bucket/path_within_bucket/provider=.../raw.{format}", to
#'   append to the S3 endpoint URL.
#' @examples
#' create_path_bucket(
#'   provider = "IGN", dataset_family = "ADMINEXPRESS",
#'   source = "EXPRESS-COG-CARTO-TERRITOIRE", year = 2022,
#'   borders = "DEPARTEMENT", crs = 4326, filter_by = "REGION", value = "11",
#'   vectorfile_format = "geojson", territory = "metropole",
#'   simplification = 50
#' )
#' @export
create_path_bucket <- function(provider, dataset_family, source, year, borders,
                               crs, filter_by, value, vectorfile_format,
                               territory, simplification = 0,
                               filename = "raw", bucket = BUCKET,
                               path_within_bucket = PATH_WITHIN_BUCKET) {
  paste0(
    bucket, "/", path_within_bucket,
    "/provider=", provider,
    "/dataset_family=", dataset_family,
    "/source=", source,
    "/year=", year,
    "/administrative_level=", borders,
    "/crs=", crs,
    "/", filter_by, "=", value,
    "/vectorfile_format=", vectorfile_format,
    "/territory=", territory,
    "/simplification=", as_simplification(simplification),
    "/", filename, ".", vectorfile_format
  )
}

#' Path of a consolidated GeoParquet file within the S3 storage
#'
#' A consolidated file holds all the polygons of a level, to be filtered when
#' read. This must stay identical to `create_path_consolidated` in the
#' pipeline and in the Python client.
#'
#' @inheritParams create_path_bucket
#' @param layout "FRANCE_ENTIERE" (true positions) or
#'   "FRANCE_ENTIERE_DROM_RAPPROCHES" (DROM moved next to metropolitan
#'   France, Ile-de-France zoomed in).
#' @return Path "bucket/path_within_bucket/provider=.../raw.parquet".
#' @examples
#' create_path_consolidated(
#'   provider = "IGN", dataset_family = "ADMINEXPRESS",
#'   source = "EXPRESS-COG-CARTO-TERRITOIRE", year = 2026,
#'   borders = "COMMUNE", crs = 4326, layout = "FRANCE_ENTIERE",
#'   simplification = 50
#' )
#' @export
create_path_consolidated <- function(provider, dataset_family, source, year,
                                     borders, crs, layout, simplification = 0,
                                     filename = "raw", bucket = BUCKET,
                                     path_within_bucket = PATH_WITHIN_BUCKET) {
  paste0(
    bucket, "/", path_within_bucket,
    "/provider=", provider,
    "/dataset_family=", dataset_family,
    "/source=", source,
    "/year=", year,
    "/administrative_level=", borders,
    "/crs=", crs,
    "/layout=", layout,
    "/vectorfile_format=parquet",
    "/simplification=", as_simplification(simplification),
    "/", filename, ".parquet"
  )
}

# Simplification as written in the paths: 50, not 50.0
as_simplification <- function(simplification) {
  if (is.null(simplification) || is.na(simplification)) {
    return(0L)
  }
  as.integer(as.numeric(simplification))
}
