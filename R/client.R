# Connection shared by the calls without `con`, created at the first call
.cartiflette <- new.env(parent = emptyenv())

#' DuckDB connection able to read the cartiflette files
#'
#' @param con Existing DuckDB connection to use. By default, an in-memory
#'   connection shared by all the calls: the tables returned with
#'   `engine = "duckdb"` stay usable, and the extensions are loaded once.
#' @return Connection with the httpfs and spatial extensions loaded. The proxy
#'   is taken from the `https_proxy` environment variable. Coordinates are
#'   read as (longitude, latitude), the order of the files, by the functions
#'   that depend on it (`geometry_always_xy`): `ST_Distance_Sphere` and
#'   `ST_Transform` from EPSG:4326 expect (latitude, longitude) otherwise.
#' @noRd
connect <- function(con = NULL) {
  if (is.null(con)) {
    if (is.null(.cartiflette$con) || !DBI::dbIsValid(.cartiflette$con)) {
      .cartiflette$con <- DBI::dbConnect(duckdb::duckdb())
    }
    con <- .cartiflette$con
  }
  DBI::dbExecute(con, "SET enable_progress_bar = false")
  DBI::dbExecute(con, "INSTALL httpfs; LOAD httpfs; INSTALL json; LOAD json; INSTALL spatial; LOAD spatial;")
  DBI::dbExecute(con, "SET geometry_always_xy = true")
  proxy <- Sys.getenv("https_proxy", Sys.getenv("HTTPS_PROXY"))
  if (nzchar(proxy)) {
    # DuckDB expects host:port
    proxy <- sub("/.*$", "", sub("^[A-Za-z]+://", "", proxy))
    DBI::dbExecute(con, paste0("SET http_proxy = ", DBI::dbQuoteString(con, proxy)))
  }
  con
}

#' Format of the files to read
#'
#' GeoParquet is used whenever it exists (from 2025 onwards, and for the
#' earlier years it has been produced for): only the needed parts of the file
#' are downloaded. GeoJSON is only read when there is no GeoParquet, or when
#' explicitly requested with `force = TRUE` for a year that has GeoJSON files:
#' none is published from 2025 onwards.
#'
#' @param vectorfile_format "auto", "geojson", "parquet" or "geoparquet".
#' @param year Vintage.
#' @param force Read GeoJSON when requested even if GeoParquet exists,
#'   provided GeoJSON files exist for the year.
#' @param parquet_exists Whether GeoParquet exists (see `parquet_available`).
#'   By default, deduced from the year only: from 2025 onwards.
#' @param geojson_exists Whether GeoJSON files exist (see
#'   `geojson_available`). By default, deduced from the year only: before
#'   2025.
#' @return "parquet" or "geojson". A warning is emitted when GeoJSON is
#'   requested and GeoParquet exists.
#' @noRd
choose_format <- function(vectorfile_format, year, force = FALSE,
                          parquet_exists = NULL, geojson_exists = NULL) {
  year <- as.integer(year)
  if (is.null(parquet_exists)) {
    parquet_exists <- year >= PARQUET_FIRST_YEAR
  }
  if (is.null(geojson_exists)) {
    geojson_exists <- year < PARQUET_FIRST_YEAR
  }
  if (tolower(vectorfile_format) == "auto") {
    return(if (parquet_exists) "parquet" else "geojson")
  }
  vectorfile_format <- standardize_format(vectorfile_format)
  if (vectorfile_format != "geojson" || !parquet_exists) {
    return(vectorfile_format)
  }
  if (!geojson_exists) {
    warning(
      "GeoParquet is used instead of GeoJSON: no GeoJSON file is published ",
      "for ", year, " (only GeoParquet from ", PARQUET_FIRST_YEAR, " onwards; ",
      "the cartiflette API serves GeoJSON). It gives the same result.",
      if (force) " force = TRUE is ignored.",
      call. = FALSE
    )
    return("parquet")
  }
  if (force) {
    warning(
      "Reading GeoJSON files as requested (force = TRUE). GeoParquet is ",
      "available for ", year, ": it gives the same result and is much faster ",
      "for large requests, as only the needed parts are downloaded.",
      call. = FALSE
    )
    return("geojson")
  }
  warning(
    "GeoParquet is used instead of GeoJSON, as it is available for ", year,
    ": it gives the same result and is much faster for large requests, as ",
    "only the needed parts are downloaded. Pass force = TRUE to read the ",
    "GeoJSON files anyway.",
    call. = FALSE
  )
  "parquet"
}

