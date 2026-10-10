test_that("GeoJSON files of several values are read together", {
  storage <- local_storage()
  write_geojson(storage, "11")
  write_geojson(storage, "84")
  df <- download(values = c("11", "84"), year = 2022)
  expect_s3_class(df, "sf")
  expect_equal(sort(df$INSEE_DEP), c("01", "75", "92"))
  expect_equal(sf::st_crs(df)$epsg, 4326L)
})

test_that("GeoJSON region codes fall back to the unpadded spelling", {
  # Files published before 2025 are stored under REGION=1, not REGION=01
  storage <- local_storage()
  write_geojson(storage, "01", region_in_path = "1")
  for (value in list(1, "1", "01")) {
    expect_equal(download(values = value, year = 2022)$INSEE_DEP, "971")
  }
})

test_that("a missing GeoJSON file raises an error", {
  local_storage()
  expect_error(download(values = "11", year = 2022))
})

test_that("GeoParquet is filtered by filter_by", {
  storage <- local_storage()
  write_consolidated(storage, 2025)
  cases <- list(
    list("REGION", "11", c("75", "92")),
    list("REGION", list(1, "84"), c("01", "971")),
    list("TERRITOIRE", "guadeloupe", "971"),
    list("FRANCE_ENTIERE", "France", c("01", "75", "92", "971"))
  )
  for (case in cases) {
    # year 2025: "auto" reads the GeoParquet
    df <- download(values = case[[2]], filter_by = case[[1]], year = 2025)
    expect_equal(sort(df$INSEE_DEP), case[[3]])
    expect_false("bbox" %in% names(df))
    expect_equal(sf::st_crs(df)$epsg, 4326L)
  }
})

test_that("GeoParquet is read when GeoJSON is requested", {
  # No GeoJSON file for 2025 here: the GeoParquet is read
  storage <- local_storage()
  write_consolidated(storage, 2025)
  expect_warning(
    df <- download(values = "11", year = 2025, vectorfile_format = "geojson"),
    "GeoParquet is used instead"
  )
  expect_equal(sort(df$INSEE_DEP), c("75", "92"))
})

test_that("GeoJSON can be forced for a year that has GeoJSON files", {
  # 2022: GeoJSON files of the former pipeline, and a GeoParquet produced
  # afterwards
  storage <- local_storage()
  write_geojson(storage, "11")
  write_consolidated(storage, 2022)
  calls <- readers(expect_warning(
    df <- download(values = "11", year = 2022, vectorfile_format = "geojson", force = TRUE),
    "Reading GeoJSON files as requested"
  ))
  expect_equal(sort(df$INSEE_DEP), c("75", "92"))
  expect_equal(calls, "read_geojson")
})

test_that("force is ignored without GeoJSON files", {
  for (year in c(2025, 2023)) {
    storage <- local_storage()
    write_consolidated(storage, year)
    calls <- readers(expect_warning(
      df <- download(values = "11", year = year, vectorfile_format = "geojson", force = TRUE),
      "force = TRUE is ignored"
    ))
    expect_equal(sort(df$INSEE_DEP), c("75", "92"))
    expect_equal(calls, "read_parquet")
  }
})

test_that("geojson_available", {
  args <- PATH_ARGS[setdiff(names(PATH_ARGS), c("value", "filter_by"))]
  storage <- local_storage()
  write_geojson(storage, "11", year = 2022)
  write_geojson(storage, "11", year = 2025)
  available <- function(year) {
    do.call(geojson_available, c(list("11", "REGION"), utils::modifyList(args, list(year = year))))
  }
  expect_false(available(2025))
  expect_true(available(2022))
  expect_false(available(2023))
})

test_that("parquet_available", {
  args <- PATH_ARGS[setdiff(names(PATH_ARGS), c("value", "territory"))]
  storage <- local_storage()
  write_consolidated(storage, 2022)
  available <- function(year) {
    do.call(parquet_available, utils::modifyList(args, list(year = year)))
  }
  expect_true(available(2025))
  expect_true(available(2022))
  expect_false(available(2023))
})

test_that("GeoParquet produced for an earlier year is read", {
  storage <- local_storage()
  write_geojson(storage, "11")
  write_consolidated(storage, 2022)
  calls <- readers({
    expect_warning(
      df <- download(values = "11", year = 2022, vectorfile_format = "geojson"),
      "GeoParquet is used instead"
    )
    download(values = "11", year = 2022)
  })
  expect_equal(sort(df$INSEE_DEP), c("75", "92"))
  expect_equal(calls, c("read_parquet", "read_parquet"))
})

test_that("GeoJSON is read when there is no GeoParquet for an earlier year", {
  storage <- local_storage()
  write_geojson(storage, "11")
  calls <- readers(df <- download(values = "11", year = 2022))
  expect_equal(sort(df$INSEE_DEP), c("75", "92"))
  expect_equal(calls, "read_geojson")
})

test_that("a missing GeoParquet file raises an error", {
  storage <- local_storage()
  write_consolidated(storage, 2025)
  expect_error(
    download(values = "11", year = 2022, vectorfile_format = "parquet"),
    "available from 2025"
  )
})

test_that("GeoParquet errors", {
  storage <- local_storage()
  write_consolidated(storage, 2025)
  expect_error(
    download(values = "75", filter_by = "DEPARTEMENT", year = 2025),
    "cannot be filtered by DEPARTEMENT"
  )
  expect_error(download(values = c("11", "99"), year = 2025), "No REGION 99")
})

