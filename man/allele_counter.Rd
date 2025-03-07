% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/cmd-alleleCounter.R
\name{allele_counter}
\alias{allele_counter}
\title{Run alleleCount}
\usage{
allele_counter(
  hts_file,
  loci_file,
  ofile,
  ...,
  odir = getwd(),
  alleleCounter = NULL
)
}
\arguments{
\item{hts_file}{A string of path to sample HTS file.}

\item{loci_file}{A string of path to loci file.}

\item{ofile}{A string of path to the output file.}

\item{...}{<\link[rlang:dyn-dots]{dynamic dots}> Additional arguments passed to \code{alleleCounter} command. Empty arguments are automatically trimmed. If a single argument, such as a file path, contains spaces, it must be quoted, for example using \code{\link{shQuote}}. Details see: \code{cmd_help(alleleCounter())}.}

\item{odir}{A string of path to the output directory.}

\item{alleleCounter}{A string of path to \code{alleleCounter} command.}
}
\value{
A \code{command} object.
}
\description{
The \code{alleleCount} program primarily exists to prevent code duplication
between some other projects, specifically \code{AscatNGS} and \code{Battenberg}.
}
\seealso{
\url{https://github.com/cancerit/alleleCount}
}
