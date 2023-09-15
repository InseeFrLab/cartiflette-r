# Librairie `R` `cartiflette`

<!-- badges: start -->
<!-- badges: end -->

## Installation

You can install the development version of cartiflette from [GitHub](https://github.com/) with:

``` r
# install.packages("devtools")
devtools::install_github("linogaliana/cartiflette")
```

## Example

This is a basic example which shows you how to solve a common problem:

``` r
library(cartiflette)
df <- download_vectorfile_url_all(
    crs = 4326,
    values = c("75", "92", "93", "94"),
    borders="COMMUNE_ARRONDISSEMENT",
    vectorfile_format="geojson",
    filter_by="DEPARTEMENT",
    source="EXPRESS-COG-CARTO-TERRITOIRE",
    year=2022)
plot(sf::st_geometry(df))
```

