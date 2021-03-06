#' Get a dataframe of n lagged columns of a feature (to be deprecated)
#' @param vec A vector of data
#' @param lags An integer >= 0
#' @param name A character string
#'
#' @examples
#' feature <- runif(10)
#' lagged_cols <- vaep_features_lag(feature, 3, "lagged_feature_")
#' head(lagged_cols)
#'
#' @author Robert Hickman
#' @export vaep_features_lag

vaep_features_lag <- function(vec, lags, name) {
  x <- lapply(0:lags, lag, x = vec) %>% do.call(cbind, .) %>% as.data.frame()
  #replace names
  names(x) <- paste0(name, 0:lags)
  return(x)
}

#' Get the features of each match event (and preceeding events) from a spadl format
#' @param spadl A dataframe of event data in spadl format
#'
#'
#' @author Robert Hickman
#' @export vaep_get_features

vaep_get_features <- function(spadl) {
  #switch back play directions to 0 = own goal
  spadl[!spadl$home_team, grep("_x$", names(spadl))] <- Rteta::spadl_field_length - spadl[!spadl$home_team, grep("_x$", names(spadl))]
  spadl[!spadl$home_team, grep("_y$", names(spadl))] <- Rteta::spadl_field_width - spadl[!spadl$home_team, grep("_y$", names(spadl))]

  #find the type of action n, n-1, n-2
  #uses the lagging function
  type_ids <- Rteta::vaep_features_lag(spadl$type_id, 2, "type_id_a")

  #find the type name and one hot encode types for n, n-1, n-2 action
  types_onehot <- do.call(
    cbind,
    purrr::map2(Rteta::spadl_type_ids$type_id, Rteta::spadl_type_ids$type_name, function(i, a, cols) {
      df <- as.data.frame(cols == i)
      names(df) <- gsub("_id_", paste0("_", a, "_"), names(df))
      return(df)
    }, cols = type_ids)
  )

  #do the same as above for bodyparts
  bodypart_ids <- Rteta::vaep_features_lag(spadl$bodypart_id, 2, "bodypart_id_a")

  bodypart_onehot <- do.call(
    cbind,
    purrr::map2(Rteta::spadl_bodypart_ids$bodypart_id, Rteta::spadl_bodypart_ids$bodypart_name, function(i, a, cols) {
      df <- as.data.frame(cols == i)
      names(df) <- gsub("_id_", paste0("_", a, "_"), names(df))
      return(df)
    }, cols = bodypart_ids)
  )

  #and for the result of actions
  result_ids <- Rteta::vaep_features_lag(spadl$result_id, 2, "result_id_a")

  result_onehot <- do.call(
    cbind,
    purrr::map2(Rteta::spadl_result_ids$result_id, Rteta::spadl_result_ids$result_name, function(i, a, cols) {
      df <- as.data.frame(cols == i)
      names(df) <- gsub("_id_", paste0("_", a, "_"), names(df))
      return(df)
    }, cols = result_ids)
  )

  #find time related signals n, n-1, n-2
  period_ids <- Rteta::vaep_features_lag(spadl$period_id, 2, "period_id_a")

  halves <- split(spadl,spadl$period_id)
  period_time_seconds <- lapply(halves, function(h) vaep_features_lag(h$time_seconds, 2, "time_seconds_a"))
  period_time_seconds <- do.call(rbind, period_time_seconds)

  half_ends <- lapply(halves, function(h) h[which.max(h$time_seconds),])
  half_ends <- do.call(rbind, half_ends)[c("time_seconds", "period_id")]
  half_ends$period_id <- half_ends$period_id + 1
  half_ends <- rbind(data.frame(time_seconds = 0, period_id = 1), half_ends)

  #have a total match time and a time since half start parameters
  total_time_seconds <- period_time_seconds
  total_time_seconds$period_id <- spadl$period_id
  total_time_seconds <- merge(total_time_seconds, half_ends, by = "period_id")

  total_time_seconds$time_seconds_overall_a0 = total_time_seconds$time_seconds_a0 + total_time_seconds$time_seconds
  total_time_seconds$time_seconds_overall_a1 = total_time_seconds$time_seconds_a1 + total_time_seconds$time_seconds
  total_time_seconds$time_seconds_overall_a2 = total_time_seconds$time_seconds_a2 + total_time_seconds$time_seconds

  total_time_seconds <- total_time_seconds[grep("a[0-9]$", names(total_time_seconds))]
  total_time_seconds$time_delta_1 <- total_time_seconds$time_seconds_overall_a0 - lag(total_time_seconds$time_seconds_overall_a0)
  total_time_seconds$time_delta_2 <- total_time_seconds$time_seconds_overall_a0 - lag(total_time_seconds$time_seconds_overall_a0, n = 2)

  #same but for the start and end positions of actions
  start_xs <- Rteta::vaep_features_lag(spadl$start_x, 2, "start_x_a")
  start_ys <- Rteta::vaep_features_lag(spadl$start_y, 2, "start_y_a")
  end_xs <- Rteta::vaep_features_lag(spadl$end_x, 2, "end_x_a")
  end_ys <- Rteta::vaep_features_lag(spadl$end_y, 2, "end_y_a")

  #calculate the change in position an action produces
  delta_x <- end_xs - start_xs
  names(delta_x) <- gsub("^end_", "d", names(delta_x))
  delta_y <- end_ys - start_ys
  names(delta_y) <- gsub("^end_", "d", names(delta_y))

  movement <- sqrt(delta_x^2 + delta_y ^ 2)
  names(movement) <- gsub("^dx_", "movement_", names(movement))

  #calculate the start and end distance to goal of an action
  start_goal_distance <- sqrt(
    (Rteta::spadl_field_length - spadl$start_x)^2 +
      ((Rteta::spadl_field_width / 2) - spadl$start_y)^2
  )
  end_goal_distance <- sqrt(
    (Rteta::spadl_field_length - spadl$end_x)^2 +
      ((Rteta::spadl_field_width / 2) - spadl$end_y)^2
  )
  start_goal_dist <- Rteta::vaep_features_lag(start_goal_distance, 2, "start_dist_to_goal_a")
  end_goal_dist <- Rteta::vaep_features_lag(end_goal_distance, 2, "end_dist_to_goal_a")

  #calculate the start and end angles to goal of an action
  start_goal_angles <- abs(atan(((Rteta::spadl_field_width / 2) - spadl$start_y) / (Rteta::spadl_field_length - spadl$start_x)))
  end_goal_angles <- abs(atan(((Rteta::spadl_field_width / 2) - spadl$end_y) / (Rteta::spadl_field_length - spadl$end_x)))
  start_goal_angles <- Rteta::vaep_features_lag(start_goal_angles, 2, "start_angle_to_goal_a")
  end_goal_angles <- Rteta::vaep_features_lag(end_goal_angles, 2, "end_angle_to_goal_a")

  dx <- (Rteta::vaep_features_lag(spadl$end_x, 2, "dx_a0") - spadl$start_x)[2:3]
  dy <- (Rteta::vaep_features_lag(spadl$end_y, 2, "dy_a0") - spadl$start_y)[2:3]
  move <- sqrt(dx^2 + dy^2)
  names(move) <- c("mov_a01", "mov_a02")

  #get the goals for and goals against of the team of any action when that action is taken
  goal_context <- Rteta::get_context_goals(spadl)

  #bind everything together
  features0 <- cbind(
    start_xs, start_ys, end_xs, end_ys,
    start_goal_dist, end_goal_dist,
    start_goal_angles, end_goal_angles,
    delta_x, delta_y, movement,
    dx, dy, move,
    total_time_seconds
  )
  features2 <- cbind(
    type_ids, types_onehot, bodypart_ids, bodypart_onehot, result_ids, result_onehot, goal_context
  )

  #socceraction stores these as separate files in h5df but see no reason not to create 1 flat df
  all_features <- cbind(features0, features2)
}

#' Get the goal context of a spadl data frame
#' @param spadl A dataframe of event data in spadl format
#'
#'
#' @author Robert Hickman
#' @export get_context_goals

get_context_goals <- function(spadl) {
  teama <- spadl$home_team
  teamb <- !teama

  #find goals for each team
  teama_goals <- (teama & grepl("^shot", spadl$type_name) & spadl$result_name == "success") | (teamb & grepl("^shot", spadl$type_name) & spadl$result_name == "owngoal")
  teamb_goals <- (teamb & grepl("^shot", spadl$type_name) & spadl$result_name == "success") | (teama & grepl("^shot", spadl$type_name) & spadl$result_name == "owngoal")

  #find total goals for each team
  goalsfor <- lag(cumsum(teama_goals) * teama + cumsum(teamb_goals) * teamb, default = 0)
  goalsagainst <- lag(cumsum(teama_goals) * teamb + cumsum(teamb_goals) * teama, default = 0)

  df <- data.frame(
    goalscore_team = goalsfor,
    goalscore_opponent = goalsagainst,
    goalscore_diff = goalsfor - goalsagainst)

  return(df)
}

