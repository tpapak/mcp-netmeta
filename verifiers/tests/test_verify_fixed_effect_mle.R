#' Tests for Fixed-Effect NMA MLE Verifier
#'
#' Run with: Rscript verifiers/tests/test_verify_fixed_effect_mle.R
#' Or from R: source("verifiers/tests/test_verify_fixed_effect_mle.R")

# Load the verifier
source("verifiers/verify_fixed_effect_mle.R")

# Test counter
tests_passed <- 0
tests_failed <- 0

test <- function(name, expr) {
  result <- tryCatch(
    {
      if (expr) {
        cat(sprintf("[PASS] %s\n", name))
        tests_passed <<- tests_passed + 1
        TRUE
      } else {
        cat(sprintf("[FAIL] %s\n", name))
        tests_failed <<- tests_failed + 1
        FALSE
      }
    },
    error = function(e) {
      cat(sprintf("[ERROR] %s: %s\n", name, e$message))
      tests_failed <<- tests_failed + 1
      FALSE
    }
  )
  invisible(result)
}

cat("\n")
cat("====================================================\n")
cat("  Tests for verify_fixed_effect_mle.R\n")
cat("====================================================\n\n")

# ============================================================
# TEST 1: Simple two-arm studies only (synthetic data)
# ============================================================

cat("--- Test 1: Two-arm studies only (synthetic) ---\n\n")

# Create simple synthetic data with only two-arm studies
# A vs B: 3 studies
# B vs C: 2 studies  
# A vs C: 1 study
synthetic_data <- data.frame(
  studlab = c("S1", "S2", "S3", "S4", "S5", "S6"),
  treat1 = c("A", "A", "A", "B", "B", "A"),
  treat2 = c("B", "B", "B", "C", "C", "C"),
  TE = c(0.5, 0.6, 0.4, 0.3, 0.4, 0.9),
  seTE = c(0.1, 0.15, 0.12, 0.2, 0.18, 0.25)
)

# Run NMA
nma1 <- netmeta(
  TE = synthetic_data$TE,
  seTE = synthetic_data$seTE,
  treat1 = synthetic_data$treat1,
  treat2 = synthetic_data$treat2,
  studlab = synthetic_data$studlab,
  sm = "MD",
  common = TRUE,
  random = FALSE,
  reference.group = "C"
)

# Compute exact MLE
exact1 <- compute_exact_mle(
  TE = synthetic_data$TE,
  seTE = synthetic_data$seTE,
  treat1 = synthetic_data$treat1,
  treat2 = synthetic_data$treat2,
  studlab = synthetic_data$studlab,
  reference = "C"
)

# Verify exact MLE
v1 <- verify_fixed_effect_mle(
  TE = synthetic_data$TE,
  seTE = synthetic_data$seTE,
  treat1 = synthetic_data$treat1,
  treat2 = synthetic_data$treat2,
  studlab = synthetic_data$studlab,
  league_table = exact1$league_table,
  reference = "C"
)

test("Exact MLE passes all verification tests", v1$is_valid_mle)
test("Score equations are zero", v1$tests$score_zero$passed)
test("Information matrix is positive definite", v1$tests$positive_definite$passed)
test("Solution is unique", v1$tests$unique_solution$passed)
test("Matches WLS solution", v1$tests$wls_solution$passed)
test("No multi-arm studies detected", !v1$tests$multiarm_consistent$has_multiarm)

# For two-arm only data, netmeta should exactly match exact MLE
max_diff_1 <- max(abs(nma1$TE.common - exact1$league_table))
test("netmeta matches exact MLE for two-arm data", max_diff_1 < 1e-10)

cat("\n")

# ============================================================
# TEST 2: Data with multi-arm study (Senn2013 - Diabetes)
# ============================================================

cat("--- Test 2: Multi-arm study (Senn2013) ---\n\n")

data(Senn2013, package = "netmeta")

# Run NMA
nma2 <- netmeta(
  TE = Senn2013$TE,
  seTE = Senn2013$seTE,
  treat1 = Senn2013$treat1,
  treat2 = Senn2013$treat2,
  studlab = Senn2013$studlab,
  sm = "MD",
  common = TRUE,
  random = FALSE,
  reference.group = "plac"
)

# Compute exact MLE
exact2 <- compute_exact_mle(
  TE = Senn2013$TE,
  seTE = Senn2013$seTE,
  treat1 = Senn2013$treat1,
  treat2 = Senn2013$treat2,
  studlab = Senn2013$studlab,
  reference = "plac"
)

# Verify exact MLE
v2 <- verify_fixed_effect_mle(
  TE = Senn2013$TE,
  seTE = Senn2013$seTE,
  treat1 = Senn2013$treat1,
  treat2 = Senn2013$treat2,
  studlab = Senn2013$studlab,
  league_table = exact2$league_table,
  reference = "plac"
)

test("Exact MLE passes all verification tests (multi-arm)", v2$is_valid_mle)
test("Score equations are zero (multi-arm)", v2$tests$score_zero$passed)
test("Information matrix is positive definite (multi-arm)", v2$tests$positive_definite$passed)
test("Solution is unique (multi-arm)", v2$tests$unique_solution$passed)
test("Matches WLS solution (multi-arm)", v2$tests$wls_solution$passed)
test("Multi-arm study detected", v2$tests$multiarm_consistent$has_multiarm)
test("Multi-arm variances are consistent", v2$tests$multiarm_consistent$passed)

# Check that Willms1999 (3-arm study) is properly identified
willms_check <- v2$tests$multiarm_consistent$details[["Willms1999"]]
test("Willms1999 identified as 3-arm study", !is.null(willms_check) && willms_check$n_arms == 3)
test("Willms1999 has 3 contrasts (complete)", !is.null(willms_check) && willms_check$n_contrasts == 3)
test("Willms1999 arm variances recovered", !is.null(willms_check) && willms_check$is_solvable)

# Verify netmeta output (expected to fail due to approximate method)
v2_netmeta <- verify_netmeta_mle(nma2)
test("netmeta uses approximate method (verification fails)", !v2_netmeta$is_valid_mle)

# But the difference should be small
max_diff_2 <- max(abs(nma2$TE.common - exact2$league_table))
test("netmeta vs exact MLE difference is small (< 0.05)", max_diff_2 < 0.05)

cat("\n")

# ============================================================
# Summary
# ============================================================

cat("====================================================\n")
cat(sprintf("  SUMMARY: %d passed, %d failed\n", tests_passed, tests_failed))
cat("====================================================\n\n")

if (tests_failed > 0) {
  quit(status = 1)
}
