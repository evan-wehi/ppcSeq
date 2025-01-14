% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ppcSeq.R
\name{do_inference}
\alias{do_inference}
\title{do_inference}
\usage{
do_inference(my_df, formula, sample_column, gene_column, value_column,
  significance_column, do_check_column, full_bayes = F, C, X,
  lambda_mu_mu, cores, exposure_rate_multiplier, intercept_shift_scale,
  additional_parameters_to_save, adj_prob_theshold, to_exclude = tibble(S
  = integer(), G = integer()), truncation_compensation = 1,
  save_generated_quantities = F, inits_fx = "random",
  prior_from_discovery = tibble(.variable = character(), mean =
  numeric(), sd = numeric()))
}
\arguments{
\item{formula}{A formula}

\item{sample_column}{A column name}

\item{gene_column}{A column name}

\item{value_column}{A column name}

\item{significance_column}{A column name}

\item{full_bayes}{A boolean}

\item{input.df}{A tibble including a gene name column | sample name column | read counts column | covariates column}

\item{how_many_negative_controls}{An integer}

\item{how_many_posterior_draws}{An integer}
}
\value{
A tibble with additional columns
}
\description{
This function calls the stan model.
}
