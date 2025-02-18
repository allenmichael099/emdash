#' The application server-side
#' 
#' @param input,output,session Internal parameters for {shiny}. 
#'     DO NOT REMOVE.
#' @noRd
app_server <- function( input, output, session ) {
  # List the first level callModules here
  

  # prepare data ------------------------------------------------------------
  cons <- connect_stage_collections(url = getOption('emdash.mongo_url'))  
  data_r <- callModule(mod_load_data_server, "load_data_ui", cons)
  
  # Side bar ----------------------------------------------------------------
  
  # Dashboard ---------------------------------------------------------------
  # Dashboard - boxes - start ----------
  callModule(
    mod_value_box_server,
    "value_box_ui_unique_users",
    value = paste0(nrow(data_r$participants),
                   " (+", sum(data_r$participants$update_ts == Sys.Date(), na.rm = T), ")"),
    subtitle = "unique users (new today)",
    icon = icon("users")
  )
  callModule(
    mod_value_box_server,
    "value_box_ui_active_users_today",
    value = sum(data_r$participants$n_trips_today != 0, na.rm = T),
    subtitle = "active users today",
    icon = icon("walking")
  )
  callModule(
    mod_value_box_server,
    "value_box_ui_total_trips",
    value = paste0(sum(data_r$participants$n_trips, na.rm = T), 
                   " (+", sum(data_r$participants$n_trips_today, na.rm = T), ")"),
    subtitle = "trips total (new today)",
    icon = icon("route")
  )
  callModule(
    mod_value_box_server,
    "value_box_ui_total_days",
    value = difftime(Sys.Date() ,as.Date(min(data_r$participants$update_ts)), units = "days"),
    subtitle = sprintf("days since the first user\n(%s to %s)", 
                       as.Date(min(data_r$participants$update_ts)), Sys.Date()),
    icon = icon("calendar-plus")
  )
  
  # Dashboard - boxes - end ----------
  
  # Dashboard - plots - start ----------
  callModule(
    mod_ggplotly_server,
    "ggplotly_ui_signup_trend",
    utils_plot_signup_trend(data_r$participants)
  )
  callModule(
    mod_ggplotly_server,
    "ggplotly_ui_trip_trend",
    utils_plot_trip_trend(data_r$trips)
  )
  callModule(
    mod_ggplotly_server,
    "ggplotly_ui_participation_period",
    utils_plot_participation_period(data_r$participants)
  )
  callModule(
    mod_ggplotly_server,
    "ggplotly_ui_branch",
    utils_plot_branch(data_r$participants)
  )
  callModule(
    mod_ggplotly_server,
    "ggplotly_ui_platform",
    utils_plot_platform(data_r$participants)
  )

  # Dashboard - plots - end ----------
  # Tables ------------------------------------------------------------------
  data_esquisse <- reactiveValues(data = data.frame(), name = "data_esquisse")
  
  # These are the column names we want to change
  originalColumnNames <- c("user_id", 
                           "update_ts",
                           "client", 
                           "curr_platform",
                           "n_trips",
                           "n_trips_today", 
                           "n_active_days", 
                           "first_trip_local_datetime", 
                           "last_trip_local_datetime", 
                           "n_days", 
                           "first_get_call", 
                           "last_get_call", 
                           "first_put_call", 
                           "last_put_call", 
                           "first_diary_call", 
                           "last_diary_call")
  
  # Human friendly names to set for the columns
  newColumnNames <- c('user id',
                      'last profile update',
                      'UI channel',
                      'android/iOS',
                      'Total trips',
                      'Trips today',
                      'Number of days with at least one trip',
                      'First trip date',
                      'Last trip date',
                      'Number of days since app install',
                      'first app communication',
                      'last app communication',
                      'first data upload', 
                      'last data upload',
                      'first app launch',
                      'last app launch')
  
  
  observeEvent(input$tabs, { 
    if (input$tabs  == "participants") {
      data_esquisse$data <- 
        data_r$participants %>%
        drop_list_columns() %>%
        setnames(originalColumnNames,newColumnNames)
    }
    if (input$tabs == "trips") {
      data_esquisse$data <- 
        data_r$trips %>%
        drop_list_columns() %>%
        sf::st_drop_geometry()
    }
  })
  
  # INTERACTIVE PLOT PANEL
  callModule(
    esquisse::esquisserServer,
    "esquisse", 
    data = data_esquisse
  )
  
  # DATA TABS
  # 
  # use these to generate lists of columns to inform which columns to remove
  # data_r$participants %>% colnames() %>% dput()
  # data_r$trips %>% colnames() %>% dput()

  
  cols_to_remove_from_participts_table <- c("first_trip_datetime", 
                                              "last_trip_datetime")
  cols_to_remove_from_trips_table <- c("start_fmt_time0", "start_local_dt_timezone", "start_fmt_time",
                                       "end_fmt_time0", "end_local_dt_timezone", "end_fmt_time", 
                                       "end_loc_coordinates", "start_loc_coordinates", 
                                       "duration", "distance", "geometry", "source")
  
  observeEvent(data_r$click, {
    callModule(mod_DT_server, "DT_ui_participants", 
               data = data_r$participants %>%
                 dplyr::select(-dplyr::any_of(cols_to_remove_from_participts_table)) %>%
                 setnames(originalColumnNames,newColumnNames)
               )
    callModule(mod_DT_server, "DT_ui_trips", 
               data = data_r$trips %>%
                 dplyr::select(-dplyr::any_of(cols_to_remove_from_trips_table)) %>%
                 sf::st_drop_geometry())
  })
  
 
  
  # Maps --------------------------------------------------------------------
  
  # these lists of columns in trips_with_trajectories can inform  
  # 1) which columns to remove in the map filter
  # 2) which columns to remove to pass to the map and show up in the map popups

  # data_r$trips_with_trajectories %>% colnames() %>% dput()
  
  cols_to_include_in_map_filter <- reactive({
    data_r$trips_with_trajectories %>%
    colnames() %>%
    # specify columns to remove here
    setdiff(c("start_fmt_time0", "start_local_dt_timezone", "start_local_time", 
              "end_fmt_time0", "end_local_dt_timezone", "end_local_time", 
              "end_loc_coordinates", "start_loc_coordinates", "duration", "distance", 
              "location_points", "source"))
    })
    
  filtered_trips <- 
    callModule(
      module = esquisse::filterDF,
      id = "filtering",
      data_table = reactive(anonymize_uuid_if_required(data_r$trips_with_trajectories)),
      data_name = reactive("data"),
      data_vars = cols_to_include_in_map_filter, # the map filter uses start_fmt_time and end_fmt_time (UTC time)
      drop_ids = FALSE
    )
  
  cols_to_remove_from_map_popup <- c("start_fmt_time0", "start_local_dt_timezone", "start_fmt_time",
                                     "end_fmt_time0", "end_local_dt_timezone", "end_fmt_time",
                                     "end_loc_coordinates", "start_loc_coordinates", 
                                     "duration", "distance", "location_points")
  
  observeEvent(filtered_trips$data_filtered(), {
    callModule(
      mod_mapview_server,
      "mapview_trips",
      data_sf = filtered_trips$data_filtered() %>% 
        dplyr::select(-dplyr::any_of(cols_to_remove_from_map_popup))
    )
  })
  
  # On exit -----------------------------------------------------------------
  session$onSessionEnded(function() {
    message("disconnecting from the emission collections..")
    lapply(cons, function(.x) {
      .x$disconnect()
    })
  })
  
}


