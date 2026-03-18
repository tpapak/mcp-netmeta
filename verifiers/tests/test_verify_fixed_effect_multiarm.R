#' Tests for Fixed-Effect NMA MLE Verifier with Multiple Multi-arm Studies
#'
#' Uses Dong2013 dataset (41 studies: 7 four-arm, 3 three-arm, 31 two-arm)
#' and smokingcessation dataset (24 studies: 2 three-arm, 22 two-arm)
#'
#' Run with: Rscript verifiers/tests/test_verify_fixed_effect_multiarm.R
#' Or from R: source("verifiers/tests/test_verify_fixed_effect_multiarm.R")

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
cat("  Tests for Fixed-Effect MLE Verifier\n")
cat("  Datasets with multiple multi-arm studies\n")
cat("====================================================\n\n")

# ============================================================
# Load and prepare Dong2013 dataset
# ============================================================

data(Dong2013, package = "netmeta")

# Convert arm-level binary data to pairwise contrasts
# Use incr=0.5 and allstudies=TRUE to handle zero-event arms
pw_all <- pairwise(
  treat = treatment,
  event = death,
  n = randomized,
  studlab = id,
  data = Dong2013,
  sm = "OR",
  incr = 0.5,
  allstudies = TRUE
)
pw_all <- pw_all[!is.na(pw_all$TE), ]

cat(sprintf("Dong2013: %d contrasts from %d studies, %d treatments\n",
            nrow(pw_all), length(unique(pw_all$studlab)),
            length(unique(c(as.character(pw_all$treat1), as.character(pw_all$treat2))))))
cat(sprintf("Treatments: %s\n",
            paste(sort(unique(c(as.character(pw_all$treat1), as.character(pw_all$treat2)))),
                  collapse = ", ")))

# Count multi-arm studies
study_counts <- table(as.character(pw_all$studlab))
multi_studies <- names(study_counts[study_counts > 1])
n_multiarm_3plus <- 0
for (s in multi_studies) {
  idx <- which(as.character(pw_all$studlab) == s)
  trts <- unique(c(as.character(pw_all$treat1[idx]), as.character(pw_all$treat2[idx])))
  if (length(trts) > 2) n_multiarm_3plus <- n_multiarm_3plus + 1
}
cat(sprintf("Multi-arm studies (3+ arms): %d\n\n", n_multiarm_3plus))

# ============================================================
# TEST 1: Covariance matrix singularity with complete multi-arm data
#
# When pairwise() produces all C(k,2) contrasts for a k-arm study,
# the resulting covariance matrix V is singular because only k-1
# contrasts are independent. This is expected behaviour.
# ============================================================

cat("--- Test 1: Covariance matrix with complete multi-arm data ---\n\n")

cov_result <- build_covariance_matrix(
  seTE = pw_all$seTE,
  studlab = as.character(pw_all$studlab),
  treat1 = as.character(pw_all$treat1),
  treat2 = as.character(pw_all$treat2)
)

test("Covariance matrix V is constructed", !is.null(cov_result$V))
test("V has correct dimensions", all(dim(cov_result$V) == c(nrow(pw_all), nrow(pw_all))))
test("Multi-arm studies detected", cov_result$has_multiarm)
test("Arm variances are consistent", cov_result$multiarm_consistent)

# V is singular because redundant contrasts are included
eig <- eigen(cov_result$V, symmetric = TRUE, only.values = TRUE)$values
n_zero_eig <- sum(abs(eig) < 1e-10)
cat(sprintf("  V has %d near-zero eigenvalues (redundant contrasts)\n", n_zero_eig))
test("V is singular (expected with complete multi-arm contrasts)", is.null(cov_result$W))

cat("\n")

# ============================================================
# TEST 2: Multi-arm arm variance recovery on all Dong2013 studies
# ============================================================

cat("--- Test 2: Arm variance recovery per multi-arm study ---\n\n")

for (s in multi_studies) {
  idx <- which(as.character(pw_all$studlab) == s)
  trts <- unique(c(as.character(pw_all$treat1[idx]), as.character(pw_all$treat2[idx])))
  if (length(trts) <= 2) next

  arm_result <- recover_arm_variances(
    treatments = trts,
    treat1 = as.character(pw_all$treat1[idx]),
    treat2 = as.character(pw_all$treat2[idx]),
    seTE = pw_all$seTE[idx]
  )

  test(sprintf("Study %s (%d-arm): arm variances recovered", s, arm_result$n_arms),
       arm_result$is_solvable)
  test(sprintf("Study %s (%d-arm): variances consistent", s, arm_result$n_arms),
       arm_result$is_consistent)

  if (arm_result$n_arms == 4) {
    test(sprintf("Study %s: 6 contrasts (complete 4-arm)", s),
         arm_result$n_contrasts == 6)
  } else if (arm_result$n_arms == 3) {
    test(sprintf("Study %s: 3 contrasts (complete 3-arm)", s),
         arm_result$n_contrasts == 3)
  }
}

cat("\n")

