#' Retrieve immediate children taxa for a given taxon name or ID.
#'
#' This function is different from [downstream()] in that it only
#' collects immediate taxonomic children, while [downstream()]
#' collects taxonomic names down to a specified taxonomic rank, e.g.,
#' getting all species in a family.
#'
#' @export
#' @param x Vector of taxa names (character) or IDs (character or numeric)
#' to query.
#' @param db character; database to query. One or more of `itis`,
#' `ncbi`, `worms`, or `bold`. Note that each taxonomic data
#' source has their own identifiers, so that if you provide the wrong
#' `db` value for the identifier you could get a result, but it will
#' likely be wrong (not what you were expecting). If using ncbi, we recommend
#' getting an API key; see [taxize-authentication]
#' @param rows (numeric) Any number from 1 to infinity. If the default NA, all
#' rows are considered. Note that this parameter is ignored if you pass in a
#' taxonomic id of any of the acceptable classes: tsn. NCBI has a
#' method for this function but rows doesn't work.
#' @param ... Further args passed on to [ritis::hierarchy_down()],
#' [ncbi_children()], [worrms::wm_children()], [bold_children()]
#' See those functions for what parameters can be passed on.
#'
#' @section ncbi:
#' note that with `db = "ncbi"`, we set `ambiguous = TRUE`; that is, children
#' taxa with words like "unclassified", "unknown", "uncultured", "sp." are
#' NOT removed
#' 
#' @section bold:
#' BEWARE: `db="bold"` scrapes the BOLD website, so may be unstable. That is,
#' one day it may work, and the next it may fail. Open an issue if you
#' encounter an error: https://github.com/ropensci/taxize/issues
#'
#' @return A named list of data.frames with the children names of every
#' supplied taxa. You get an NA if there was no match in the database.
#'
#' @examples \dontrun{
#' # Plug in taxonomic IDs
#' children(161994, db = "itis")
#' children(8028, db = "ncbi")
#' ## works with numeric if as character as well
#' children(161994, db = "itis")
#' children(88899, db = "bold")
#' children(as.boldid(88899))
#'
#' # Plug in taxon names
#' children("Salmo", db = 'itis')
#' children("Salmo", db = 'ncbi')
#' children("Salmo", db = 'worms')
#' children("Salmo", db = 'bold')
#'
#' # Plug in IDs
#' (id <- get_wormsid("Platanista"))
#' children(id)
#'
#' # Many taxa
#' sp <- c("Tragia", "Schistocarpha", "Encalypta")
#' children(sp, db = 'itis')
#'
#' # Two data sources
#' (ids <- get_ids("Apis", db = c('ncbi','itis')))
#' children(ids)
#' ## same result
#' children(get_ids("Apis", db = c('ncbi','itis')))
#'
#' # Use the rows parameter
#' children("Poa", db = 'itis')
#' children("Poa", db = 'itis', rows=1)
#'
#' # use curl options
#' res <- children("Poa", db = 'itis', rows=1, verbose = TRUE)
#' }

children <- function(...){
  UseMethod("children")
}

#' @export
#' @rdname children
children.default <- function(x, db = NULL, rows = NA, ...) {
  nstop(db)
  results <- switch(
    db,
    itis = {
      id <- process_children_ids(x, db, get_tsn, rows = rows, ...)
      stats::setNames(children(id, ...), x)
    },

    ncbi = {
      if (all(grepl("^[[:digit:]]*$", x))) {
        id <- x
        class(id) <- "uid"
        stats::setNames(children(id, ...), x)
      } else {
        out <- ncbi_children(name = x, ...)
        structure(out, class = 'children', db = 'ncbi', .Names = x)
      }
    },

    worms = {
      id <- process_children_ids(x, db, get_wormsid, rows = rows, ...)
      stats::setNames(children(id, ...), x)
    },

    bold = {
      id <- process_children_ids(as.character(x), db, get_boldid,
        rows = rows, ...)
      stats::setNames(children(id, ...), x)
    },

    stop("the provided db value was not recognised", call. = FALSE)
  )

  set_output_types(results, x, db)
}

