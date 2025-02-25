source("./R/generic_scraper.R")
source("./R/utilities.R")

pennsylvania_bi_vaccination_pull <- function(x, wait = 10){
    # scrape from the power bi iframe directly
    y <- "https://app.powerbigov.us/view?r=" %>%
        str_c(
            "eyJrIjoiMTcyY2I2MjMtZjJjNC00NjNjLWJjNWYtNTZlZWE1YmRkYWYwIiwidCI",
            "6IjQxOGUyODQxLTAxMjgtNGRkNS05YjZjLTQ3ZmM1YTlhMWJkZSJ9",
            "&pageName=ReportSection7b14ce996120a5295481")
    
    remDr <- RSelenium::remoteDriver(
        remoteServerAddr = "localhost",
        port = 4445,
        browserName = "firefox"
    )
    
    del_ <- capture.output(remDr$open())
    remDr$navigate(y)
    
    Sys.sleep(wait)
    
    elDD <- remDr$findElement("xpath", "//div[@class='slicer-dropdown-menu']")
    elDD$clickElement()
    
    Sys.sleep(2)
    
    sub_dir <- str_c(
        "./results/raw_files/", Sys.Date(), "_pennsylvania_bi_vaccination")
    dir.create(sub_dir, showWarnings = FALSE)
    
    viz_labels <- remDr$getPageSource()[[1]] %>%
        xml2::read_html() %>%
        rvest::html_nodes(xpath="//div[@class='slicerItemContainer']") %>%
        rvest::html_attr("aria-label")
    
    html_list <- list()
    iters <- 1
    new_labels <- TRUE
    not_viz_els <- FALSE
    
    while(new_labels & iters < 6){
        for(l in viz_labels){
            if(!(l %in% names(html_list))){
                
                src_str <- str_c(
                    "//div[@class='slicerItemContainer' and @aria-label='",
                    l, "']/div")
                
                elCB <- remDr$findElement("xpath", src_str)
                
                if(elCB$isElementDisplayed()[[1]]){
                
                    elCB$clickElement()
                    Sys.sleep(7)
                    
                    html_list[[l]] <- xml2::read_html(
                        remDr$getPageSource()[[1]])
                }
                else{
                    not_viz_els <- TRUE
                }
            }
        }
        
        if(not_viz_els){
            sr_ <- "//text[@title='PARTIAL']"
            elSB <- remDr$findElements(
                "xpath", "//div[@class='scroll-bar']")[[2]]
            elDEST <- remDr$findElement("xpath", sr_)
            remDr$mouseMoveToLocation(webElement = elSB)
            remDr$buttondown()
            Sys.sleep(1)
            remDr$mouseMoveToLocation(webElement = elDEST)
            remDr$buttonup()
        }
        
        viz_labels <- remDr$getPageSource()[[1]] %>%
            xml2::read_html() %>%
            rvest::html_nodes(xpath="//div[@class='slicerItemContainer']") %>%
            rvest::html_attr("aria-label")

        new_labels <- !all(viz_labels %in% names(html_list))

        if(!any(viz_labels %in% names(html_list))){
            warning(
                "There was no overlap in labels. Check to make sure no ",
                "facilities were skipped.")
        }

        if((!new_labels) & (iters == 1)){
            warning("page is not as expected. Please inspect.")
        }

        iters <- iters + 1
    }

    fns <- str_c(sub_dir, "/", names(html_list), ".html")
    
    Map(xml2::write_html, html_list, fns)
    
    iframes <- lapply(str_remove(fns, "/results/raw_files"), function(fn)
        htmltools::tags$iframe(
            src = fn, 
            style="display:block", 
            height="500", width="1200"
        )  
    )
    
    x <- htmltools::tags$html(
        htmltools::tags$body(
            iframes
        )
    )
    
    tf <- tempfile(fileext = ".html")
    
    htmltools::save_html(x, file = tf)
    
    xml2::read_html(tf)
}

