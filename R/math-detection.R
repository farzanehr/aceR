
#' @keywords internal

ace_detection <- function(x, y) {
  if (length(x) == 1) {
    out = c()
    out$pr = NA
    out$dprime = NA
    out$dprime_snodgrass = NA
    out$dprime_wixted = NA
    return (out)  
  }
  rejs = identify_correct_rejections(x, y)
  types = plyr::mapvalues(rejs, warn_missing = FALSE,
    from = c("correct_rejection", "miss", "false_alarm", "hit"), 
    to = c("target", "target", "nontarget", "nontarget"))
  types = na.omit(types)
  num_targets = length(which(types == "target"))
  num_nontargets = length(which(types == "nontarget"))
  num_total = num_targets + num_nontargets
  freq = as.data.frame(t(summary(rejs)))
  cols = names(freq)
  if (!("false_alarm" %in% cols)) freq$false_alarm = 0
  if (!("miss" %in% cols)) freq$miss = 0
  if (!("correct_rejection" %in% cols)) freq$correct_rejection = 0
  if (!("hit" %in% cols)) freq$hit = 0
  out = c()
  if (num_targets > 0) {
    out$correct_rejection_rate = freq$correct_rejection / num_targets
    out$miss_rate = freq$miss / num_targets
  } else {
    out$correct_rejection_rate = NA
    out$miss_rate = NA
  }
  if (num_nontargets > 0) {
    out$false_alarm_rate = freq$false_alarm / num_nontargets
    out$hit_rate = freq$hit / num_nontargets
  } else {
    out$false_alarm_rate = NA
    out$hit_rate = NA
  }
  out$pr = out$hit_rate - out$false_alarm_rate
  out$dprime = qnorm(out$hit_rate) - qnorm(out$false_alarm_rate)
  out$dprime_snodgrass = qnorm(snodgrass_correction(out$hit_rate, num_total)) - qnorm(snodgrass_correction(out$false_alarm_rate, num_total))
  out$dprime_wixted = qnorm(wixted_hit_rate_correction(out$hit_rate, num_targets)) - qnorm(wixted_false_alarm_correction(out$false_alarm_rate, num_nontargets))
  return (out)
}

#' @keywords internal

ace_wm_k <- function(hit, fa, targets) {
  return (targets * (hit - fa))
}

#' @keywords internal

snodgrass_correction <- function(rate, num) {
  return ((rate + 0.50) / (num + 1))
}

#' @keywords internal

wixted_hit_rate_correction <- function(hit_rate, num_targets) {
  if (is.na(hit_rate)) return (NA)
  if (hit_rate == 1) {
    return (1 - (0.5 / num_targets))
  } else {
    return (hit_rate)
  }
}

#' @keywords internal

wixted_false_alarm_correction <- function(false_alarm_rate, num_nontargets) {
  if (is.na(false_alarm_rate)) return (NA)
  if (false_alarm_rate == 0 && !is.na(false_alarm_rate)) {
    return (0 + (0.5 / num_nontargets))
  } else {
    return (false_alarm_rate)
  }
}

#' @keywords internal

identify_correct_rejections <- function(response_window, reaction_time) {
  rws = to_numeric(response_window)
  rts = to_numeric(reaction_time)
  out = c()
  for (i in 1:(length(rts) - 1)) {
    if (is.na(rts[i])) {
      rej = ifelse(rws[i + 1] == rws[i], "correct_rejection", "false_alarm")
    } else {
      rej = ifelse(rws[i + 1] < rws[i], "hit", "miss")
    }
    out = c(out, rej)
  }
  out = as.factor(c(out, NA)) # last trial
  return (out)
}