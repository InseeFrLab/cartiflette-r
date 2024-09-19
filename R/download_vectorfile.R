#' Download and read a single geographical vector file from a generated URL.
#'
#' This function generates a URL using specified parameters and downloads a single
#' geographical vector file from the URL. The downloaded file is then read into an
#' R data frame using the 'sf' package.
#'
#' @inheritParams create_url_download
#'
#' @return An 'sf' data frame containing the downloaded geographical vector data.
#'
#' @seealso \code{\link{create_url_download}} for generating the download URL.
#'
#' @examples
#' download_vectorfile_url_single()
#' plot(sf::st_geometry(download_vectorfile_url_single()))
#' df <- download_vectorfile_url_single(filter_by = "REGION", year = 2022, value = 52, crs = 4326)
#' plot(sf::st_geometry(df))
#' @export
download_vectorfile_url_single <- function(
    value = 75,
    borders = "COMMUNE",
    vectorfile_format="geojson",
    filter_by = "DEPARTEMENT",
    year = 2022,
    provider = "IGN",
    source = "EXPRESS-COG-CARTO-TERRITOIRE",
    crs = 4326,
    bucket = "projet-cartiflette",
    path_within_bucket = "production",
    dataset_family = "ADMINEXPRESS",
    territory = "metropole",
    simplification = "0.0",
    filename = "raw"
){

  url <- create_url_download(
    borders = borders,
    vectorfile_format=vectorfile_format,
    filter_by = filter_by,
    year = year,
    provider = provider,
    source = source,
    crs = crs,
    value = value,
    path_within_bucket = path_within_bucket,
    dataset_family = dataset_family,
    territory = territory,
    simplification = simplification,
    filename = filename
  )

  df <- sf::st_read(url)

  return(df)
}

#' Download a series of files from cartiflette project.
#'
#'
#' @rdname carti_download
#' @inheritParams download_vectorfile_url_single
#'
#' @return An 'sf' data frame containing the downloaded geographical vector data.
#' @note `download_vectorfile_url_all` is deprecated and will be removed in
#'  a future version
#' @examples
#' df <- carti_download(
#'    crs = 4326,
#'    values = c("75", "92", "93", "94"),
#'    borders="COMMUNE_ARRONDISSEMENT",
#'    vectorfile_format="geojson",
#'    filter_by="DEPARTEMENT",
#'    source="EXPRESS-COG-CARTO-TERRITOIRE",
#'    year=2022)
#' plot(sf::st_geometry(df))
#'
#' @export
carti_download <- function(
    values = c("28", "29"),
    borders = "COMMUNE",
    vectorfile_format="geojson",
    filter_by = "DEPARTEMENT",
    year = 2022,
    provider = "IGN",
    source = "EXPRESS-COG-CARTO-TERRITOIRE",
    crs = 4326,
    bucket = "projet-cartiflette",
    path_within_bucket = "production",
    dataset_family = "ADMINEXPRESS",
    territory = "metropole",
    simplification = "0.0",
    filename = "raw"
){

  vectors <- lapply(
    values,
    download_vectorfile_url_single,
    borders = borders,
    vectorfile_format = vectorfile_format,
    filter_by = filter_by,
    year = year,
    provider = provider,
    source = source,
    crs = crs,
    path_within_bucket = path_within_bucket,
    dataset_family = dataset_family,
    territory = territory,
    simplification = simplification,
    filename = filename
  )

  vectors <- dplyr::bind_rows(vectors)

  return(vectors)

}

#' @rdname carti_download
#' @export
download_vectorfile_url_all <- function(...) {
  .Deprecated("carti_download")
  return(carti_download(...))
}