is_url <- function(url) {
  grepl("^https?://", url)
}

# HEAD request
head_request <- function(url) {
  curl::curl_fetch_memory(url, handle = curl::new_handle(nobody = TRUE))
}

file_exists <- function(url) {
  if (!is_url(url)) {
    return(file.exists(url))
  }
  head_request(url)$status_code < 400
}

# Size in bytes of a file, local or remote (HEAD request)
file_size <- function(url) {
  if (!is_url(url)) {
    if (!file.exists(url)) {
      stop("No file at ", url, call. = FALSE)
    }
    return(file.size(url))
  }
  response <- head_request(url)
  if (response$status_code >= 400) {
    stop("No file at ", url, " (HTTP ", response$status_code, ")", call. = FALSE)
  }
  as.numeric(curl::parse_headers_list(response$headers)[["content-length"]])
}

#' Link of the consolidated GeoParquet holding the polygons for `filter_by`
#'
#' @param filter_by Level used to select the polygons:
#'   FRANCE_ENTIERE_DROM_RAPPROCHES reads the file with the DROM brought
#'   closer, any other level the file with the true positions.
#' @param ... Other arguments of `create_path_consolidated`, except `layout`.
#' @noRd
consolidated_url <- function(filter_by, ...) {
  layout <- if (toupper(filter_by) == DROM_RAPPROCHES) DROM_RAPPROCHES else "FRANCE_ENTIERE"
  paste0(endpoint_url(), "/", create_path_consolidated(layout = layout, ...))
}

#' Whether a consolidated GeoParquet exists for these parameters
#'
#' It is published for every year from 2025 onwards, so no request is made for
#' them. Earlier years were first published in GeoJSON only, and GeoParquet
#' may have been produced afterwards: its existence is checked with a HEAD
#' request.
#'
#' @inheritParams consolidated_url
#' @noRd
parquet_available <- function(filter_by, ...) {
  if (as.integer(list(...)$year) >= PARQUET_FIRST_YEAR) {
    return(TRUE)
  }
  file_exists(consolidated_url(filter_by, ...))
}

#' Whether GeoJSON files exist for these parameters
#'
#' No GeoJSON file is published from 2025 onwards, so no request is made for
#' them. For earlier years, the file of the first value is checked with a HEAD
#' request: a year republished by the current pipeline only has GeoParquet.
#'
#' @param values Values of `filter_by`.
#' @param filter_by Level used to split the files.
#' @param ... Other arguments of `create_path_bucket`.
#' @noRd
geojson_available <- function(values, filter_by, ...) {
  if (as.integer(list(...)$year) >= PARQUET_FIRST_YEAR) {
    return(FALSE)
  }
  tryCatch(
    file_exists(geojson_urls(values[1], filter_by, ...)),
    error = function(e) FALSE
  )
}

#' Links of the GeoJSON files of some values, one file per value
#'
#' @inheritParams geojson_available
#' @return Character vector. An error is raised if no file exists for a value
#'   that has several possible spellings (see `value_candidates`).
#' @noRd
geojson_urls <- function(values, filter_by, ...) {
  vapply(values, function(value) {
    candidates <- vapply(value_candidates(filter_by, value), function(candidate) {
      paste0(
        endpoint_url(), "/",
        create_path_bucket(
          filter_by = filter_by,
          value = candidate,
          vectorfile_format = "geojson",
          ...
        )
      )
    }, character(1))
    if (length(candidates) == 1) {
      # A missing file makes DuckDB raise an explicit HTTP 404 error
      return(candidates)
    }
    existing <- candidates[vapply(candidates, file_exists, logical(1))]
    if (length(existing) == 0) {
      stop(
        "No file for ", filter_by, " ", as_value(value), ": ",
        paste(candidates, collapse = " nor "),
        call. = FALSE
      )
    }
    existing[[1]]
  }, character(1), USE.NAMES = FALSE)
}

