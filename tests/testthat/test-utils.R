test_that("create_path_bucket keeps the layout of the published files", {
  # Layout of the files published in production: must not change
  expect_equal(
    do.call(create_path_bucket, c(PATH_ARGS, vectorfile_format = "geojson")),
    paste0(
      "projet-cartiflette/production/provider=IGN/dataset_family=ADMINEXPRESS/",
      "source=EXPRESS-COG-CARTO-TERRITOIRE/year=2022/",
      "administrative_level=DEPARTEMENT/crs=4326/REGION=11/",
      "vectorfile_format=geojson/territory=metropole/simplification=50/",
      "raw.geojson"
    )
  )
})

test_that("create_path_bucket takes another location", {
  args <- utils::modifyList(PATH_ARGS, list(simplification = NULL))
  path <- do.call(create_path_bucket, c(
    args,
    vectorfile_format = "parquet", bucket = "my-bucket", path_within_bucket = "test"
  ))
  expect_true(startsWith(path, "my-bucket/test/provider=IGN/"))
  expect_true(endsWith(path, "/simplification=0/raw.parquet"))
})

test_that("create_path_consolidated matches the pipeline", {
  # Same test in the pipeline and the Python client
  expect_equal(
    create_path_consolidated(
      provider = "IGN",
      dataset_family = "ADMINEXPRESS",
      source = "EXPRESS-COG-CARTO-TERRITOIRE",
      year = 2025,
      borders = "COMMUNE",
      crs = 4326,
      layout = "FRANCE_ENTIERE_DROM_RAPPROCHES",
      simplification = 50.0
    ),
    paste0(
      "projet-cartiflette/production/provider=IGN/dataset_family=ADMINEXPRESS/",
      "source=EXPRESS-COG-CARTO-TERRITOIRE/year=2025/administrative_level=COMMUNE/",
      "crs=4326/layout=FRANCE_ENTIERE_DROM_RAPPROCHES/vectorfile_format=parquet/",
      "simplification=50/raw.parquet"
    )
  )
})

test_that("standardize_format", {
  expect_equal(standardize_format("geojson"), "geojson")
  expect_equal(standardize_format("GeoJSON"), "geojson")
  expect_equal(standardize_format("parquet"), "parquet")
  expect_equal(standardize_format("geoparquet"), "parquet")
  for (format in c("topojson", "shp", "gpkg")) {
    expect_error(standardize_format(format), "Unsupported format")
  }
})

test_that("value_candidates pads the region codes below 10", {
  expect_equal(value_candidates("REGION", 1), c("01", "1"))
  expect_equal(value_candidates("REGION", "1"), c("01", "1"))
  expect_equal(value_candidates("REGION", "01"), c("01", "1"))
  expect_equal(value_candidates("region", "6"), c("06", "6"))
  expect_equal(value_candidates("REGION", "11"), "11")
  expect_equal(value_candidates("REGION", 84), "84")
  expect_equal(value_candidates("DEPARTEMENT", "01"), "01")
  expect_equal(value_candidates("DEPARTEMENT", "2A"), "2A")
  expect_equal(value_candidates("COMMUNE", 100000), "100000")
  expect_equal(value_candidates("FRANCE_ENTIERE", "France"), "France")
})

test_that("choose_format", {
  expect_equal(choose_format("auto", 2025), "parquet")
  expect_equal(choose_format("AUTO", "2026"), "parquet")
  expect_equal(choose_format("auto", 2024), "geojson")
  expect_equal(choose_format("geojson", 2022), "geojson")
  expect_equal(choose_format("geoparquet", 2022), "parquet")
  expect_equal(choose_format("auto", 2022, parquet_exists = TRUE), "parquet")
  expect_equal(choose_format("auto", 2025, parquet_exists = FALSE), "geojson")
})

test_that("choose_format prefers GeoParquet", {
  expect_warning(
    expect_equal(choose_format("geojson", 2025), "parquet"),
    "GeoParquet is used instead"
  )
  # 2022 republished with GeoParquet: its GeoJSON files can still be forced
  expect_warning(
    expect_equal(
      choose_format("geojson", 2022, force = TRUE, parquet_exists = TRUE),
      "geojson"
    ),
    "force = TRUE"
  )
})

test_that("choose_format ignores force without GeoJSON files", {
  # No GeoJSON file from 2025 onwards (or for a year republished by the
  # current pipeline): force = TRUE is ignored
  for (case in list(list(2025, NULL), list(2026, NULL), list(2023, FALSE))) {
    expect_warning(
      expect_equal(
        choose_format(
          "geojson", case[[1]],
          force = TRUE, parquet_exists = TRUE, geojson_exists = case[[2]]
        ),
        "parquet"
      ),
      "no GeoJSON file.*force = TRUE is ignored"
    )
  }
})