test_that("engine = 'duckdb' returns a lazy table", {
  skip_if_not_installed("dbplyr")
  storage <- local_storage()
  write_consolidated(storage, 2025)
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  tbl <- download(values = "11", year = 2025, engine = "duckdb", con = con)
  expect_s3_class(tbl, "tbl_lazy")
  total <- dplyr::pull(dplyr::summarise(tbl, total = sum(POPULATION, na.rm = TRUE)))
  expect_equal(total, 3)
  df <- to_sf(dplyr::filter(tbl, POPULATION > 1))
  expect_s3_class(df, "sf")
  expect_equal(df$INSEE_DEP, "75")
})

test_that("engine = 'duckdb' is not read yet", {
  skip_if_not_installed("dbplyr")
  storage <- local_storage()
  write_consolidated(storage, 2025)
  tbl <- download(values = "11", year = 2025, engine = "duckdb", where = "POPULATION > 1")
  plan <- paste(utils::capture.output(dplyr::explain(tbl)), collapse = "\n")
  expect_match(gsub(" ", "", plan), "POPULATION>1")
  expect_no_match(plan, "COLUMN_DATA_SCAN")
})

test_that("engine = 'duckdb' reads GeoJSON", {
  skip_if_not_installed("dbplyr")
  storage <- local_storage()
  write_geojson(storage, "11")
  tbl <- download(values = "11", year = 2022, engine = "duckdb")
  expect_equal(dplyr::pull(dplyr::count(tbl)), 2)
})

test_that("unknown engine", {
  expect_error(download(values = "11", year = 2025, engine = "polars"), "engine")
})

# Paris (2.3, 48.8), Hauts-de-Seine (2.2, 48.8), Guadeloupe, Ain (5, 46)
WHERE_CASES <- list(
  list("POPULATION > 1", "75"),
  list("INSEE_DEP IN ('92', '01') AND POPULATION = 1", c("01", "92")),
  # Bounding box around Paris
  list("ST_Intersects(geometry, ST_MakeEnvelope(2.25, 48.7, 2.4, 48.9))", "75"),
  # Within 400 km of Paris: Ain is ~390 km away (~440 km if the coordinates
  # were read as latitude, longitude)
  list(
    "ST_Distance_Sphere(ST_Centroid(geometry), ST_Point(2.35, 48.85)) < 400000",
    c("01", "75", "92")
  ),
  list(
    paste0(
      "ST_DWithin(ST_Transform(geometry, 'EPSG:4326', 'EPSG:2154'), ",
      "ST_Transform(ST_Point(2.35, 48.85), 'EPSG:4326', 'EPSG:2154'), 400000)"
    ),
    c("01", "75", "92")
  )
)

test_that("where on GeoParquet", {
  storage <- local_storage()
  write_consolidated(storage, 2025)
  for (case in WHERE_CASES) {
    df <- download(values = "France", filter_by = "FRANCE_ENTIERE", year = 2025, where = case[[1]])
    expect_equal(sort(df$INSEE_DEP), case[[2]], label = case[[1]])
  }
})

test_that("where on GeoJSON", {
  storage <- local_storage()
  write_geojson(storage, "11")
  write_geojson(storage, "84")
  write_geojson(storage, "01", region_in_path = "1")
  for (case in WHERE_CASES) {
    df <- download(values = c("11", "84", "01"), year = 2022, where = case[[1]])
    expect_equal(sort(df$INSEE_DEP), case[[2]], label = case[[1]])
  }
})

test_that("where with no matching polygon", {
  storage <- local_storage()
  write_consolidated(storage, 2025)
  df <- download(values = "11", year = 2025, where = "POPULATION > 100")
  expect_s3_class(df, "sf")
  expect_equal(nrow(df), 0)
})

test_that("invalid where", {
  storage <- local_storage()
  write_consolidated(storage, 2025)
  for (where in c("POPULATION >", "UNKNOWN_COLUMN > 1", "not_a_function(geometry)")) {
    expect_error(
      download(values = "11", year = 2025, where = where),
      "Invalid where expression"
    )
  }
})

test_that("default simplification is 80", {
  # Without simplification, the lightest GeoParquet (80 % of points removed)
  storage <- local_storage()
  write_consolidated(storage, 2025, simplification = 80)
  df <- carti_download(values = "11", borders = "DEPARTEMENT", filter_by = "REGION", year = 2025)
  expect_equal(sort(df$INSEE_DEP), c("75", "92"))
})

test_that("default simplification of GeoJSON is 50", {
  # The GeoJSON files of 2022 only exist with 0 and 50: 50 by default
  storage <- local_storage()
  write_geojson(storage, "11")
  calls <- readers(
    df <- carti_download(values = "11", borders = "DEPARTEMENT", filter_by = "REGION", year = 2022)
  )
  expect_equal(sort(df$INSEE_DEP), c("75", "92"))
  expect_equal(calls, "read_geojson")
})

test_that("production files are read (network, read-only)", {
  skip_on_cran()
  skip_if_offline("minio.lab.sspcloud.fr")
  # 2022: GeoJSON, stored under REGION=1
  for (value in list(1, "1", "01")) {
    df <- carti_download(
      values = value, borders = "DEPARTEMENT", filter_by = "REGION",
      year = 2022, simplification = 50
    )
    expect_equal(df$INSEE_DEP, "971")
  }
  # 2026: GeoParquet
  df <- carti_download(
    values = "11", borders = "DEPARTEMENT", filter_by = "REGION",
    year = 2026, simplification = 50
  )
  expect_equal(nrow(df), 8)
})
