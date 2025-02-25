source("./R/generic_scraper.R")
source("./R/utilities.R")

pennsylvania_bi_population_pull <- function(x, wait = 10){
    # scrape from the power bi iframe directly
    y <- "https://app.powerbigov.us/view?r=" %>%
        str_c(
            "eyJrIjoiMTcyY2I2MjMtZjJjNC00NjNjLWJjNWYtNTZlZWE1YmRkYWYwIiwidCI",
            "6IjQxOGUyODQxLTAxMjgtNGRkNS05YjZjLTQ3ZmM1YTlhMWJkZSJ9",
            "&pageName=ReportSection")
    
    remDr <- RSelenium::remoteDriver(
        remoteServerAddr = "localhost",
        port = 4445,
        browserName = "firefox"
    )
    
    del_ <- capture.output(remDr$open())
    remDr$navigate(y)
    
    Sys.sleep(wait)
    
    raw_html <- xml2::read_html(remDr$getPageSource()[[1]])
    
    is_population <- raw_html %>%
        rvest::html_nodes(xpath="//div[@class='preTextWithEllipsis']") %>%
        rvest::html_text() %>%
        str_detect("(?=.*Inmate)(?=.*Population)") %>%
        any()
    
    if(!is_population){
        warning("Page structure may have changed please inspect.")
    }
    
    raw_html
}

pennsylvania_bi_population_restruct  <- function(x){
    val_sr_str <- "//text[@class='label' and contains(@transform,'translate')]"
    lab_sr_str <- "//text[@class='setFocusRing']//title"

    tibble(
        Name = x %>%
            rvest::html_nodes(xpath=lab_sr_str) %>%
            rvest::html_text(),
        
        Residents.Population = x %>%
            rvest::html_nodes(xpath=val_sr_str) %>%
            rvest::html_text())
}




pennsylvania_bi_population_extract <- function(x){
    x %>%
        clean_scraped_df()
}

#' Scraper class for general PA population data from dashboard
#' 
#' @name pennsylvania_bi_population_scraper
#' @description One page in PAs power BI tool which is dedicated to inmate
#' population. We scrape each page with relevant data from the PA bi tool with
#' separate scrapers.
#' 
#' \describe{
#'   \item{Facility}{Facility abbreviation}
#'   \item{Population}{inmates population}
#' }

pennsylvania_bi_population_scraper <- R6Class(
    "pennsylvania_bi_population_scraper",
    inherit = generic_scraper,
    public = list(
        log = NULL,
        initialize = function(
            log,
            url = "https://www.cor.pa.gov/Pages/COVID-19.aspx",
            id = "pennsylvania_bi_population",
            type = "html",
            state = "PA",
            jurisdiction = "state",
            # pull the JSON data directly from the API
            pull_func = pennsylvania_bi_population_pull,
            # restructuring the data means pulling out the data portion of the 
            restruct_func = pennsylvania_bi_population_restruct,
            # Rename the columns to appropriate database names
            extract_func = pennsylvania_bi_population_extract){
            super$initialize(
                url = url, id = id, pull_func = pull_func, type = type,
                restruct_func = restruct_func, extract_func = extract_func,
                log = log, state = state, jurisdiction = jurisdiction)
        }
    )
)

if(sys.nframe() == 0){
    pennsylvania_bi_population <- pennsylvania_bi_population_scraper$new(log=TRUE)
    pennsylvania_bi_population$raw_data
    pennsylvania_bi_population$pull_raw()
    pennsylvania_bi_population$raw_data
    pennsylvania_bi_population$save_raw()
    pennsylvania_bi_population$restruct_raw()
    pennsylvania_bi_population$restruct_data
    pennsylvania_bi_population$extract_from_raw()
    pennsylvania_bi_population$extract_data
    pennsylvania_bi_population$validate_extract()
    pennsylvania_bi_population$save_extract()
}