#' Query over several GeoJSON files, one row per feature
#'
#' A file is a single JSON object (FeatureCollection), so DuckDB's
#' `maximum_object_size` must exceed the size of the largest file. It is set
#' from the actual sizes (HEAD requests): DuckDB allocates buffers of about
#' twice this size, so a fixed large value runs out of memory on small
#' machines.
#'
#' @param con See `connect`.
#' @param urls Links of the files.
#' @return SQL query: the properties of the features as columns, and a
#'   `geometry` column.
#' @noRd
read_geojson <- function(con, urls) {
  largest <- max(vapply(urls, file_size, numeric(1)))
  sprintf(
    "SELECT
      unnest(feature.properties),
      ST_GeomFromGeoJSON(feature.geometry) AS geometry
    FROM (
      SELECT unnest(features) AS feature
      FROM read_json(
        [%s],
        maximum_object_size = %s,
        union_by_name = true,
        hive_partitioning = false
      )
    )",
    paste(DBI::dbQuoteString(con, urls), collapse = ", "),
    format(largest + 1e6, scientific = FALSE)
  )
}

#' Query over the polygons of some values in a consolidated GeoParquet
#'
#' The file holds a whole level and the filter is a `WHERE` clause: DuckDB
#' only downloads the row groups holding the requested values, thanks to the
#' sorting of the file, its statistics and bloom filters.
#'
#' @param con See `connect`.
#' @param values Values of `filter_by` to retrieve.
#' @param filter_by Level used to select the polygons (e.g. "REGION").
#' @param ... Other arguments of `create_path_consolidated`, except `layout`,
#'   deduced from `filter_by`.
#' @return SQL query, not run yet. An error is raised if there is no
#'   GeoParquet file for these parameters, if the file cannot be filtered by
#'   `filter_by`, or if some values are not found.
#' @noRd
read_parquet <- function(con, values, filter_by, ...) {
  filter_by <- toupper(filter_by)
  url <- consolidated_url(filter_by, ...)
  source <- sprintf(
    "read_parquet(%s, hive_partitioning = false)", DBI::dbQuoteString(con, url)
  )
  metadata <- tryCatch(
    DBI::dbGetQuery(con, sprintf(
      "SELECT decode(value) AS value FROM parquet_kv_metadata(%s) WHERE decode(key) = %s",
      DBI::dbQuoteString(con, url), DBI::dbQuoteString(con, FILTER_COLUMNS_KEY)
    )),
    error = function(e) {
      stop(
        "No GeoParquet file at ", url, ". GeoParquet files are available from ",
        PARQUET_FIRST_YEAR, " onwards (and for some earlier years), use ",
        "vectorfile_format = 'geojson' otherwise.\n", conditionMessage(e),
        call. = FALSE
      )
    }
  )
  filter_columns <- jsonlite::fromJSON(metadata$value[[1]])
  if (!filter_by %in% names(filter_columns)) {
    stop(
      list(...)$borders, " polygons cannot be filtered by ", filter_by,
      "; available: ", paste(names(filter_columns), collapse = ", "),
      call. = FALSE
    )
  }
  column <- DBI::dbQuoteIdentifier(con, filter_columns[[filter_by]])

  candidates <- lapply(values, value_candidates, filter_by = filter_by)
  wanted <- unique(unlist(candidates))
  where <- sprintf(
    "%s IN (%s)", column, paste(DBI::dbQuoteString(con, wanted), collapse = ", ")
  )
  found <- DBI::dbGetQuery(
    con, sprintf("SELECT DISTINCT %s AS value FROM %s WHERE %s", column, source, where)
  )$value
  missing <- vapply(values, as_value, character(1))[
    !vapply(candidates, function(cs) any(cs %in% found), logical(1))
  ]
  if (length(missing) > 0) {
    stop("No ", filter_by, " ", paste(missing, collapse = ", "), " in ", url, call. = FALSE)
  }
  sprintf("SELECT * EXCLUDE (bbox) FROM %s WHERE %s", source, where)
}

#' Keep the rows of a query matching a DuckDB SQL expression
#'
#' @param query SQL query, e.g. from `read_parquet` or `read_geojson`.
#' @param where SQL expression, as in a `WHERE` clause, on the attributes
#'   (`POPULATION > 2000`) and the `geometry` column with the functions of the
#'   DuckDB spatial extension. On a GeoParquet file, DuckDB applies it while
#'   reading.
#' @return SQL query.
#' @noRd
filter_query <- function(query, where) {
  sprintf("SELECT * FROM (%s) WHERE (%s)", query, where)
}

