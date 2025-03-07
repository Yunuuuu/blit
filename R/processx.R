# Used to the working directory, then this method call `system2` to invoke the
# command.
#' @param shell For windows, a string of "cmd" or "powershell", for others, a
#' string of "sh" or "bash".
#' @importFrom rlang caller_call
#' @keywords internal
#' @noRd
processx_command <- function(command, help, shell = NULL,
                             stdout = TRUE, stderr = TRUE, stdin = NULL,
                             stdout_callback = NULL, stderr_callback = NULL,
                             verbose = TRUE, call = caller_call()) {
    assert_s3_class(command, "command", call = call)
    assert_string(stdin, allow_empty = FALSE, allow_null = TRUE, call = call)
    assert_bool(verbose, call = call)

    if (!is.null(stdout_callback)) {
        stdout_callback <- rlang::as_function(stdout_callback, call = call)
    }
    if (!is.null(stderr_callback)) {
        stderr_callback <- rlang::as_function(stderr_callback, call = call)
    }

    # for help document, we only display the last one
    if (help) {
        command$command_series <- utils::tail(command$command_series, 1L)
    }

    # build the command content script
    content <- lapply(.subset2(command, "command_series"), function(cmd) {
        o <- cmd$build_command(help = help, verbose = verbose)
        paste(o, collapse = " ")
    })

    content <- Reduce(function(x, y) c(paste(x, "|"), y), content)

    # prepare the command -----------------------
    script <- tempfile(pkg_nm())
    if (.Platform$OS.type == "windows") {
        # https://stackoverflow.com/questions/605686/how-to-write-a-multiline-command
        # for cmd "^"
        # for powershell "`"
        cmd <- shell %||% "cmd"
        # content <- c(switch(cmd,
        #     cmd = sprintf("del /F %s", shQuote(script, "cmd")),
        #     powershell = sprintf("Remove-Item -Force -Path '%s'", script)
        # ), content)
        arg <- switch(cmd,
            cmd = "/C",
            powershell = c("-ExecutionPolicy", "Bypass", "-File")
        )
        cmd <- paste(cmd, "exe", sep = ".")
    } else {
        # content <- c(sprintf("rm -f '%s'", script), content)
        cmd <- shell %||% "sh" # or "bash"
        arg <- NULL
    }

    # write the content to the script ----------
    writeLines(content, script, sep = "\n")
    # ensure file has execute permission
    if (file.access(script, mode = 1L) != 0L) {
        Sys.chmod(script, "555")
    }

    # setting environment variables -------------
    if (length(envvar <- .subset2(command, "envvar"))) {
        if (verbose) {
            cli::cli_inform("Environment Variables: {.field {names(envvar)}}")
        }
        envvar <- c("current", unlist(envvar, recursive = FALSE))
    } else {
        envvar <- NULL
    }

    # set working directory ---------------------
    if (!is.null(wd <- .subset2(command, "wd"))) {
        if (!dir.exists(wd) &&
            !dir.create(wd, showWarnings = FALSE)) {
            cli::cli_abort(
                "Cannot create working directory {.path {wd}}"
            )
        }
        if (verbose) {
            cli::cli_inform("Working Directory: {.path {wd}")
        }
    }

    if (verbose) {
        cli::cli_text(
            "Running command: {.field {paste(content, collapse = ' ')}}"
        )
        cli::cat_line()
    }

    cleaned <- lapply(.subset2(command, "command_series"), function(cmd) {
        out <- cmd$get_cleaned()
        cmd$reset_cleaned()
        out
    })
    cleaned <- unlist(cleaned, FALSE, FALSE)
    cleanup <- function() {
        rlang::try_fetch(
            file.remove(script),
            error = function(cnd) cli::cli_warn(conditionMessage(cnd))
        )
        for (quo in cleaned) {
            rlang::try_fetch(
                rlang::eval_tidy(quo),
                error = function(cnd) cli::cli_warn(conditionMessage(cnd))
            )
        }
    }

    # execute the command ----------------------
    BlitProcess$new(
        cmd, c(arg, script),
        wd = wd,
        env = envvar,
        stdout = stdout,
        stderr = stderr,
        stdin = stdin,
        .blit_stdout_callback = stdout_callback,
        .blit_stderr_callback = stderr_callback,
        .blit_cleanup = cleanup,
        cleanup_tree = TRUE
    )
}

