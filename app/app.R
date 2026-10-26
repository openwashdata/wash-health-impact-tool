# Entry point for Posit Connect Cloud. The app itself ships with the washhealth
# package (pkg/inst/app); the library calls below let the manifest pick up the
# packages the app needs, which washhealth only suggests.
library(shiny)
library(bslib)
library(brand.yml)
library(washhealth)

options(washhealth.methodology_url = "https://github.com/openwashdata/wash-health-impact-tool/blob/main/docs/methodology.qmd")
shinyAppDir(system.file("app", package = "washhealth"))