# Run `code`, turning the SQL errors due to `where` into a clear message
with_where <- function(code, where) {
  tryCatch(code, error = function(e) {
    if (!is.null(where) &&
      grepl("Parser Error|Binder Error|Catalog Error", conditionMessage(e))) {
      stop("Invalid where expression '", where, "': ", conditionMessage(e), call. = FALSE)
    }
    stop(e)
  })
}

#' Convert a query with a `geometry` column into an sf data frame
#'
#' @param x A lazy table returned by `carti_download(..., engine = "duckdb")`,
#'   possibly modified with dplyr, or an SQL query.
#' @param crs EPSG code of the geometries.
#' @param con DuckDB connection, when `x` is an SQL query.
#' @return An `sf` data frame.
#' @examples
#' \donttest{
#' communes <- carti_download(
#'   values = "11", borders = "COMMUNE", filter_by = "REGION",
#'   year = 2026, engine = "duckdb"
#' )
#' grandes <- dplyr::filter(communes, POPULATION > 50000)
#' to_sf(grandes)
#' }
#' @export
to_sf <- function(x, crs = 4326, con = NULL) {
  if (inherits(x, "tbl_lazy")) {
    con <- dbplyr::remote_con(x)
    x <- dbplyr::sql_render(x)
  }
  df <- DBI::dbGetQuery(con, sprintf(
    "SELECT * EXCLUDE (geometry), ST_AsWKB(geometry) AS geometry FROM (%s)", x
  ))
  geometry <- sf::st_as_sfc(
    structure(unclass(df$geometry), class = "WKB"),
    crs = sf::st_crs(as.integer(crs))
  )
  df$geometry <- NULL
  sf::st_sf(df, geometry = geometry)
}

