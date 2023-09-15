#' Create a URL to download cartiflette dataset.
#'
#' This function generates a URL for downloading geographical vector data
#' based on the provided parameters.
#'
#' @param base_url The base URL for the data repository. Default is the URL for the project.
#' @param year The year of the data to download. Default is 2022.
#' @param borders The administrative level for filtering the data. Default is "COMMUNE".
#' @param crs The coordinate reference system (CRS) for the data. Default is 4326.
#' @param vectorfile_format The format of the vector file to download. Default is "geojson".
#' @param filter_by The filter criterion for the data. Default is "DEPARTEMENT".
#' @param provider The data provider. Default is "IGN".
#' @param source The data source. Default is "EXPRESS-COG-CARTO-TERRITOIRE".
#' @param value The value to filter the data by. Default is 75.
#'
#' @return A character string representing the generated download URL.
#'
#' @examples
#' create_url_download()
#' create_url_download(year = 2021, borders = "REGION", crs = 4326)
#'
#' @export



create_url_download <- function(
    base_url = "https://minio.lab.sspcloud.fr/projet-cartiflette/diffusion/shapefiles-test2",
    year = 2022,
    borders = "COMMUNE",
    crs = 4326,
    vectorfile_format="geojson",
    filter_by = "DEPARTEMENT",
    provider = "IGN",
    source = "EXPRESS-COG-CARTO-TERRITOIRE",
    value = 75
  ){

  download_link <- glue::glue(
    "{base_url}/year={year}/administrative_level={borders}/crs={crs}"
  )
  download_link <- glue::glue(
    "{download_link}/{filter_by}={value}/vectorfile_format={vectorfile_format}"
  )
  download_link <- glue::glue(
    "{download_link}/provider={provider}/source={source}/raw.{vectorfile_format}"
  )

return(download_link)
}
