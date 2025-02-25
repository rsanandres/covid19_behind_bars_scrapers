source("./R/generic_scraper.R")
source("./R/utilities.R")

indiana_pull <- function(x){
    in_img <- get_src_by_attr(x, "img", attr = "src", attr_regex = "(?i)COVID")
    
    magick::image_read(in_img)
}

indiana_restruct <- function(x){

    # Run through OCR
    results <- ExtractTable(x)
    
    # Wrangle Data
    if (length(results) == 2) {
        if("0" %in% names(results[[1]])){
            names(results[[1]]) <- as.character(
                max(as.numeric(names(results[[2]]))) +
                    as.numeric(names(results[[1]])) + 1)
        }
        d <- cbind(results[[2]],results[[1]])
    } else {
        d <- results[[1]]
    }

    d
}

indiana_extract <- function(x){
    col_name_mat <- matrix(c(
        "Correctional Facility", "0", "Name",
        "Staff Tested", "1", "Staff.Tested",
        "Staff Current Positive", "2", "Staff.Active",
        "Staff Total Positive", "3", "Staff.Confirmed",
        "Staff Recovered", "4", "Staff.Recovered",
        "Staff Death", "5", "Staff.Deaths",
        "Offender Test", "6", "Residents.Tadmin",
        "Offender Current Positive", "7", "Residents.Active",
        "Offender Total Positive", "8", "Residents.Confirmed",
        "Offender Recovered", "9", "Residents.Recovered",
        "Offender Presumed Death", "10", "Drop.Res.Deaths.Presumed",
        "Offender Confirmed Death", "11", "Drop.Res.Deaths.Confirmed"
        ), ncol = 3, nrow = 12, byrow = TRUE)
    
    colnames(col_name_mat) <- c("check", "raw", "clean")
    col_name_df <- as_tibble(col_name_mat)
    
    check_names_extractable(x, col_name_df)
    
    rename_extractable(x, col_name_df) %>%
        as_tibble() %>%
        filter(Name!="Correctional Facility" & Name!="Total") %>%
        clean_scraped_df() %>%
        mutate(Residents.Deaths =
                   Drop.Res.Deaths.Presumed + Drop.Res.Deaths.Confirmed) %>%
        select(-starts_with("Drop"))
        
}

#' Scraper class for general Indiana COVID data
#' 
#' @name indiana_scraper
#' @description Data from IN is pulled from a image hosted in the DOC website
#' which is run the OCR. The data posted has been consistent however it should
#' be noted that it seems that residents confirmed goes down when they leave
#' the facility so recovered can be higher than confirmed.
#' \describe{
#'   \item{Correctional Facility}{The facility name.}
#'   \item{COVID-19 Tests Administered to Staff}{Test administered by facility to staff}
#'   \item{Staff Positive for COVID-19}{Staff who are confirmed}
#'   \item{Staff Recovered COVID-19}{Staff who have recovered after being confirmed}
#'   \item{Staff Confirmed / Presumed COVID-19 Death}{Staff deaths related to covid}
#'   \item{Offenders in Quarantine}{Residents currently in quarantine}
#'   \item{Offenders in Isolation}{Residents currently in isolation}
#'   \item{COVID-19 Tests Administered to Offenders}{Number of tests administered to residents, not number of residents tested}
#'   \item{Offender Positive for COVID-19}{Residents currently in facility confirmed sometimes lower than recovered}
#'   \item{Offenders Recovered COVID-19}{Redidents who have recovered}
#'   \item{Offender Presumed COVID-19 Death}{Residents who have died, presumably to covid}
#'   \item{Offender Confirmed COVID-19 Death}{Residents who have died related to covid}
#' }

indiana_scraper <- R6Class(
    "indiana_scraper",
    inherit = generic_scraper,
    public = list(
        log = NULL,
        initialize = function(
            log,
            url = "https://www.in.gov/idoc/3780.htm",
            id = "indiana",
            type = "img",
            state = "IN",
            jurisdiction = "state",
            pull_func = indiana_pull,
            restruct_func = indiana_restruct,
            # Rename the columns to appropriate database names
            extract_func = indiana_extract){
            super$initialize(
                url = url, id = id, pull_func = pull_func, type = type,
                restruct_func = restruct_func, extract_func = extract_func,
                log = log, state = state, jurisdiction = jurisdiction)
        }
    )
)

if(sys.nframe() == 0){
    indiana <- indiana_scraper$new(log=TRUE)
    indiana$raw_data
    indiana$pull_raw()
    indiana$raw_data
    indiana$save_raw()
    indiana$restruct_raw()
    indiana$restruct_data
    indiana$extract_from_raw()
    indiana$extract_data
    indiana$validate_extract()
    indiana$save_extract()
}

