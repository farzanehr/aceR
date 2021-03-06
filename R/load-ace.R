
#' Reads raw ace data from a file.
#'
#' Reads, parses, and converts an ACE csv or xls into an R \code{\link{data.frame}}.
#'
#' @export
#' @param file The name of the file which the data is to be read from.
#' @return Returns the file's content as an R \code{\link{data.frame}}.

load_ace_file <- function(file) {
  # read raw csv file
  if (is_filtered(file)) {
    return (load_ace_filtered_file(file))
  }
  if (is_excel(file)) {
    raw_dat = load_excel(file)
  } 
  if (is_pulvinar(file)) { # TODO: can we get a common phrase in all pulvinar export filenames? 
    raw_dat = load_csv(file, pulvinar = T)
    return (transform_pulvinar(file, raw_dat))
  } else {
    raw_dat = load_csv(file)
    raw_dat = breakup_by_user(raw_dat)
  }
  if (is.vector(raw_dat)) {
    out = data.frame()
    dfs = names(raw_dat)
    for (i in 1:length(dfs)) {
      name = paste(file, dfs[i], sep = "-")
      df = attempt_transform(name, raw_dat[[i]])
      out = plyr::rbind.fill(out, df)
    }
    return (out)
  } else {
    return (attempt_transform(file, raw_dat))
  }
}

#' @keywords internal

load_ace_filtered_file <- function(file) {
  if (is_excel(file)) {
    df = openxlsx::read.xlsx(file, sheet = 1)
  } else {
    df = read.csv(file, header = TRUE, sep = ",")
  }
  cols = names(df)
  pid_col = cols[grep("id", cols)[1]]
  names(df)[names(df) == pid_col] = COL_PID
  names(df) = sapply(names(df), function(x) to_snake_case(x))
  df = standardize_ace_column_names(df)
  df[, COL_PID] = as.character(df[, COL_PID])
  df$file = file
  df$module = identify_module(file)
  df = standardize_ace_values(df)
  df = replace_nas(df, "")
  df[, COL_TIME] = df$time_gameplayed_utc
  df[, COL_CONDITION] = df$details
  df[, COL_BID] = paste(df[, COL_PID], df[, COL_TIME])
  by_block = add_block_half(subset_by_col(df, "bid"))
  out = flatten_df_list(by_block)
  return (out)
}

#' @keywords internal

add_block_half = function(x) {
  df_list = lapply(x, function(x) {
    df = x
    df[, COL_BLOCK_HALF] =  plyr::mapvalues(make_half_seq(nrow(x)), from = c(1, 2), to = c("first_half", "second_half"))
    return(df)
  })
  return (df_list)
}

#' @keywords internal

is_filtered <- function (filename) {
  return (grepl("filtered", filename))
}

#' @keywords internal

is_pulvinar <- function (filename) {
  return (grepl("pulvinar", filename, ignore.case = T))
}

#' @keywords internal

attempt_transform <- function(file, raw_dat) {
  # transform data to data frame
  df = tryCatch ({
    transformed = transform_raw(file, raw_dat)
    # test if data is usable
    st = paste(transformed, collapse = "")
    if (grepl("}", st)) {
      warning(file, " contains invalid data ")
      return (data.frame())
    }
    # technically a 'valid' file, BUT contains no data.
    if (nrow(transformed) < 2) {
      warning(file, "is valid, but contains no data!")
      return (data.frame())
    }
    return (transformed)
  }, error = function(e) {
    warning("unable to load ", file)
    return (data.frame())
  })
  return (df)
}

#' @keywords internal

transform_raw <- function (file, raw_dat) {
  if (nrow(raw_dat) == 0) return (data.frame())
  # standardize raw data
  raw_dat = standardize_raw_csv_data(raw_dat)
  # remove nondata rows
  dat = remove_nondata_rows(raw_dat)
  # move grouping rows into column
  dat = transform_grouping_rows(dat)
  # standardize session info
  dat = standardize_session_info(dat)
  # transform session info into columns
  dat = transform_session_info(dat)
  # parse subsections
  dat = parse_subsections(dat)
  # standardize output
  names(dat) = standardize_names(dat)
  dat$file = file
  dat$module = identify_module(file)
  dat = standardize_ace_column_names(dat)
  cols = names(dat)
  if (!(COL_TIME) %in% cols) {
    # make "time" column from subid & filename if file doesn't contain time
    dat[, COL_TIME] = paste(dat$file, dat[, COL_SUB_ID], sep = ".")
  } else {
    dat[, COL_TIME] = as.vector(dat[, COL_TIME])
  }
  if (COL_PID %in% cols) {
    # make block id from pid & time
    dat[, COL_BID] = paste(dat[, COL_PID], dat[, COL_TIME], sep = ".")
  } else {
    # make block id from file name & time if file doesn't contain PID
    dat[, COL_BID] = paste(dat$file, dat[, COL_TIME], sep = ".")
    dat[, COL_PID] = guess_pid(dat$file)
  }
  dat = standardize_ace_values(dat)
  return (dat)
}

#' @keywords internal

transform_pulvinar <- function (file, dat) {
  if (nrow(dat) == 0) return (data.frame())
  # standardize output
  names(dat) = standardize_names(dat, pulvinar = T)
  dat$file = file
  dat$module = identify_module(file)
  dat = standardize_ace_column_names(dat)
  # parse subsections, currently SLOW version
  dat = parse_subsections_pulvinar(dat)
  # make block id from pid & time
  dat[, COL_BID] = paste(dat[, COL_PID], dat[, COL_TIME], sep = ".")
  dat = standardize_ace_values(dat)
  # was flagging sets where pid and name don't match--this is being somewhat handled in parse_subsections_pulvinar
  # dat = clean_invalid_subs(dat)
  return (dat)
}

#' @keywords internal

clean_invalid_subs <- function(dat) {
  # leaving this function here for now in case it becomes necessary later.
  # currently this function is made obsolete by remove_nondata_rows_pulvinar() and the rejection criterion of only matching PID-names in parse_subsections_pulvinar()
  # using data.table internally for speed & reduction of with() calls
  # using bare colnames here because we can assume these cols will exist under this name and data.table doesn't like quoted varnames
  # repairing those with valid but not matching pid_num and name
  dat = as.data.table(tidyr::separate_(dat, COL_PID, into = c("pid_stem", "pid_num"), sep = 11, remove = F))
  dat_good = dat[pid_num == name]
  dat_bad = dat[pid_num != name]
  subs = unique(dat_bad[[COL_PID]])
  for (sub in subs) {
    this_name = unique(dat_bad[pid == sub, name])
    # if pid_num already exists as matching data, change this pid_num to name
    if (dim(dat_good[pid_num == this_name])[1] > 0) {
      dat_bad[, pid_num := ifelse(pid == sub, name, pid_num)]
      dat_bad[, pid := ifelse(pid == sub, paste0(pid_stem, name), pid)]
    } else if (dim(dat_good[name == this_name])[1] > 0) {
      # else if name already exists as matching data, change this name to pid_num
      dat_bad[, name := ifelse(pid == sub, pid_num, name)]
    }
  }
  clean = rbind(dat_good, dat_bad)
  return(as.data.frame(clean[, c("pid_stem", "pid_num") := NULL]))
}

#' @keywords internal

guess_pid <- function(x) {
  file = basename(x)
  # maybe_pid = stringr::str_extract(file, "^[a-zA-Z0-9]*")
  maybe_pid = unique(na.omit(as.numeric(unlist(strsplit(unlist(file), "[^0-9]+")))))[1]
  return (maybe_pid)
}