# Ensure that the output types are consistent when searches return nothing
itis_blank <- data.frame(
  parentname = character(0),
  parenttsn  = character(0),
  rankname   = character(0),
  taxonname  = character(0),
  tsn        = character(0),
  stringsAsFactors = FALSE
)
worms_blank <- ncbi_blank <- bold_blank <-
  data.frame(
    childtaxa_id     = character(0),
    childtaxa_name   = character(0),
    childtaxa_rank   = character(0),
    stringsAsFactors = FALSE
  )

set_output_types <- function(x, x_names, db){
  blank_fun <- switch(
    db,
    itis  = function(w) if (nrow(w) == 0 || all(is.na(w))) itis_blank else w,
    ncbi  = function(w) if (nrow(w) == 0 || all(is.na(w))) ncbi_blank else w,
    worms = function(w) if (nrow(w) == 0 || all(is.na(w))) worms_blank else w,
    bold = function(w) if (nrow(w) == 0 || all(is.na(w))) bold_blank else w
  )

  typed_results <- lapply(seq_along(x), function(i) blank_fun(x[[i]]))
  names(typed_results) <- x_names
  attributes(typed_results) <- attributes(x)
  typed_results
}

process_children_ids <- function(input, db, fxn, ...){
  g <- tryCatch(as.numeric(as.character(input)), warning = function(e) e)
  if (inherits(g, "condition")) eval(fxn)(input, ...)
  if (is.numeric(g) || is.character(input) && all(grepl("[[:digit:]]", input))) {
    as_fxn <- switch(db, itis = as.tsn, worms = as.wormsid, bold = as.boldid)
    as_fxn(input, check = FALSE)
  } else {
    eval(fxn)(input, ...)
  }
}

#' @export
#' @rdname children
children.tsn <- function(x, db = NULL, ...) {
  warn_db(list(db = db), "itis")
  fun <- function(y){
    # return NA if NA is supplied
    if (is.na(y)) {
      out <- NA
    } else {
		  out <- ritis::hierarchy_down(y, ...)
    }
  }
  out <- lapply(x, fun)
  names(out) <- x
  class(out) <- 'children'
  attr(out, 'db') <- 'itis'
  return(out)
}

df2dt2tbl <- function(x) {
  tibble::as_tibble(
    data.table::setDF(
      data.table::rbindlist(
        x, use.names = TRUE, fill = TRUE)
    )
  )
}

#' @export
#' @rdname children
children.wormsid <- function(x, db = NULL, ...) {
  warn_db(list(db = db), "worms")
  fun <- function(y){
    # return NA if NA is supplied
    if (is.na(y)) {
      out <- NA
    } else {
      out <- worrms::wm_children(as.numeric(y))
      out <- list(out)
      i <- 1
      while (NROW(out[[length(out)]]) == 50) {
        i <- i + 1
        out[[i]] <- worrms::wm_children(
          as.numeric(y),
          offset = sum(unlist(sapply(out, NROW))))
      }
      out <- df2dt2tbl(out)
      stats::setNames(
        out[names(out) %in% c('AphiaID', 'scientificname', 'rank')],
        c('childtaxa_id', 'childtaxa_name', 'childtaxa_rank')
      )
    }
  }
  out <- lapply(x, fun)
  names(out) <- x
  class(out) <- 'children'
  attr(out, 'db') <- 'worms'
  return(out)
}

#' @export
#' @rdname children
children.ids <- function(x, db = NULL, ...) {
  fun <- function(y, ...){
    # return NA if NA is supplied
    if (is.na(y)) {
      out <- NA
    } else {
      out <- children(y, ...)
    }
    return(out)
  }
  out <- lapply(x, fun)
  class(out) <- 'children_ids'
  return(out)
}

#' @export
#' @rdname children
children.uid <- function(x, db = NULL, ...) {
  warn_db(list(db = db), "uid")
  out <- if (is.na(x)) {
    stats::setNames(list(ncbi_blank), x)
  } else {
    ncbi_children(id = x, ambiguous = TRUE, ...)
  }
  class(out) <- 'children'
  attr(out, 'db') <- 'ncbi'
  return(out)
}

#' @export
#' @rdname children
children.boldid <- function(x, db = NULL, ...) {
  warn_db(list(db = db), "bold")
  out <- if (is.na(x)) {
    stats::setNames(list(bold_blank), x)
  } else {
    bold_children(id = x, ...)
  }
  class(out) <- 'children'
  attr(out, 'db') <- 'bold'
  return(out)
}
