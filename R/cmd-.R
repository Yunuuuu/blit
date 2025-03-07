#' Helper function to create new command.
#'
#' @description
#' `make_command` is a helper function used by developers to create function for
#' a new [`Command`] object. It should not be used by end users.
#'
#' @param name A string of the function name.
#' @param fun A function used to initialize the [`Command`] object.
#' @param envir A environment used to bind the created function.
#' @return A function.
#' @seealso [`Command`]
#' @importFrom rlang caller_env
#' @export
make_command <- function(name, fun, envir = caller_env()) {
    force(name)
    out <- rlang::new_function(
        rlang::fn_fmls(fun),
        quote({
            # capture the call, and modify it if the first unnamed value is
            # a `command`
            call <- as.list(sys.call())
            envir <- parent.frame() # the environment used to evaluate the call

            # unnamed values
            unnamed <- which(!rlang::have_name(call[-1L])) + 1L

            # prepare the ouput
            out <- NULL # should be the input `command`
            if (length(unnamed)) {
                # if the first unnamed value is a `command` object
                out <- rlang::try_fetch(
                    eval(.subset2(call, unnamed[1L]), envir = envir),
                    error = function(cnd) NULL
                )
                if (inherits(out, "command")) {
                    call <- call[-unnamed[1L]]
                } else {
                    out <- NULL
                }
            }

            # insert a new stack to save the function
            # in this way, the error message will give the function name
            new_stack <- new.env(parent = envir)
            new_stack[[name]] <- fun
            call[[1L]] <- rlang::sym(name)
            new <- eval(as.call(call), envir = new_stack)
            if (is.null(out)) {
                out <- new_command(new)
            } else {
                out$command_series <- c(
                    .subset2(out, "command_series"),
                    list(new)
                )
            }
            out
        })
    )
    assign(name, value = out, envir = envir, inherits = FALSE)
    out
}

new_command <- function(Command, envvar = NULL, wd = NULL) {
    structure(
        list(command_series = list(Command), envvar = NULL, wd = NULL),
        class = "command"
    )
}

#' @export
print.command <- function(x, ...) {
    command_series <- .subset2(x, "command_series")
    if (length(command_series)) {
        if (length(command_series) > 1L) {
            cat(
                sprintf("A series of %d commands:", length(command_series)),
                sep = "\n"
            )
            indent <- 2L
        } else {
            indent <- 0L
        }
        for (command in command_series) {
            print(command, indent = indent)
        }
    }
    if (!is.null(wd <- .subset2(x, "wd"))) {
        cat(sprintf("Working directory: %s", wd), sep = "\n")
    }
    if (!is.null(envvar <- .subset2(x, "envvar"))) {
        cat("Environment Variables:", sep = "\n")
        nms <- format(names(envvar), justify = "right")
        values <- format(envvar, justify = "left")
        cat(paste0("  ", nms, ": ", values), sep = "\n")
    }
    invisible(x)
}