pennsylvania_bi_vaccination_restruct  <- function(x){
    
    sub_files <- x %>%
        rvest::html_nodes("iframe") %>%
        rvest::html_attr("src") %>%
        str_replace("\\./", "./results/raw_files/")

    bind_rows(lapply(sub_files, function(f){
        
        fac_name <- str_remove(last(str_split(f, "/")[[1]]), ".html")
    
        sub_html <- xml2::read_html(f)
        
        data_cards <- sub_html %>%
            rvest::html_nodes(xpath="//svg[@class='card']/../../..")
        
        titles <- sub_html %>%
            rvest::html_nodes(xpath="//div[@class='preTextWithEllipsis']") %>%
            rvest::html_text()
        
        res_idx <- min(which(str_detect(titles, "(?i)inmate")))
        staff_idx <- min(which(str_detect(titles, "(?i)staff")))
        
        if(res_idx > staff_idx){
            stop("Scraper is not as expected, please inspect.")
        }
        
        data_cards <- sub_html %>%
            rvest::html_nodes(xpath="//svg[@class='card']/../../..")
        
        card_labs <- sapply(data_cards, function(z){
            rvest::html_attr(rvest::html_nodes(z, "div.visualTitle"), "title")
            }) %>%
            str_replace(" ", ".")
        
        card_group <- rep(c("Residents.", "Staff."), each = length(card_labs)/2)
        
        card_vals <- sapply(data_cards, function(z){
            rvest::html_text(rvest::html_nodes(z, "title"))
            }) %>%
            string_to_clean_numeric()
        
        tibble(
            Name = fac_name,
            measure = str_c(card_group, card_labs),
            value = card_vals
        )
    }))
}

pennsylvania_bi_vaccination_extract <- function(x){
    x %>%
        pivot_wider(names_from = "measure", values_from = "value") %>%
        mutate(Residents.Initiated = Residents.Partial + Residents.Full) %>%
        mutate(Staff.Initiated = Staff.Partial + Staff.Full) %>%
        mutate(Staff.Population = 
                   Staff.Partial + Staff.Full + Staff.Not.Vaccinated) %>%
        select(-ends_with("Not.Vaccinated"), -ends_with("Partial")) %>%
        clean_scraped_df() %>%
        rename(
            Residents.Completed = Residents.Full, Staff.Completed = Staff.Full)
}

#' Scraper class for general PA vaccination data from dashboard
#' 
#' @name pennsylvania_bi_vaccination_scraper
#' @description One page in PAs power BI tool which is dedicated to inmate
#' and staff vaccinations. We scrape each page with relevant data from the PA
#' bi tool with separate scrapers.
#' 
#' \describe{
#'   \item{Facility}{Facility abbreviation}
#'   \item{Partial}{Completed - Initiated}
#'   \item{Full}{Completed}
#' }

pennsylvania_bi_vaccination_scraper <- R6Class(
    "pennsylvania_bi_vaccination_scraper",
    inherit = generic_scraper,
    public = list(
        log = NULL,
        initialize = function(
            log,
            url = "https://www.cor.pa.gov/Pages/COVID-19.aspx",
            id = "pennsylvania_bi_vaccination",
            type = "html",
            state = "PA",
            jurisdiction = "state",
            # pull the JSON data directly from the API
            pull_func = pennsylvania_bi_vaccination_pull,
            # restructuring the data means pulling out the data portion of the 
            restruct_func = pennsylvania_bi_vaccination_restruct,
            # Rename the columns to appropriate database names
            extract_func = pennsylvania_bi_vaccination_extract){
            super$initialize(
                url = url, id = id, pull_func = pull_func, type = type,
                restruct_func = restruct_func, extract_func = extract_func,
                log = log, state = state, jurisdiction = jurisdiction)
        }
    )
)

if(sys.nframe() == 0){
    pennsylvania_bi_vaccination <- pennsylvania_bi_vaccination_scraper$new(log=TRUE)
    pennsylvania_bi_vaccination$raw_data
    pennsylvania_bi_vaccination$pull_raw()
    pennsylvania_bi_vaccination$raw_data
    pennsylvania_bi_vaccination$save_raw()
    pennsylvania_bi_vaccination$restruct_raw()
    pennsylvania_bi_vaccination$restruct_data
    pennsylvania_bi_vaccination$extract_from_raw()
    pennsylvania_bi_vaccination$extract_data
    pennsylvania_bi_vaccination$validate_extract()
    pennsylvania_bi_vaccination$save_extract()
}