#' Download official French borders produced by cartiflette
#'
#' Everything is done with DuckDB; with the default engine, the result is
#' converted into an `sf` data frame at the end.
#'
#' - GeoParquet (from 2025 onwards, and some earlier years): one file per
#'   level; DuckDB filters it and only downloads the needed parts.
#' - GeoJSON (2022): one file per value of `filter_by`; DuckDB reads the files
#'   together.
#'
#' @param values Values of `filter_by` to retrieve (e.g. `c("11", "84")` for
#'   REGION, `"France"` for FRANCE_ENTIERE). Region codes below 10 can be
#'   given as `1`, `"1"` or `"01"`.
#' @param borders Level of the polygons: COMMUNE, COMMUNE_ARRONDISSEMENT,
#'   IRIS (2025 onwards), DEPARTEMENT, REGION, BASSIN_VIE, ZONE_EMPLOI,
#'   UNITE_URBAINE, AIRE_ATTRACTION_VILLES.
#' @param filter_by Level used to select the polygons: DEPARTEMENT, REGION,
#'   TERRITOIRE, FRANCE_ENTIERE, FRANCE_ENTIERE_DROM_RAPPROCHES or a zoning;
#'   also COMMUNE and COMMUNE_ARRONDISSEMENT for IRIS.
#' @param territory Kept for compatibility with the storage layout of the
#'   GeoJSON files, "metropole".
#' @param vectorfile_format "auto" (default), "geojson" or "parquet".
#'   GeoParquet is read whenever it exists, even if "geojson" is requested,
#'   unless `force` is `TRUE`.
#' @param year Vintage of the borders. Defaults to the current year.
#' @param crs EPSG code of the projection. Default 4326.
#' @param simplification Simplification level, as the percentage of points
#'   removed: 0 (complete contours), 50, or 80 (lightest). Default 80, or 50
#'   for the years only published as GeoJSON (2022), which have no 80 version.
#' @param bucket Bucket of the files, "projet-cartiflette".
#' @param path_within_bucket Prefix within the bucket: "production" for the
#'   published files, or a test location such as "test/v0.4.0".
#' @param provider Provider of the data, "IGN".
#' @param dataset_family Dataset family, "ADMINEXPRESS".
#' @param source Source label in the paths, "EXPRESS-COG-CARTO-TERRITOIRE".
#' @param filename Name of the file without extension, "raw".
#' @param engine "sf" (default): return an `sf` data frame. "duckdb": return
#'   a lazy table (dbplyr), not evaluated yet, to go on with dplyr or SQL;
#'   [to_sf()] converts it.
#' @param con DuckDB connection to use (e.g. to join the result with other
#'   data). By default, an in-memory connection shared by all the calls.
#' @param force Read GeoJSON when `vectorfile_format = "geojson"` even if
#'   GeoParquet exists for the year. Only for years with GeoJSON files
#'   (2022): none is published from 2025 onwards, so GeoParquet is read
#'   anyway, with a warning.
#' @param where DuckDB SQL expression to keep only some of the polygons of
#'   `values`, on their attributes (`"POPULATION > 2000"`) or their geometry
#'   (`"ST_Intersects(geometry, ST_MakeEnvelope(4.2, 43.3, 4.9, 43.8))"`,
#'   coordinates in `crs`). Applied before the conversion, whatever the format
#'   and the engine; on the GeoParquet, while reading the file.
#'
#' @return An `sf` data frame, or a lazy table with `engine = "duckdb"`.
#'
#' @examples
#' \donttest{
#' # Departements with the DROM brought closer to metropolitan France
#' departements <- carti_download(
#'   values = "France",
#'   borders = "DEPARTEMENT",
#'   filter_by = "FRANCE_ENTIERE_DROM_RAPPROCHES",
#'   year = 2026
#' )
#' plot(sf::st_geometry(departements))
#'
#' # Communes of more than 2,000 inhabitants in Occitanie
#' communes <- carti_download(
#'   values = "76",
#'   borders = "COMMUNE",
#'   filter_by = "REGION",
#'   year = 2026,
#'   where = "POPULATION > 2000"
#' )
#' }
#' @export
carti_download <- function(values,
                           borders = "COMMUNE",
                           filter_by = "REGION",
                           territory = "metropole",
                           vectorfile_format = "auto",
                           year = NULL,
                           crs = 4326,
                           simplification = NULL,
                           bucket = BUCKET,
                           path_within_bucket = PATH_WITHIN_BUCKET,
                           provider = "IGN",
                           dataset_family = "ADMINEXPRESS",
                           source = "EXPRESS-COG-CARTO-TERRITOIRE",
                           filename = "raw",
                           engine = "sf",
                           con = NULL,
                           force = FALSE,
                           where = NULL) {
  if (!engine %in% ENGINES) {
    stop(
      "engine must be one of ", paste(ENGINES, collapse = ", "), ", not '", engine, "'",
      call. = FALSE
    )
  }
  if (engine == "duckdb" && !requireNamespace("dbplyr", quietly = TRUE)) {
    stop("engine = 'duckdb' needs the dbplyr package", call. = FALSE)
  }
  if (is.null(year)) {
    year <- as.integer(format(Sys.Date(), "%Y"))
  }
  values <- as.list(values)

  default_simplification <- is.null(simplification)
  path <- list(
    bucket = bucket,
    path_within_bucket = path_within_bucket,
    provider = provider,
    dataset_family = dataset_family,
    source = source,
    year = year,
    borders = borders,
    crs = crs,
    simplification = if (default_simplification) DEFAULT_SIMPLIFICATION else simplification,
    filename = filename
  )
  parquet_exists <- do.call(parquet_available, c(list(filter_by), path))
  geojson_exists <- NULL
  if (force && parquet_exists && tolower(vectorfile_format) == "geojson") {
    geojson_exists <- do.call(
      geojson_available, c(list(values, filter_by, territory = territory), path)
    )
  }
  vectorfile_format <- choose_format(
    vectorfile_format, year, force,
    parquet_exists = parquet_exists,
    geojson_exists = geojson_exists
  )
  if (vectorfile_format == "geojson" && default_simplification) {
    # The GeoJSON files have no 80 version
    path$simplification <- GEOJSON_DEFAULT_SIMPLIFICATION
  }
  con <- connect(con)
  if (vectorfile_format == "parquet") {
    query <- do.call(read_parquet, c(list(con, values, filter_by), path))
  } else {
    urls <- do.call(geojson_urls, c(list(values, filter_by, territory = territory), path))
    query <- read_geojson(con, urls)
  }
  if (!is.null(where)) {
    query <- filter_query(query, where)
  }

  with_where(
    if (engine == "duckdb") {
      dplyr::tbl(con, dplyr::sql(query))
    } else {
      to_sf(query, crs, con)
    },
    where
  )
}

#' @rdname carti_download
#' @param ... Arguments of `carti_download`.
#' @note `download_vectorfile_url_all` is deprecated and will be removed in a
#'   future version.
#' @export
download_vectorfile_url_all <- function(...) {
  .Deprecated("carti_download")
  carti_download(...)
}
