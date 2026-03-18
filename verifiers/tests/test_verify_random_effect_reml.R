#' Tests for Random-Effect REML Verifier
#'
#' Run with: Rscript verifiers/tests/test_verify_random_effect_reml.R

source("verifiers/verify_fixed_effect_mle.R")
source("verifiers/verify_random_effect_reml.R")

tests_passed <- 0
tests_failed <- 0

test <- function(name, expr) {
  result <- tryCatch({
    if (expr) {
      cat(sprintf("[PASS] %s\n", name))
      tests_passed <<- tests_passed + 1
      TRUE
    } else {
      cat(sprintf("[FAIL] %s\n", name))
      tests_failed <<- tests_failed + 1
      FALSE
    }
  }, error = function(e) {
    cat(sprintf("[ERROR] %s: %s\n", name, e$message))
    tests_failed <<- tests_failed + 1
    FALSE
  })
  invisible(result)
}

cat("\n")
cat("====================================================\n")
cat("  Tests for verify_random_effect_reml.R\n")
cat("====================================================\n\n")

# ============================================================
# TEST 1: Two-arm studies with heterogeneity
# ============================================================

cat("--- Test 1: Two-arm studies with heterogeneity ---\n\n")

# Create data with clear heterogeneity (different effects across studies)
data1 <- data.frame(
  studlab = c("S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8"),
  treat1 = c("A", "A", "A", "A", "B", "B", "A", "A"),
  treat2 = c("B", "B", "B", "B", "C", "C", "C", "C"),
  TE = c(0.3, 0.8, 0.5, 1.0, 0.2, 0.6, 0.7, 1.2),  # Heterogeneous
  seTE = c(0.1, 0.1, 0.1, 0.1, 0.15, 0.15, 0.2, 0.2)
)

nma1 <- netmeta(
  TE = data1$TE,
  seTE = data1$seTE,
  treat1 = data1$treat1,
  treat2 = data1$treat2,
  studlab = data1$studlab,
  sm = "MD",
  common = FALSE,
  random = TRUE,
  method.tau = "REML",
  reference.group = "C"
)

cat("tau =", round(nma1$tau, 4), "\n\n")

v1 <- verify_netmeta_reml(nma1, tol = 1e-4)

test("REML verification passes (heterogeneous data)", v1$is_valid_reml)
test("Fixed effects score = 0", v1$tests$score_theta_zero$passed)
test("REML score for tau² satisfied", v1$tests$score_tau2_zero$passed)
test("Information matrix positive definite", v1$tests$positive_definite$passed)
test("tau² >= 0", v1$tests$tau2_nonnegative$passed)
test("Solution is unique", v1$tests$unique_solution$passed)
test("Matches GLS solution", v1$tests$gls_solution$passed)
test("REML is at maximum", v1$tests$is_maximum$passed)
test("tau² is non-trivial", nma1$tau > 0.01)

cat("\n")

# ============================================================
# TEST 2: Two-arm studies with tau² at boundary (no heterogeneity)
# ============================================================

cat("--- Test 2: Two-arm studies at boundary (tau² = 0) ---\n\n")

# Create homogeneous data
data2 <- data.frame(
  studlab = c("S1", "S2", "S3", "S4", "S5", "S6"),
  treat1 = c("A", "A", "A", "B", "B", "A"),
  treat2 = c("B", "B", "B", "C", "C", "C"),
  TE = c(0.5, 0.5, 0.5, 0.3, 0.3, 0.8),  # Very consistent
  seTE = c(0.1, 0.15, 0.12, 0.2, 0.18, 0.25)
)

nma2 <- netmeta(
  TE = data2$TE,
  seTE = data2$seTE,
  treat1 = data2$treat1,
  treat2 = data2$treat2,
  studlab = data2$studlab,
  sm = "MD",
  common = FALSE,
  random = TRUE,
  method.tau = "REML",
  reference.group = "C"
)

cat("tau =", round(nma2$tau, 6), "(at boundary)\n\n")

v2 <- verify_netmeta_reml(nma2, tol = 1e-4)

test("REML verification passes (boundary)", v2$is_valid_reml)
test("tau² is at boundary", nma2$tau < 1e-4)
test("Boundary condition handled", v2$tests$score_tau2_zero$at_boundary)
test("REML score <= 0 at boundary", v2$tests$score_tau2_zero$passed)

cat("\n")

# ============================================================
# TEST 3: Multi-arm study (expected to fail due to approximation)
# ============================================================

cat("--- Test 3: Multi-arm study (approximate method) ---\n\n")

data(Senn2013, package = "netmeta")

nma3 <- netmeta(
  TE = Senn2013$TE,
  seTE = Senn2013$seTE,
  treat1 = Senn2013$treat1,
  treat2 = Senn2013$treat2,
  studlab = Senn2013$studlab,
  sm = "MD",
  common = FALSE,
  random = TRUE,
  method.tau = "REML",
  reference.group = "plac"
)

cat("tau =", round(nma3$tau, 4), "\n\n")

v3 <- verify_netmeta_reml(nma3, tol = 1e-4)

# Expected to fail because netmeta uses approximate method for multi-arm
test("Multi-arm verification fails (expected)", !v3$is_valid_reml)
test("Info matrix still positive definite", v3$tests$positive_definite$passed)
test("Solution still unique", v3$tests$unique_solution$passed)
test("tau² still non-negative", v3$tests$tau2_nonnegative$passed)

cat("\n")

# ============================================================
# TEST 4: REML components
# ============================================================

cat("--- Test 4: REML log-likelihood and score ---\n\n")

# Use the heterogeneous data
design <- build_design_matrix(data1$treat1, data1$treat2, "C")
X <- design$X

# Test REML log-likelihood function
loglik_0 <- reml_loglik(0, data1$TE, data1$seTE, X, data1$studlab, 
                         data1$treat1, data1$treat2)
loglik_1 <- reml_loglik(0.1, data1$TE, data1$seTE, X, data1$studlab,
                         data1$treat1, data1$treat2)

test("REML loglik computes", is.finite(loglik_0))
test("REML loglik changes with tau²", loglik_0 != loglik_1)

# Test REML score function  
score_0 <- reml_score_tau2(0, data1$TE, data1$seTE, X, data1$studlab,
                            data1$treat1, data1$treat2)
score_at_estimate <- reml_score_tau2(nma1$tau^2, data1$TE, data1$seTE, X,
                                      data1$studlab, data1$treat1, data1$treat2)

test("REML score computes", is.finite(score_0))
test("Score at estimate is near zero", abs(score_at_estimate) < 1e-3)

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