#' R6 Class to prepare command parameters.
#'
#' @description
#' `Command` is an R6 class used by developers to create new command. It should
#' not be used by end users.
#'
#' @seealso make_command
#' @export
Command <- R6Class("Command",
    public = list(

        #' @description Create a new `Command` object.
        #' @param ... Additional argument passed into command.
        #' @param .subcmd A sub-command string that is always inserted between
        #' the main command and other parameters.
        initialize = function(..., .subcmd = NULL) {
            # if provided subcmd, we assign it into our object
            private$subcmd <- .subcmd

            # collect all parameters, we cannot evaluate it since if we want to
            # print help document, it's much possible there were some missing
            # argument we only evaluate necessary parameters
            input <- rlang::enquos(..., .ignore_empty = "all")

            # Extract params used
            # `command_locate`: params used to locate command path.
            # `combine_params`: combine combine dots and params or other global
            #                   params (both optional and regular params)
            # Core parameters will always be evaluated, they will be used to
            # execute the command or display the document
            core_params <- private$trim_params(c(
                rlang::fn_fmls_names(private$command_locate),
                rlang::fn_fmls_names(private$combine_params)
            ))

            # `setup_command_params`: params used to execute the command
            params <- private$trim_params(
                setdiff(
                    rlang::fn_fmls_names(private$setup_command_params),
                    core_params
                )
            )

            # there were usually additional arguments passed into command by
            # `...`, they must be un-named
            dots <- input[!rlang::names2(input) %in% c(core_params, params)]

            # here: we check if all necessary parameters have been provided by
            #       external function. (in case from myself missing provide the
            #       parameters in external function)
            missing <- setdiff(core_params, names(input))
            if (length(missing)) {
                cli::cli_abort("Missing parameters: {.arg {missing}}")
            }

            # here: we check if we need `...`.
            if (private$collect_dots) {
                # we collect and check dots
                named <- dots[rlang::have_name(dots)]
                if (length(named)) {
                    cli::cli_abort(
                        "Unknown parameter{?s}: {.arg {names(named)}}"
                    )
                }
                private$.dots <- dots
            } else if (length(dots)) {
                if (rlang::is_named(dots)) {
                    note <- paste(
                        "Did you misname argument{?s}",
                        "({.arg {names(dots)}})?"
                    )
                } else {
                    note <- "Did you forget to name an argument?"
                }
                cli::cli_abort(c("`...` must be empty", i = note))
            }

            core_params <- lapply(
                input[intersect(names(input), core_params)],
                rlang::eval_tidy
            )

            params <- input[intersect(names(input), params)]
            private$.core_params <- core_params
            private$.params <- params
        },

        #' @description Build the command line
        #' @param help A boolean value indicating whether to build parameters
        #' for help document or not.
        #' @param verbose A boolean value indicating whether the command
        #' execution should be verbose.
        #' @param envir An environment used to Execute command.
        #' @return An atomic character combine the command and parameters.
        #' @importFrom rlang caller_env
        build_command = function(help = FALSE, verbose = TRUE) {
            private$verbose <- verbose
            core_params <- private$.core_params

            # locate command path ------------------------------
            command <- rlang::inject(private$command_locate(
                !!!core_params[intersect(
                    rlang::fn_fmls_names(private$command_locate),
                    names(core_params)
                )]
            ))
            if (is.null(command) || !nzchar(command)) {
                cli::cli_abort("Cannot locate command {.field {private$name}}")
            }

            # prepare command parameters -----------------------
            if (isTRUE(help)) {
                private$params <- build_command_params(
                    private$setup_help_params(),
                    paste(
                        "`$setup_help_params()` method must return an",
                        "object that can be coerced into a character vector."
                    )
                )
                private$dots <- character()
            } else {
                # always ensure the parameters have been computed
                # only evaluate the parameters once
                if (is.null(private$.evaluated_params)) {
                    private$.evaluated_params <- lapply(
                        private$.params, rlang::eval_tidy
                    )
                }
                if (is.null(private$.evaluated_dots)) {
                    private$.evaluated_dots <- lapply(
                        private$.dots, rlang::eval_tidy
                    )
                }
                private$params <- build_command_params(
                    rlang::inject(private$setup_command_params(
                        !!!private$.evaluated_params[intersect(
                            rlang::fn_fmls_names(private$setup_command_params),
                            names(private$.evaluated_params)
                        )]
                    )),
                    paste(
                        "`$setup_command_params()` method must return an",
                        "object that can be coerced into a character vector."
                    )
                )
                private$dots <- build_command_params(
                    private$.evaluated_dots,
                    paste(
                        "Only objects that can be coerced into",
                        "a character vector can be input in {.code ...}"
                    )
                )
            }
            combined <- rlang::inject(private$combine_params(
                !!!core_params[intersect(
                    rlang::fn_fmls_names(private$combine_params),
                    names(core_params)
                )]
            ))
            private$params <- NULL
            private$dots <- NULL

            # combine command, subcmd, and params -------
            c(command, private$subcmd, combined)
        },

        #' @description Get the cleaned expression
        #' @return A list of [`quosures`][rlang::quo()].
        get_cleaned = function() private$cleaned,

        #' @description Reset the cleaned expression
        #' @return The object itself.
        reset_cleaned = function() {
            private$cleaned <- NULL
            invisible(self)
        },

        #' @description Build parameters to run command.
        #' @param indent A single integer number giving the space of indent.
        #' @return The object itself.
        print = function(indent = NULL) {
            if (!is.numeric(indent) || indent < 1L) {
                msg <- sprintf("<Command: %s>", private$name)
            } else {
                msg <- sprintf(
                    "%s<Command: %s>",
                    strrep(" ", as.integer(indent)),
                    private$name
                )
            }
            cat(msg, sep = "\n")
            invisible(self)
        }
    ),
    private = list(
        # @field core_params A list of parameters used to define the command
        # itself.
        .core_params = list(),

        # @field dots A list of parameters used to execute the command
        .params = NULL,

        # @field dots Additional parameters used to execute the command.
        .dots = NULL,

        # the both fields saved the estimated value for the `$params` and
        # `$dots` respectively.
        .evaluated_params = NULL,
        .evaluated_dots = NULL,

        # these fields carry the state when executating the command, and
        # will always be re-calculated before using
        verbose = NULL, params = NULL, dots = NULL, cleaned = NULL,

        # @field subcmd A character string define the subcmd argument.
        subcmd = NULL,

        # remove extra parameters used by internal
        trim_params = function(argv) setdiff(argv, private$extra_params),

        # @description Used to attach an expression to be evaluated when
        # exiting command finished.
        setup_exit = function(...) {
            private$cleaned <- c(private$cleaned, rlang::enquos(...))
            invisible(self)
        },

        ##############################################################
        # Following fields or methods should be overrided by sub-class.
        # @field name A string of the command name.
        name = NULL,

        # @field alias A character giving the command alias.
        alias = NULL,

        # @field collect_dots A boolean value indicating whether `...` should be
        # collected and passed into command
        collect_dots = TRUE,

        # @field extra_params Additional parameters used by `Command` object
        # but shouldn't collected from user input.
        extra_params = NULL,

        # @description Method used to locate command
        #
        # @return An string of command path
        command_locate = function(cmd) {
            if (is.null(cmd <- cmd)) {
                commands <- c(private$name, private$alias)
                for (cmd in commands) {
                    if (nzchar(command <- Sys.which(cmd))) {
                        break
                    }
                }
                if (!nzchar(command)) {
                    cli::cli_abort(sprintf(
                        "Cannot locate %s command",
                        oxford_comma(sprintf("{.field %s}", commands),
                            final = "or"
                        )
                    ))
                }
            } else {
                command <- Sys.which(cmd)
            }
            command
        },

        # @description Method used to prepare parameters to run regular command
        #
        # @return An atomic character, or `NULL`.
        setup_command_params = function() NULL,

        # @description Method used to prepare parameters to display the help
        # documents. This method shouldn't have any arguments.
        #
        # @return An atomic character, or `NULL`.
        setup_help_params = function() {
            if (is.null(private$name)) {
                nm <- "<Command>"
            } else {
                nm <- sprintf("<Command: %s>", private$name)
            }
            cli::cli_abort("No help document for {nm}")
        },

        # @description Method used to combine `private$dots` and
        # `private$params`
        #
        # @return An atomic character.
        combine_params = function() c(private$dots, private$params)
    )
)