# ============================================================
# TEST 3: Verification using independent contrasts
#
# For multi-arm studies, keep only k-1 contrasts per k-arm study
# (those sharing a common reference arm within the study).
# This makes V non-singular and allows exact MLE computation.
# ============================================================

cat("--- Test 3: Exact MLE with independent contrasts (Dong2013) ---\n\n")

# Select k-1 independent contrasts per multi-arm study
keep <- rep(TRUE, nrow(pw_all))
for (s in multi_studies) {
  idx <- which(as.character(pw_all$studlab) == s)
  trts <- unique(c(as.character(pw_all$treat1[idx]), as.character(pw_all$treat2[idx])))
  if (length(trts) <= 2) next

  # Keep only contrasts involving the alphabetically first treatment
  ref_trt <- sort(trts)[1]
  for (i in idx) {
    t1 <- as.character(pw_all$treat1[i])
    t2 <- as.character(pw_all$treat2[i])
    if (!(t1 == ref_trt || t2 == ref_trt)) {
      keep[i] <- FALSE
    }
  }
}
pw_indep <- pw_all[keep, ]

cat(sprintf("Independent contrasts: %d (from %d total)\n",
            nrow(pw_indep), nrow(pw_all)))

# Compute exact MLE on independent contrasts
exact_indep <- compute_exact_mle(
  TE = pw_indep$TE,
  seTE = pw_indep$seTE,
  treat1 = as.character(pw_indep$treat1),
  treat2 = as.character(pw_indep$treat2),
  studlab = as.character(pw_indep$studlab),
  reference = "Placebo"
)

test("Exact MLE computed successfully (independent contrasts)", !is.null(exact_indep$league_table))

# Verify
v_indep <- verify_fixed_effect_mle(
  TE = pw_indep$TE,
  seTE = pw_indep$seTE,
  treat1 = as.character(pw_indep$treat1),
  treat2 = as.character(pw_indep$treat2),
  studlab = as.character(pw_indep$studlab),
  league_table = exact_indep$league_table,
  reference = "Placebo"
)

test("Exact MLE passes all verification tests", v_indep$is_valid_mle)
test("Score equations are zero", v_indep$tests$score_zero$passed)
test("Information matrix is positive definite", v_indep$tests$positive_definite$passed)
test("Solution is unique", v_indep$tests$unique_solution$passed)
test("Matches WLS solution", v_indep$tests$wls_solution$passed)

cat("\n")

# ============================================================
# TEST 4: League table properties
# ============================================================

cat("--- Test 4: League table properties ---\n\n")

lt <- exact_indep$league_table
trts_all <- rownames(lt)

# Antisymmetry: lt[i,j] = -lt[j,i]
max_antisym_err <- 0
for (i in seq_along(trts_all)) {
  for (j in seq_along(trts_all)) {
    err <- abs(lt[i, j] + lt[j, i])
    if (err > max_antisym_err) max_antisym_err <- err
  }
}
test("League table is antisymmetric (lt[i,j] = -lt[j,i])", max_antisym_err < 1e-10)

# Diagonal = 0
test("League table diagonal is zero", all(abs(diag(lt)) < 1e-10))

# Transitivity: lt[A,C] = lt[A,B] + lt[B,C]
max_trans_err <- 0
for (i in seq_along(trts_all)) {
  for (j in seq_along(trts_all)) {
    for (k in seq_along(trts_all)) {
      err <- abs(lt[i, k] - (lt[i, j] + lt[j, k]))
      if (err > max_trans_err) max_trans_err <- err
    }
  }
}
test("League table satisfies transitivity", max_trans_err < 1e-10)

cat("\n")

# ============================================================
# TEST 5: netmeta comparison on Dong2013
# ============================================================

cat("--- Test 5: netmeta vs exact MLE comparison (Dong2013) ---\n\n")

# Run netmeta on the full data (it handles multi-arm internally)
nma <- netmeta(
  TE = pw_all$TE,
  seTE = pw_all$seTE,
  treat1 = as.character(pw_all$treat1),
  treat2 = as.character(pw_all$treat2),
  studlab = as.character(pw_all$studlab),
  sm = "OR",
  common = TRUE,
  random = FALSE,
  reference.group = "Placebo"
)

# Compare netmeta (full data) with exact MLE (independent contrasts)
# They won't match exactly because they use different contrast sets
# and netmeta uses its own multi-arm approximation
trts_non_ref <- sort(setdiff(trts_all, "Placebo"))
cat(sprintf("%-15s %12s %12s %12s\n", "Treatment", "Exact MLE", "netmeta", "Difference"))
cat(sprintf("%-15s %12s %12s %12s\n", "----------", "---------", "-------", "----------"))
max_diff <- 0
for (trt in trts_non_ref) {
  exact_est <- exact_indep$league_table[trt, "Placebo"]
  netmeta_est <- nma$TE.common[trt, "Placebo"]
  diff <- abs(exact_est - netmeta_est)
  if (diff > max_diff) max_diff <- diff
  cat(sprintf("%-15s %12.6f %12.6f %12.6f\n", trt, exact_est, netmeta_est, diff))
}

