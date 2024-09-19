#' Create a URL to download cartiflette dataset.
#'
#' This function generates a URL for downloading geographical vector data
#' based on the provided parameters. The URL is constructed to match the
#' specific format required by the data repository.
#'
#' @param base_url The base URL for the data repository. Default is the URL for the project.
#' @param year The year of the data to download. Default is 2022.
#' @param borders The administrative level for filtering the data, now including arrondissements. Default is "COMMUNE_ARRONDISSEMENT".
#' @param crs The coordinate reference system (CRS) for the data. Default is 4326.
#' @param vectorfile_format The format of the vector file to download. Default is "geojson".
#' @param filter_by The filter criterion for the data. Default is "DEPARTEMENT".
#' @param provider The data provider. Default is "IGN".
#' @param source The data source, adjusted to the new dataset family parameter. Default is "EXPRESS-COG-CARTO-TERRITOIRE".
#' @param value The value to filter the data by. Default is 75.
#'
#' @return A character string representing the generated download URL.
#'
#' @examples
#' create_url_download()
#' create_url_download(year = 2021, borders = "REGION", crs = 4326, value = 33)
#'
#' @export

create_url_download <- function(
  base_url = "https://minio.lab.sspcloud.fr",
  year = 2022,
  borders = "COMMUNE_ARRONDISSEMENT",
  crs = 4326,
  vectorfile_format = "geojson",
  filter_by = "DEPARTEMENT",
  provider = "IGN",
  source = "EXPRESS-COG-CARTO-TERRITOIRE",
  value = 75,
  bucket = "projet-cartiflette",
  path_within_bucket = "production",
  dataset_family = "ADMINEXPRESS",
  territory = "metropole",
  simplification = "0.0",
  filename = "raw"
) {

  if (filename == "value"){
    filename <- value
  }

  base_url_bucket <- glue::glue(
    "{base_url}/{bucket}/{path_within_bucket}"
  )

  download_link <- glue::glue(
    "{base_url_bucket}/",
    "provider%3D{provider}/",
    "dataset_family%3D{dataset_family}/",
    "source%3D{source}/",
    "year%3D{year}/",
    "administrative_level%3D{borders}/",
    "crs%3D{crs}/",
    "{filter_by}%3D{value}/",
    "vectorfile_format%3D{vectorfile_format}/",
    "territory%3D{territory}/",
    "simplification%3D{simplification}/",
    "{filename}.{vectorfile_format}"
  )

  return(download_link)
}