#' @keywords internal
BlitProcess <- R6Class(
    "BlitProcess",
    inherit = processx::process,
    public = list(
        initialize = function(..., stdout, stderr,
                              .blit_stdout_callback,
                              .blit_stderr_callback,
                              .blit_cleanup = NULL) {
            private$.blit_stdout <- stdout
            private$.blit_stdout_callback <- .blit_stdout_callback
            private$.blit_stderr <- stderr
            private$.blit_stderr_callback <- .blit_stderr_callback

            # translate the stdout and stderr from `blit` into `processx`
            if (identical(stdout, "") || is.null(stdout) ||
                identical(stdout, "|")) {

            } else if (isFALSE(stdout)) {
                stdout <- NULL
            } else if (isTRUE(stdout) || inherits(stdout, "connection")) {
                # we need echo the stdout
                stdout <- "|"
            } else if (!is.null(stdout_callback)) {
                stdout <- "|"
            }

            if (identical(stderr, "") || is.null(stderr) ||
                identical(stderr, "|")) {

            } else if (isFALSE(stderr)) {
                stderr <- NULL
            } else if (is.null(stderr)) {
                stderr <- "2>&1"
            } else if (isTRUE(stderr) || inherits(stderr, "connection")) {
                stderr <- "|"
            } else if (!is.null(stderr_callback)) {
                stderr <- "|"
            }
            super$initialize(..., stdout = stdout, stderr = stderr)
            private$.blit_cleanup <- .blit_cleanup
        },
        .blit_wait_with_interrupt = function(timeout = NULL, spinner = FALSE) {
            out <- rlang::try_fetch(
                private$.blit_wait(timeout, spinner),
                interrupt = function(cnd) {
                    rlang::try_fetch(private$.blit_kill(),
                        error = function(e) NULL
                    )
                    private$.blit_complete()
                    cli::cli_warn("System command interrupted",
                        class = "system_command_interrupt"
                    )
                    invokeRestart("abort")
                }
            )
            if (private$.blit_timeout) {
                cli::cli_warn("System command timed out",
                    class = "system_command_timeout"
                )
            }
            out
        },
        .blit_active_and_collect = function(timeout = NULL, spinner = FALSE,
                                            start_time = self$get_start_time()) {
            if (out <- self$is_alive()) {
                # Timeout? Maybe finished by now...
                if (!is.null(timeout) &&
                    is.finite(timeout) &&
                    Sys.time() - start_time > timeout) {
                    private$.blit_kill(close_connections = FALSE)
                    private$.blit_timeout <- TRUE
                    return(FALSE)
                }
                # Otherwise just poll for 200ms, or less if a timeout is sooner.
                # We cannot poll until the end, even if there is not spinner,
                # because RStudio does not send a SIGINT to the R process,
                # so interruption does not work.
                if (!is.null(timeout) && is.finite(timeout)) {
                    remains <- timeout - (Sys.time() - start_time)
                    remains <- max(0, as.integer(as.numeric(remains) * 1000))
                    if (spinner) remains <- min(remains, 200)
                } else {
                    remains <- 200
                }
                polled <- self$poll_io(remains)

                # If output/error, then collect it
                if (any(polled == "ready")) {
                    private$.blit_collect_stdout()
                    private$.blit_collect_stderr()
                }
            }
            out
        }
    ),
    private = list(
        .blit_timeout = FALSE,
        .blit_wait = function(timeout = NULL, spinner = FALSE) {
            ## We make sure that the process is eliminated
            on.exit(private$.blit_kill(), add = TRUE)
            on.exit(private$.blit_complete(), add = TRUE)
            if (self$has_output_connection()) {
                private$.blit_stdout_prepare()
            }
            if (self$has_error_connection()) {
                private$.blit_stderr_prepare()
            }
            if (spinner) spin <- new_spin()
            start_time <- self$get_start_time()

            while (self$.blit_active_and_collect(timeout, spinner, start_time)) {
                if (spinner) spin()
            }
            super$wait()
            if (spinner) cat("\r \r")
            self$get_exit_status()
        },
        .blit_kill = function(close_connections = TRUE) {
            self$kill(close_connections = close_connections)
            if (private$cleanup_tree) {
                self$kill_tree(close_connections = close_connections)
            }
        },
        .blit_complete = function() {
            private$.blit_complete_collect()
            private$.blit_complete_cleanup()
        },
        .blit_complete_cleanup = function() {
            if (!is.null(private$.blit_cleanup)) {
                private$.blit_cleanup()
                private$.blit_cleanup <- NULL
            }
        },
        .blit_complete_collect = function() {
            if (self$has_output_connection()) {
                while (self$is_incomplete_output()) {
                    self$poll_io(-1)
                    if (!private$.blit_collect_stdout()) break
                }
                # ensure the stdout_remain added
                if (!is.null(line <- private$.blit_stdout_remain) &&
                    nzchar(line)) {
                    if (!is.null(private$.blit_stdout_callback)) {
                        line <- private$.blit_stdout_callback(line, self)
                    }
                    private$.blit_stdout_push(line)
                }
                if (!is.null(private$.blit_stdout_done)) {
                    private$.blit_stdout_done()
                    private$.blit_stdout_done <- NULL
                }
            }
            if (self$has_error_connection()) {
                while (self$is_incomplete_error()) {
                    self$poll_io(-1)
                    if (!private$.blit_collect_stderr()) break
                }
                # ensure the stderrr_remain added
                if (!is.null(line <- private$.blit_stderr_remain) &&
                    nzchar(line)) {
                    if (!is.null(private$.blit_stderr_callback)) {
                        line <- private$.blit_stderr_callback(line, self)
                    }
                    private$.blit_stderr_push(line)
                }
                if (!is.null(private$.blit_stderr_done)) {
                    private$.blit_stderr_done()
                    private$.blit_stderr_done <- NULL
                }
            }
            private$.blit_stdout_con <- NULL
            private$.blit_stdout_push <- NULL
            private$.blit_stdout_remain <- NULL
            private$.blit_stderr_con <- NULL
            private$.blit_stderr_push <- NULL
            private$.blit_stderr_remain <- NULL
        },
        .blit_collect_stdout = function(n_stdout = 2000) {
            ok <- FALSE
            if (self$has_output_connection()) {
                newout <- rlang::try_fetch(
                    {
                        o <- self$read_output(n_stdout)
                        ok <- TRUE
                        o
                    },
                    error = function(e) NULL
                )
                if (length(newout) && nzchar(newout)) {
                    newout <- paste0(private$.blit_stdout_remain, newout)
                    private$.blit_stdout_remain <- ""
                    lines <- .subset2(strsplit(newout, "\r?\n"), 1L)
                    nc <- nchar(newout)
                    if (substring(newout, nc, nc) != "\n") {
                        private$.blit_stdout_remain <- utils::tail(lines, 1)
                        lines <- utils::head(lines, -1)
                    }
                    if (!is.null(private$.blit_stdout_callback)) {
                        lines <- private$.blit_stdout_callback(lines, self)
                    }
                    private$.blit_stdout_push(lines)
                }
            }
            ok
        },
        .blit_stdout_prepare = function(stdout = private$.blit_stdout) {
            if (isTRUE(stdout)) {
                private$.blit_stdout_push <- function(text) {
                    cat(text, sep = "\n")
                }
            } else {
                private$.blit_stdout_con <- file(stdout, open = "w+b")
                private$.blit_stdout_push <- function(text) {
                    cat(text, file = private$.blit_stdout_con, sep = "\n")
                }
                private$.blit_stdout_done <- function() {
                    close(private$.blit_stdout_con)
                }
            }
            private$.blit_stdout_remain <- ""
        },
        .blit_stdout_con = NULL,
        .blit_stdout_push = NULL,
        .blit_stdout_done = NULL,
        .blit_stdout_remain = NULL,
        .blit_stdout = NULL,
        .blit_stdout_callback = NULL,
        .blit_collect_stderr = function(n_stderr = 2000) {
            ok <- FALSE
            if (self$has_error_connection()) {
                newerr <- rlang::try_fetch(
                    {
                        o <- self$read_error(n_stderr)
                        ok <- TRUE
                        o
                    },
                    error = function(e) NULL
                )
                if (length(newerr) && nzchar(newerr)) {
                    newerr <- paste0(private$.blit_stderr_remain, newerr)
                    private$.blit_stderr_remain <- ""
                    lines <- .subset2(strsplit(newerr, "\r?\n"), 1L)
                    nc <- nchar(newerr)
                    if (substring(newerr, nc, nc) != "\n") {
                        private$.blit_stderr_remain <- utils::tail(lines, 1)
                        lines <- utils::head(lines, -1)
                    }
                    if (!is.null(private$.blit_stderr_callback)) {
                        lines <- private$.blit_stderr_callback(lines, self)
                    }
                    private$.blit_stderr_push(lines)
                }
            }
            ok
        },
        .blit_stderr_prepare = function(stderr = private$.blit_stderr) {
            if (isTRUE(stderr)) {
                private$.blit_stderr_push <- function(text) {
                    cat(cli::col_red(text), sep = "\n")
                }
                private$.blit_stderr_done <- function() NULL
            } else {
                private$.blit_stderr_con <- file(stderr, open = "w+b")
                private$.blit_stderr_push <- function(text) {
                    cat(text, file = private$.blit_stderr_con, sep = "\n")
                }
                private$.blit_stderr_done <- function() {
                    close(private$.blit_stderr_con)
                }
            }
            private$.blit_stderr_remain <- ""
        },
        .blit_stderr_con = NULL,
        .blit_stderr_push = NULL,
        .blit_stderr_done = NULL,
        .blit_stderr_remain = NULL,
        .blit_stderr = NULL,
        .blit_stderr_callback = NULL,
        .blit_cleanup = NULL,
        finalize = function() {
            private$.blit_complete()
            if (!is.null(super$finalize)) super$finalize()
        }
    )
)

new_spin <- function() {
    state <- 1L
    spin <- c("-", "\\", "|", "/")
    function() {
        cat("\r", spin[state], "\r", sep = "")
        state <<- state %% length(spin) + 1L
        utils::flush.console()
    }
}