cat(sprintf("\nMax difference: %.6f\n", max_diff))
test("netmeta and exact MLE estimates are close (< 0.5)", max_diff < 0.5)

cat("\n")

# ============================================================
# TEST 6: smokingcessation dataset (2 three-arm studies)
# ============================================================

cat("--- Test 6: smokingcessation dataset ---\n\n")

smoke_json <- jsonlite::fromJSON("examples/smokingcessation.json")
smoke_d <- smoke_json$data

smoke_data <- data.frame(
  studlab = smoke_d$study,
  treat1 = smoke_d$treat1,
  treat2 = smoke_d$treat2,
  TE = smoke_d$TE,
  seTE = smoke_d$seTE,
  stringsAsFactors = FALSE
)

cat(sprintf("smokingcessation: %d contrasts from %d studies\n",
            nrow(smoke_data), length(unique(smoke_data$studlab))))

# This dataset has complete 3-arm studies (3 contrasts each)
# so V will be singular. Use independent contrasts.
sc <- table(smoke_data$studlab)
multi_smoke <- names(sc[sc > 1])
keep_smoke <- rep(TRUE, nrow(smoke_data))

for (s in multi_smoke) {
  idx <- which(smoke_data$studlab == s)
  trts <- unique(c(smoke_data$treat1[idx], smoke_data$treat2[idx]))
  if (length(trts) <= 2) next
  ref_trt <- sort(trts)[1]
  for (i in idx) {
    t1 <- smoke_data$treat1[i]
    t2 <- smoke_data$treat2[i]
    if (!(t1 == ref_trt || t2 == ref_trt)) {
      keep_smoke[i] <- FALSE
    }
  }
}
smoke_indep <- smoke_data[keep_smoke, ]

cat(sprintf("Independent contrasts: %d (from %d total)\n\n",
            nrow(smoke_indep), nrow(smoke_data)))

# Compute exact MLE
exact_smoke <- compute_exact_mle(
  TE = smoke_indep$TE,
  seTE = smoke_indep$seTE,
  treat1 = smoke_indep$treat1,
  treat2 = smoke_indep$treat2,
  studlab = smoke_indep$studlab,
  reference = "No contact"
)

# Verify
v_smoke <- verify_fixed_effect_mle(
  TE = smoke_indep$TE,
  seTE = smoke_indep$seTE,
  treat1 = smoke_indep$treat1,
  treat2 = smoke_indep$treat2,
  studlab = smoke_indep$studlab,
  league_table = exact_smoke$league_table,
  reference = "No contact"
)

test("smokingcessation: Exact MLE passes verification", v_smoke$is_valid_mle)
test("smokingcessation: Score equations zero", v_smoke$tests$score_zero$passed)
test("smokingcessation: Information matrix positive definite", v_smoke$tests$positive_definite$passed)
test("smokingcessation: Solution is unique", v_smoke$tests$unique_solution$passed)
test("smokingcessation: Matches WLS solution", v_smoke$tests$wls_solution$passed)

# Check multi-arm detection
test("smokingcessation: Multi-arm studies detected", v_smoke$tests$multiarm_consistent$has_multiarm)

cat("\n")

# ============================================================
# TEST 7: Verify covariance matrix singularity is the ONLY
#          reason compute_exact_mle fails on full Dong2013 data
# ============================================================

cat("--- Test 7: Diagnose full-data failure (Dong2013) ---\n\n")

# build_covariance_matrix succeeds (builds V) but W = solve(V) fails
cov_full <- build_covariance_matrix(
  seTE = pw_all$seTE,
  studlab = as.character(pw_all$studlab),
  treat1 = as.character(pw_all$treat1),
  treat2 = as.character(pw_all$treat2)
)

test("Full V matrix constructed successfully", !is.null(cov_full$V))
test("W = solve(V) fails (V is singular)", is.null(cov_full$W))
test("All multi-arm arm variances are consistent", cov_full$multiarm_consistent)

# Count the rank deficiency
# For a k-arm study with C(k,2) contrasts, the covariance block has rank k,
# so nullity = C(k,2) - k. Only studies with k >= 4 contribute nullity.
# 3-arm: rank 3, nullity 0 (block is full rank)
# 4-arm: rank 4, nullity 2
eig_full <- eigen(cov_full$V, symmetric = TRUE, only.values = TRUE)$values
rank_V <- sum(abs(eig_full) > 1e-10)
nullity_V <- nrow(pw_all) - rank_V

# Compute expected nullity from multi-arm study structure
expected_nullity <- 0
for (s in multi_studies) {
  idx <- which(as.character(pw_all$studlab) == s)
  trts <- unique(c(as.character(pw_all$treat1[idx]), as.character(pw_all$treat2[idx])))
  k <- length(trts)
  if (k >= 4) {
    expected_nullity <- expected_nullity + (choose(k, 2) - k)
  }
}
cat(sprintf("  V rank: %d, nullity: %d, expected nullity: %d, total rows: %d\n",
            rank_V, nullity_V, expected_nullity, nrow(pw_all)))
test("V nullity matches expected (C(k,2)-k per k>=4 arm study)", nullity_V == expected_nullity)

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