#' @return Always return a character.
#' @noRd
build_command_params <- function(params, msg) {
    if (is.null(params)) {
        character()
    } else if (is.character(params)) {
        params
    } else if (is.numeric(params) || is.logical(params)) {
        as.character(params)
    } else if (is.list(params)) {
        unlist(
            lapply(params, build_command_params, msg = msg),
            use.names = FALSE
        )
    } else {
        cli::cli_abort(msg)
    }
}

remove_opath <- function(opath) {
    # remove trailing backslash or slash
    opath <- path_trim(opath)
    opath <- opath[file.exists(opath)] # can also check directory
    if (length(opath) == 0L) return(NULL) # styler: off
    failed <- vapply(opath, unlink, integer(1L),
        recursive = TRUE, USE.NAMES = FALSE
    ) != 0L
    if (any(failed)) cli::cli_warn("Cannot remove {.path {opath[failed]}}")
}

build_opath <- function(odir, ofile = NULL, abs = FALSE,
                        call = rlang::caller_call()) {
    assert_string(odir,
        allow_empty = FALSE,
        arg = rlang::caller_arg(odir), call = call
    )
    assert_string(ofile,
        allow_empty = FALSE, allow_null = TRUE,
        arg = rlang::caller_arg(ofile), call = call
    )
    odir <- path_trim(odir)
    dir_create(odir)
    # whether to use absolute path
    if (abs) odir <- normalizePath(odir, winslash = "/", mustWork = TRUE)
    if (!is.null(ofile)) file_path(odir, ofile) else odir
}
