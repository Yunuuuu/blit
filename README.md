
<!-- README.md is generated from README.Rmd. Please edit that file -->

# blit: Bioinformatics Library for Integrated Tools <img src="man/figures/logo.png" alt="logo" align="right" height="140" width="120"/>

<!-- badges: start -->

[![R-CMD-check](https://github.com/WangLabCSU/blit/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/WangLabCSU/blit/actions/workflows/R-CMD-check.yaml)
[![CRAN
status](https://www.r-pkg.org/badges/version/blit)](https://CRAN.R-project.org/package=blit)
<!-- badges: end -->

The goal of `blit` is to make it easy to execute command line tool from
R.

## Installation

You can install `blit` from `CRAN` using:

``` r
install.packages("blit")
```

Alternatively, install the development version from
[GitHub](https://github.com/) with:

``` r
# install.packages("devtools")
devtools::install_github("WangLabCSU/blit")
```

## Example

``` r
library(blit)
```

To build a `command`, simply use `exec`. The first argument is the
command name, and you can also provide the full path. After that, pass
the command parameters. This will create a `command` object:

``` r
exec("echo", "$PATH")
#> <Command: echo>
```

To run the command, just pass the `command` object to the `cmd_run()`

``` r
Sys.setenv(TEST = "blit is awesome")
exec("echo", "$TEST") |> cmd_run()
#> Running command: /usr/bin/echo $TEST
#> 
#> blit is awesome
#> [1] 0
```

Alternatively, you can run it in the background. In this case, a
[`process`](https://processx.r-lib.org/index.html) object will be
returned. For more information, refer to the official site:

``` r
proc <- exec("echo", "$TEST") |> cmd_background()
#> Running command: /usr/bin/echo $TEST
proc$kill()
#> [1] FALSE
Sys.unsetenv("TEST")
```

Several functions allow you to control the environment when running the
command:

- `cmd_wd`: define the working directory.
- `cmd_envvar`: define the environment variables.
- `cmd_envpath`: define the `PATH`-like environment variables.

``` r
exec("echo", "$TEST") |>
    cmd_envvar(TEST = "blit is very awesome") |>
    cmd_run()
#> Environment Variables: TEST
#> Running command: /usr/bin/echo $TEST
#> 
#> blit is very awesome
#> [1] 0
```

`blit` provides several built-in functions for directly executing
specific commands., these include:
[alleleCounter](https://github.com/cancerit/alleleCount),
[cellranger](https://www.10xgenomics.com/cn/support/software/cell-ranger/latest),
[fastq_pair](https://github.com/linsalrob/fastq-pair),
[gistic2](https://broadinstitute.github.io/gistic2/),
[KrakenTools](https://github.com/jenniferlu717/KrakenTools),
[kraken2](https://github.com/DerrickWood/kraken2/wiki/Manual),
[perl](https://www.perl.org/),
[pySCENIC](https://github.com/aertslab/pySCENIC),
[python](https://www.python.org/),
[seqkit](https://bioinf.shenwei.me/seqkit/),
[trust4](https://github.com/liulab-dfci/TRUST4).

For these commands, you can also use `cmd_help()` to print the help
document.

``` r
python() |> cmd_help()
#> Running command: /usr/bin/python3 --help
#> 
#> usage: /usr/bin/python3 [option] ... [-c cmd | -m mod | file | -] [arg] ...
#> Options (and corresponding environment variables):
#> -b     : issue warnings about converting bytes/bytearray to str and comparing
#>          bytes/bytearray with str or bytes with int. (-bb: issue errors)
#> -B     : don't write .pyc files on import; also PYTHONDONTWRITEBYTECODE=x
#> -c cmd : program passed in as string (terminates option list)
#> -d     : turn on parser debugging output (for experts only, only works on
#>          debug builds); also PYTHONDEBUG=x
#> -E     : ignore PYTHON* environment variables (such as PYTHONPATH)
#> -h     : print this help message and exit (also -? or --help)
#> -i     : inspect interactively after running script; forces a prompt even
#>          if stdin does not appear to be a terminal; also PYTHONINSPECT=x
#> -I     : isolate Python from the user's environment (implies -E and -s)
#> -m mod : run library module as a script (terminates option list)
#> -O     : remove assert and __debug__-dependent statements; add .opt-1 before
#>          .pyc extension; also PYTHONOPTIMIZE=x
#> -OO    : do -O changes and also discard docstrings; add .opt-2 before
#>          .pyc extension
#> -P     : don't prepend a potentially unsafe path to sys.path; also
#>          PYTHONSAFEPATH
#> -q     : don't print version and copyright messages on interactive startup
#> -s     : don't add user site directory to sys.path; also PYTHONNOUSERSITE=x
#> -S     : don't imply 'import site' on initialization
#> -u     : force the stdout and stderr streams to be unbuffered;
#>          this option has no effect on stdin; also PYTHONUNBUFFERED=x
#> -v     : verbose (trace import statements); also PYTHONVERBOSE=x
#>          can be supplied multiple times to increase verbosity
#> -V     : print the Python version number and exit (also --version)
#>          when given twice, print more information about the build
#> -W arg : warning control; arg is action:message:category:module:lineno
#>          also PYTHONWARNINGS=arg
#> -x     : skip first line of source, allowing us
```

``` r
perl() |> cmd_help()
#> Running command: /usr/bin/perl --help
#> 
#> 
#> Usage: /usr/bin/perl [switches] [--] [programfile] [arguments]
#>   -0[octal/hexadecimal] specify record separator (\0, if no argument)
#>   -a                    autosplit mode with -n or -p (splits $_ into @F)
#>   -C[number/list]       enables the listed Unicode features
#>   -c                    check syntax only (runs BEGIN and CHECK blocks)
#>   -d[t][:MOD]           run program under debugger or module Devel::MOD
#>   -D[number/letters]    set debugging flags (argument is a bit mask or alphabets)
#>   -e commandline        one line of program (several -e's allowed, omit programfile)
#>   -E commandline        like -e, but enables all optional features
#>   -f                    don't do $sitelib/sitecustomize.pl at startup
#>   -F/pattern/           split() pattern for -a switch (//'s are optional)
#>   -g                    read all input in one go (slurp), rather than line-by-line (alias for -0777)
#>   -i[extension]         edit <> files in place (makes backup if extension supplied)
#>   -Idirectory           specify @INC/#include directory (several -I's allowed)
#>   -l[octnum]            enable line ending processing, specifies line terminator
#>   -[mM][-]module        execute "use/no module..." before executing program
#>   -n                    assume "while (<>) { ... }" loop around program
#>   -p                    assume loop like -n but print line also, like sed
#>   -s                    enable rudimentary parsing for switches after programfile
#>   -S                    look for programfile using PATH environment variable
#>   -t                    enable tainting warnings
#>   -T                    enable tainting checks
#>   -u                    dump core after parsing program
#>   -U                    allow unsafe operations
#>   -v                    print version, patchlevel and license
#>   -V[:configvar]        print configuration summary (or a single Config.pm variable)
#>   -w                    enable many useful warnings
#>   -W                    enable all warnings
#>   -x[directory]         ignore text before
```

And it is very easily to extend for other commands.

One of the great features of `blit` is its ability to translate the R
pipe (`%>%` or `|>`) into the Linux pipe (`|`). All functions used to
create a `command` object can accept another `command` object. The
internal will capture the first unnamed input value. If it is a
`command` object, it will be removed from the call and saved. When the
`command` object is run, the saved command will be passed through the
pipe (`|`) to the command. Here we take the `gzip` command as an example
(assuming you’re using a Linux system).

``` r
tmpdir <- tempdir()
file <- tempfile(tmpdir = tmpdir)
writeLines(letters, con = file)
file2 <- tempfile()
exec("gzip", "-c", file) |>
    exec("gzip", "-d", ">", file2) |>
    cmd_run()
#> Running command: /usr/bin/gzip -c /tmp/RtmpMpafpi/file2cd9bb567d1420 |
#> /usr/bin/gzip -d > /tmp/RtmpMpafpi/file2cd9bb358450c3
#> [1] 0
identical(readLines(file), readLines(file2))
#> [1] TRUE
```

In the last we clean the temporary files.

``` r
file.remove(file)
#> [1] TRUE
file.remove(file2)
#> [1] TRUE
```

## Development

To add a new command, use the `make_command` function. This helper
function is designed to assist developers in creating functions that
initialize new `command` objects. A `command` object is a bundle of
multiple `Command` R6 objects (note the uppercase `"C"` in `Command`,
which distinguishes it from the `command` object) and the associated
running environment (including the working directory and environment
variables).

The `make_command` function accepts a function that initializes a new
`Command` object and, when necessary, validates the input arguments. The
core purpose is to create a new `Command` R6 object, so familiarity with
the R6 class system is essential.

There are several private methods or fields you may want to override
when creating a new `Command` R6 object. The first method is
`command_locate`, which determines how to locate the command path. By
default, it will attempt to use the `cmd` argument provided by the user.
If no `cmd` argument is supplied, it will try to locate the command
using the `name` and `alias` fields. In most cases, you will only need
to provide values for the `name` and `alias` fields, rather than
overriding the `command_locate` method.

For example, consider the `ping` command. Here is how you can define it:

``` r
Ping <- R6::R6Class(
    "Ping",
    inherit = Command,
    private = list(name = "ping")
)
ping <- make_command("ping", function(..., ping = NULL) {
    Ping$new(cmd = ping, ...)
})
ping("8.8.8.8") |> cmd_run(timeout = 5) # terminate it after 5s
#> Running command: /usr/bin/ping 8.8.8.8
#> 
#> PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
#> 64 bytes from 8.8.8.8: icmp_seq=1 ttl=106 time=46.1 ms
#> 64 bytes from 8.8.8.8: icmp_seq=2 ttl=106 time=43.8 ms
#> 64 bytes from 8.8.8.8: icmp_seq=3 ttl=106 time=44.9 ms
#> 64 bytes from 8.8.8.8: icmp_seq=4 ttl=106 time=44.9 ms
#> 64 bytes from 8.8.8.8: icmp_seq=5 ttl=106 time=44.8 ms
#> Warning: System command timed out
#> [1] -9
```

For the `ping` command, the `name` field is sufficient. However, for
programs that have multiple names (like `python`), you can also provide
the `alias` (`c("python2", "python3")`) field. Refer to the
`cmd-python.R` script for more details.

For command-line tools, the input parameters should always be
characters. The core principle of the `Command` object is to convert all
R objects (such as data frames) into characters—typically file paths of
R objects that have been saved to disk.

## Session Informations

``` r
sessionInfo()
#> R version 4.4.2 (2024-10-31)
#> Platform: x86_64-pc-linux-gnu
#> Running under: Ubuntu 24.04.1 LTS
#> 
#> Matrix products: default
#> BLAS/LAPACK: /usr/lib/x86_64-linux-gnu/libmkl_rt.so;  LAPACK version 3.8.0
#> 
#> locale:
#>  [1] LC_CTYPE=C.UTF-8       LC_NUMERIC=C           LC_TIME=C.UTF-8       
#>  [4] LC_COLLATE=C.UTF-8     LC_MONETARY=C.UTF-8    LC_MESSAGES=C.UTF-8   
#>  [7] LC_PAPER=C.UTF-8       LC_NAME=C              LC_ADDRESS=C          
#> [10] LC_TELEPHONE=C         LC_MEASUREMENT=C.UTF-8 LC_IDENTIFICATION=C   
#> 
#> time zone: Asia/Shanghai
#> tzcode source: system (glibc)
#> 
#> attached base packages:
#> [1] stats     graphics  grDevices utils     datasets  methods   base     
#> 
#> other attached packages:
#> [1] blit_0.1.0.9000
#> 
#> loaded via a namespace (and not attached):
#>  [1] processx_3.8.6    compiler_4.4.2    R6_2.5.1          fastmap_1.2.0    
#>  [5] cli_3.6.3         tools_4.4.2       htmltools_0.5.8.1 yaml_2.3.10      
#>  [9] rmarkdown_2.29    knitr_1.49        xfun_0.49         digest_0.6.37    
#> [13] ps_1.8.1          rlang_1.1.4       evaluate_1.0.1
```
