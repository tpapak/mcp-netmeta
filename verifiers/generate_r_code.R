#' R Code Generator for Network Meta-Analysis
#'
#' Generates standalone R code that reproduces the NMA analysis.
#' This allows users to:
#' 1. Verify results by running the code themselves
#' 2. Understand exactly what analysis was performed
#' 3. Modify and extend the analysis
#' 4. Include reproducible code in publications
#'
#' Dependencies:
#'   - netmeta: Network meta-analysis

library(netmeta)

#' Generate R code for network meta-analysis
#'
#' Creates a complete, standalone R script that reproduces the NMA.
#'
#' @param TE Vector of observed treatment effects
#' @param seTE Vector of standard errors
#' @param treat1 Vector of first treatments
#' @param treat2 Vector of second treatments
#' @param studlab Vector of study labels
#' @param sm Summary measure (e.g., "OR", "RR", "MD", "SMD")
#' @param reference Reference treatment (NULL for automatic)
#' @param common Include common (fixed) effect model
#' @param random Include random effects model
#' @param method_tau Method for estimating tau² (default: "REML")
#' @param include_rankings Include P-score rankings
#' @param include_league Include league table output
#' @param include_forest Include forest plot code
#' @param include_netgraph Include network graph code
#' @return Character string containing R code
generate_nma_code <- function(TE, seTE, treat1, treat2, studlab,
                               sm = "MD",
                               reference = NULL,
                               common = TRUE,
                               random = TRUE,
                               method_tau = "REML",
                               include_rankings = TRUE,
                               include_league = TRUE,
                               include_forest = TRUE,
                               include_netgraph = TRUE) {
  
  # Determine reference if not specified
  if (is.null(reference)) {
    reference <- sort(unique(c(treat1, treat2)))[1]
  }
  
  # Build data frame representation
  data_rows <- sprintf('  c("%s", "%s", "%s", %s, %s)',
                       studlab, treat1, treat2, 
                       format(TE, digits = 6),
                       format(seTE, digits = 6))
  data_str <- paste(data_rows, collapse = ",\n")
  
  # Generate code
  code <- sprintf('
#\' Network Meta-Analysis
#\'
#\' This script performs a network meta-analysis using the netmeta package.
#\' Generated automatically - can be run standalone to reproduce results.
#\'
#\' Required packages: netmeta
#\' Install with: install.packages("netmeta")

# Load required package
library(netmeta)

# ============================================================
# Data
# ============================================================

# Create data frame with pairwise comparisons
data_matrix <- rbind(
%s
)

data <- data.frame(
  studlab = data_matrix[, 1],
  treat1 = data_matrix[, 2],
  treat2 = data_matrix[, 3],
  TE = as.numeric(data_matrix[, 4]),
  seTE = as.numeric(data_matrix[, 5]),
  stringsAsFactors = FALSE
)

cat("Data summary:\\n")
cat("  Studies:", length(unique(data$studlab)), "\\n")
cat("  Comparisons:", nrow(data), "\\n")
cat("  Treatments:", length(unique(c(data$treat1, data$treat2))), "\\n\\n")

# ============================================================
# Network Meta-Analysis
# ============================================================

nma <- netmeta(

  TE = data$TE,
  seTE = data$seTE,
  treat1 = data$treat1,
  treat2 = data$treat2,
  studlab = data$studlab,
  sm = "%s",
  reference.group = "%s",
  common = %s,
  random = %s,
  method.tau = "%s"
)

# Print summary
print(summary(nma))
', data_str, sm, reference, 
   ifelse(common, "TRUE", "FALSE"),
   ifelse(random, "TRUE", "FALSE"),
   method_tau)
  
  # Add rankings
  if (include_rankings) {
    code <- paste0(code, '
# ============================================================
# Treatment Rankings (P-scores)
# ============================================================

ranking <- netrank(nma, small.values = "undesirable")
print(ranking)
')
  }
  
  # Add league table
  if (include_league) {
    code <- paste0(code, sprintf('
# ============================================================
# League Table
# ============================================================

cat("\\nLeague Table (%s effects):\\n\\n")
league <- netleague(nma, common = %s, random = %s)
print(league)
', ifelse(random, "random", "common"),
   ifelse(common, "TRUE", "FALSE"),
   ifelse(random, "TRUE", "FALSE")))
  }
  
  # Add forest plot
  if (include_forest) {
    code <- paste0(code, sprintf('
# ============================================================
# Forest Plot
# ============================================================

# Forest plot comparing all treatments to reference
forest(nma, reference.group = "%s", sortvar = TE)
', reference))
  }
  
  # Add network graph
  if (include_netgraph) {
    code <- paste0(code, '
# ============================================================
# Network Graph
# ============================================================

netgraph(nma, 
         plastic = FALSE,
         thickness = "number.of.studies",
         multiarm = TRUE)
')
  }
  
  # Add verification section
  code <- paste0(code, '
# ============================================================
# Verification
# ============================================================

cat("\\n=== Verification ===\\n\\n")

# Check network connectivity
cat("Network connected:", nma$n == length(nma$trts), "\\n")

# Heterogeneity statistics
if (nma$random) {
  cat("Heterogeneity:\\n")
  cat("  tau²:", round(nma$tau^2, 4), "\\n")
  cat("  tau:", round(nma$tau, 4), "\\n")
  cat("  I²:", round(nma$I2 * 100, 1), "%\\n")
}

# Q statistics
cat("\\nQ statistics:\\n")
cat("  Q total:", round(nma$Q, 2), "(df =", nma$df.Q, ", p =", 
    format.pval(nma$pval.Q, digits = 3), ")\\n")
if (!is.null(nma$Q.heterogeneity)) {
  cat("  Q heterogeneity:", round(nma$Q.heterogeneity, 2), "(df =", 
      nma$df.Q.heterogeneity, ")\\n")
}
if (!is.null(nma$Q.inconsistency)) {
  cat("  Q inconsistency:", round(nma$Q.inconsistency, 2), "(df =", 
      nma$df.Q.inconsistency, ", p =",
      format.pval(nma$pval.Q.inconsistency, digits = 3), ")\\n")
}
')
  
  return(code)
}


#' Generate R code from netmeta object
#'
#' @param nma A netmeta object
#' @param include_rankings Include P-score rankings
#' @param include_league Include league table output
#' @param include_forest Include forest plot code
#' @param include_netgraph Include network graph code
#' @return Character string containing R code
generate_nma_code_from_netmeta <- function(nma,
                                            include_rankings = TRUE,
                                            include_league = TRUE,
                                            include_forest = TRUE,
                                            include_netgraph = TRUE) {
  
  reference <- nma$reference.group
  if (is.null(reference) || reference == "") {
    reference <- nma$trts[1]
  }
  
  generate_nma_code(
    TE = nma$TE,
    seTE = nma$seTE,
    treat1 = nma$treat1,
    treat2 = nma$treat2,
    studlab = nma$studlab,
    sm = nma$sm,
    reference = reference,
    common = nma$common,
    random = nma$random,
    method_tau = nma$method.tau,
    include_rankings = include_rankings,
    include_league = include_league,
    include_forest = include_forest,
    include_netgraph = include_netgraph
  )
}


#' Save generated R code to file
#'
#' @param code R code string
#' @param filename Output filename
save_nma_code <- function(code, filename) {
  writeLines(code, filename)
  cat("R code saved to:", filename, "\n")
}


#' Verify generated code produces same results
#'
#' Runs the generated code and compares results to the original.
#'
#' @param nma Original netmeta object
#' @param code Generated R code
#' @param tol Numerical tolerance
#' @return List with verification results
verify_generated_code <- function(nma, code, tol = 1e-10) {
  
  # Create temporary file
  tmp_file <- tempfile(fileext = ".R")
  writeLines(code, tmp_file)
  
  # Capture the nma object from running the code
  env <- new.env()
  
  # Suppress output while running
  result <- tryCatch({
    suppressMessages(suppressWarnings({
      source(tmp_file, local = env)
    }))
    TRUE
  }, error = function(e) {
    FALSE
  })
  
  # Clean up
  unlink(tmp_file)
  
  if (!result || !exists("nma", envir = env)) {
    return(list(
      passed = FALSE,
      error = "Generated code failed to run or did not produce nma object"
    ))
  }
  
  nma_reproduced <- env$nma
  
  # Compare results
  tests <- list()
  
  # Compare common effect estimates
  if (nma$common && nma_reproduced$common) {
    max_diff_common <- max(abs(nma$TE.common - nma_reproduced$TE.common), na.rm = TRUE)
    tests$common_effects <- list(
      passed = max_diff_common < tol,
      max_difference = max_diff_common
    )
  }
  
  # Compare random effects estimates
  if (nma$random && nma_reproduced$random) {
    max_diff_random <- max(abs(nma$TE.random - nma_reproduced$TE.random), na.rm = TRUE)
    tests$random_effects <- list(
      passed = max_diff_random < tol,
      max_difference = max_diff_random
    )
    
    # Compare tau
    tau_diff <- abs(nma$tau - nma_reproduced$tau)
    tests$tau <- list(
      passed = tau_diff < tol,
      difference = tau_diff
    )
  }
  
  all_passed <- all(sapply(tests, function(t) t$passed))
  
  list(
    passed = all_passed,
    tests = tests
  )
}


# ============================================================
# Example
# ============================================================

if (sys.nframe() == 0) {
  
  cat("R Code Generator for Network Meta-Analysis\n")
  cat("==========================================\n\n")
  
  # Load example data
  data(Senn2013, package = "netmeta")
  
  # Run NMA
  nma <- netmeta(
    TE = Senn2013$TE,
    seTE = Senn2013$seTE,
    treat1 = Senn2013$treat1,
    treat2 = Senn2013$treat2,
    studlab = Senn2013$studlab,
    sm = "MD",
    common = TRUE,
    random = TRUE,
    reference.group = "plac"
  )
  
  # Generate code
  code <- generate_nma_code_from_netmeta(nma)
  
  cat("Generated R code:\n")
  cat("=================\n")
  cat(code)
  
  # Verify the code reproduces results
  cat("\n\nVerifying generated code...\n")
  verification <- verify_generated_code(nma, code)
  
  if (verification$passed) {
    cat("PASSED: Generated code reproduces original results.\n")
  } else {
    cat("FAILED: Generated code does not match original results.\n")
    print(verification$tests)
  }
  
  # Save to file
  # save_nma_code(code, "my_nma_analysis.R")
}
