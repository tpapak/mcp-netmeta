#' Random-Effect Network Meta-Analysis REML Verifier
#'
#' Verifies that random-effects NMA results satisfy the REML (Restricted
#' Maximum Likelihood) conditions without re-running the analysis.
#'
#' REML estimation involves two sets of conditions:
#' 1. Fixed effects (θ): Score equations for treatment effects given τ²
#' 2. Variance component (τ²): REML score equation for heterogeneity
#'
#' The REML approach:
#' - Maximizes the likelihood of residuals (not raw data)
#' - Provides unbiased estimates of τ²
#' - Is the default method in netmeta
#'
#' Dependencies:
#'   - netmeta: Network meta-analysis
#'   - multiarmvars: Arm variance decomposition
#'   - igraph: Graph structures

library(netmeta)
library(multiarmvars)
library(igraph)

# Source the fixed-effect verifier for shared functions
# (Assumes it's in the same directory)
if (file.exists("verifiers/verify_fixed_effect_mle.R")) {
  source("verifiers/verify_fixed_effect_mle.R")
} else if (file.exists("verify_fixed_effect_mle.R")) {
  source("verify_fixed_effect_mle.R")
}

#' Build weight matrix for random effects model
#'
#' In random effects, the weight matrix is:
#'   W(τ²) = (V + τ²I)^{-1}
#' where V is the within-study covariance matrix.
#'
#' @param seTE Vector of standard errors
#' @param studlab Vector of study labels
#' @param treat1 Vector of first treatments
#' @param treat2 Vector of second treatments
#' @param tau2 Between-study variance (τ²)
#' @param tol Tolerance for arm variance recovery
#' @return Weight matrix W
build_random_weight_matrix <- function(seTE, studlab, treat1, treat2, 
                                        tau2, tol = 1e-6) {
  n <- length(seTE)
  
  # Start with within-study variances
  V <- diag(seTE^2)
  
  # Add covariances for multi-arm studies (same as fixed effect)
  study_counts <- table(studlab)
  multi_arm_studies <- names(study_counts[study_counts > 1])
  
  for (study in multi_arm_studies) {
    idx <- which(studlab == study)
    trts_in_study <- unique(c(treat1[idx], treat2[idx]))
    
    if (length(trts_in_study) > 2) {
      # Recover arm variances
      edges <- c(rbind(as.character(treat1[idx]), as.character(treat2[idx])))
      g <- make_graph(edges, directed = FALSE)
      E(g)$variance <- seTE[idx]^2
      
      if (is_connected(g)) {
        arm_vars <- tryCatch(arm_variances(g), error = function(e) NULL)
        
        if (!is.null(arm_vars)) {
          arm_var_vec <- as.numeric(arm_vars)
          names(arm_var_vec) <- V(g)$name
          
          n_idx <- length(idx)
          for (a in 1:(n_idx - 1)) {
            for (b in (a + 1):n_idx) {
              i <- idx[a]
              j <- idx[b]
              
              trts_a <- c(as.character(treat1[i]), as.character(treat2[i]))
              trts_b <- c(as.character(treat1[j]), as.character(treat2[j]))
              shared <- intersect(trts_a, trts_b)
              
              if (length(shared) == 1) {
                cov_val <- arm_var_vec[shared]
                V[i, j] <- cov_val
                V[j, i] <- cov_val
              }
            }
          }
        }
      }
    }
  }
  
  # Add τ² to diagonal (between-study variance)
  V_total <- V + tau2 * diag(n)
  
  # Weight matrix is inverse of total variance
  W <- solve(V_total)
  
  return(W)
}


#' Compute REML profile log-likelihood
#'
#' The REML log-likelihood (up to a constant) is:
#'   ℓ_R(τ²) = -0.5 * [log|V + τ²I| + log|X'W(τ²)X| + r'W(τ²)r]
#'
#' where r = y - Xθ̂(τ²) are the residuals.
#'
#' @param tau2 Between-study variance
#' @param TE Observed effects
#' @param seTE Standard errors
#' @param X Design matrix
#' @param studlab Study labels
#' @param treat1 First treatments
#' @param treat2 Second treatments
#' @return REML log-likelihood value
reml_loglik <- function(tau2, TE, seTE, X, studlab, treat1, treat2) {
  n <- length(TE)
  p <- ncol(X)
  
  # Build weight matrix
  W <- build_random_weight_matrix(seTE, studlab, treat1, treat2, tau2)
  
  # Total variance matrix
  V_total <- solve(W)
  
  # Information matrix
  XtWX <- t(X) %*% W %*% X
  
  # GLS estimate of θ given τ²
  theta_hat <- solve(XtWX) %*% t(X) %*% W %*% TE
  
  # Residuals
  r <- TE - X %*% theta_hat
  
  # REML log-likelihood components
  log_det_V <- determinant(V_total, logarithm = TRUE)$modulus
  log_det_XtWX <- determinant(XtWX, logarithm = TRUE)$modulus
  quad_form <- as.numeric(t(r) %*% W %*% r)
  
  # REML log-likelihood (up to constant)
  loglik <- -0.5 * (log_det_V + log_det_XtWX + quad_form)
  
  return(as.numeric(loglik))
}


#' Compute REML score for τ²
#'
#' The REML score equation for τ² is:
#'   U(τ²) = -0.5 * [tr(PW) - r'PWPr] = 0
#'
#' where P = W - W*X*(X'WX)^{-1}*X'W is the projection matrix.
#'
#' @param tau2 Between-study variance
#' @param TE Observed effects
#' @param seTE Standard errors
#' @param X Design matrix
#' @param studlab Study labels
#' @param treat1 First treatments
#' @param treat2 Second treatments
#' @return REML score value
reml_score_tau2 <- function(tau2, TE, seTE, X, studlab, treat1, treat2) {
  n <- length(TE)
  
  # Build weight matrix
  W <- build_random_weight_matrix(seTE, studlab, treat1, treat2, tau2)
  
  # Information matrix and its inverse
  XtWX <- t(X) %*% W %*% X
  XtWX_inv <- solve(XtWX)
  
  # GLS estimate
  theta_hat <- XtWX_inv %*% t(X) %*% W %*% TE
  
  # Residuals
  r <- TE - X %*% theta_hat
  
  # Projection matrix P = W - W*X*(X'WX)^{-1}*X'W
  WX <- W %*% X
  P <- W - WX %*% XtWX_inv %*% t(WX)
  
  # Derivative of V_total with respect to τ² is I (identity)
  # So dW/dτ² = -W * I * W = -W²
  
  # REML score: -0.5 * [tr(P) - r'P²r]
  # Simplified form for τ²: tr(P) - r'P*P*r
  trace_P <- sum(diag(P))
  quad_P <- as.numeric(t(r) %*% P %*% P %*% r)
  
  score <- -0.5 * (trace_P - quad_P)
  
  return(score)
}


#' Verify random-effects NMA satisfies REML conditions
#'
#' Checks:
#' 1. Fixed effects score = 0 (given τ²)
#' 2. REML score for τ² = 0
#' 3. Information matrices are positive definite
#' 4. Solution is unique
#'
#' @param TE Vector of observed treatment effects
#' @param seTE Vector of standard errors
#' @param treat1 Vector of first treatments
#' @param treat2 Vector of second treatments
#' @param studlab Vector of study labels
#' @param league_table Matrix of estimated effects (random effects)
#' @param tau2 Estimated between-study variance
#' @param reference Reference treatment
#' @param tol Numerical tolerance
#' @param tol_multiarm Tolerance for multi-arm consistency
#' @return List with verification results
verify_random_effect_reml <- function(TE, seTE, treat1, treat2, studlab,
                                       league_table, tau2, reference,
                                       tol = 1e-4,
                                       tol_multiarm = 1e-4) {
  
  # Build design matrix
  design <- build_design_matrix(treat1, treat2, reference)
  X <- design$X
  n_params <- design$n_params
  n <- length(TE)
  
  # Build weight matrix with estimated τ²
  W <- build_random_weight_matrix(seTE, studlab, treat1, treat2, tau2, tol_multiarm)
  
  # Extract estimates
  beta_hat <- extract_estimates(league_table, reference)
  beta_hat <- beta_hat[colnames(X)]
  
  # ========== TEST 1: Fixed effects score = 0 ==========
  # At REML solution: X'W(τ²)(y - Xθ) = 0
  
  y_hat <- X %*% beta_hat
  residuals <- TE - y_hat
  score_theta <- t(X) %*% W %*% residuals
  
  max_score_theta <- max(abs(score_theta))
  score_theta_ok <- max_score_theta < tol
  
  # ========== TEST 2: REML score for τ² = 0 ==========
  # At the boundary (τ² = 0), the score doesn't need to be zero,
  # but must be non-positive (can't decrease by going more negative)
  
  score_tau2 <- reml_score_tau2(tau2, TE, seTE, X, studlab, treat1, treat2)
  
  if (tau2 < tol) {
    # At boundary: score should be <= 0 (or we'd want to go negative)
    score_tau2_ok <- score_tau2 <= tol
    at_boundary <- TRUE
  } else {
    # Interior: score should be zero
    score_tau2_ok <- abs(score_tau2) < tol
    at_boundary <- FALSE
  }
  
  # ========== TEST 3: Information matrix positive definite ==========
  
  info_matrix <- t(X) %*% W %*% X
  eigenvalues <- eigen(info_matrix, symmetric = TRUE, only.values = TRUE)$values
  min_eigenvalue <- min(eigenvalues)
  info_ok <- min_eigenvalue > tol * 1e-4
  
  # ========== TEST 4: τ² is non-negative ==========
  
  tau2_ok <- tau2 >= 0
  
  # ========== TEST 5: Solution is unique ==========
  
  rank <- qr(info_matrix, tol = tol * 1e-4)$rank
  unique_ok <- rank == n_params
  
  # ========== TEST 6: Verify GLS solution ==========
  # θ̂ = (X'WX)^{-1}X'Wy
  
  beta_gls <- solve(info_matrix) %*% t(X) %*% W %*% TE
  max_diff <- max(abs(beta_hat - beta_gls))
  gls_ok <- max_diff < tol
  
  # ========== TEST 7: Check REML is at maximum ==========
  # Verify loglik decreases when τ² is perturbed
  
  loglik_at_tau2 <- reml_loglik(tau2, TE, seTE, X, studlab, treat1, treat2)
  
  # Perturb τ² slightly
  delta <- max(0.001, tau2 * 0.01)
  loglik_plus <- reml_loglik(tau2 + delta, TE, seTE, X, studlab, treat1, treat2)
  loglik_minus <- reml_loglik(max(0, tau2 - delta), TE, seTE, X, studlab, treat1, treat2)
  
  is_maximum <- (loglik_at_tau2 >= loglik_plus - tol) && 
                (loglik_at_tau2 >= loglik_minus - tol)
  
  # ========== Results ==========
  
  all_passed <- score_theta_ok && score_tau2_ok && info_ok && 
                tau2_ok && unique_ok && gls_ok && is_maximum
  
  list(
    is_valid_reml = all_passed,
    is_unique = unique_ok,
    
    tests = list(
      score_theta_zero = list(
        passed = score_theta_ok,
        property = "Fixed effects score = 0",
        description = "Gradient w.r.t. treatment effects is zero",
        max_score_component = max_score_theta,
        score_vector = as.numeric(score_theta),
        tolerance = tol
      ),
      
      score_tau2_zero = list(
        passed = score_tau2_ok,
        property = if (at_boundary) "REML score for tau² <= 0 (at boundary)" 
                   else "REML score for tau² = 0",
        description = if (at_boundary) 
          "At boundary tau²=0, gradient must be non-positive" 
          else "Gradient w.r.t. heterogeneity variance is zero",
        score_value = score_tau2,
        at_boundary = at_boundary,
        tolerance = tol
      ),
      
      positive_definite = list(
        passed = info_ok,
        property = "Information matrix positive definite",
        description = "Hessian confirms this is a maximum for theta",
        min_eigenvalue = min_eigenvalue,
        tolerance = tol * 1e-4
      ),
      
      tau2_nonnegative = list(
        passed = tau2_ok,
        property = "tau² >= 0",
        description = "Heterogeneity variance is non-negative",
        tau2 = tau2
      ),
      
      unique_solution = list(
        passed = unique_ok,
        property = "Unique solution",
        description = "Network is connected, treatment effects are unique",
        rank = rank,
        n_params = n_params
      ),
      
      gls_solution = list(
        passed = gls_ok,
        property = "Matches GLS solution",
        description = "Estimates equal (X'WX)^{-1} X'Wy given tau²",
        max_difference = max_diff,
        tolerance = tol
      ),
      
      is_maximum = list(
        passed = is_maximum,
        property = "REML is at maximum",
        description = "Log-likelihood decreases when tau² is perturbed",
        loglik_at_tau2 = loglik_at_tau2,
        loglik_plus = loglik_plus,
        loglik_minus = loglik_minus
      )
    ),
    
    summary = list(
      n_observations = n,
      n_parameters = n_params,
      n_studies = length(unique(studlab)),
      treatments = design$treatments,
      reference = reference,
      tau2 = tau2,
      tau = sqrt(tau2)
    ),
    
    tolerance = tol,
    tolerance_multiarm = tol_multiarm
  )
}


#' Wrapper for netmeta objects
#'
#' @param nma A netmeta object with random = TRUE
#' @param tol Tolerance for REML conditions
#' @param tol_multiarm Tolerance for multi-arm consistency
#' @return Verification results
verify_netmeta_reml <- function(nma, tol = 1e-4, tol_multiarm = 1e-4) {
  if (!nma$random) {
    stop("netmeta object must have random = TRUE")
  }
  
  reference <- nma$reference.group
  if (is.null(reference) || reference == "") {
    reference <- nma$trts[1]
  }
  
  verify_random_effect_reml(
    TE = nma$TE,
    seTE = nma$seTE,
    treat1 = nma$treat1,
    treat2 = nma$treat2,
    studlab = nma$studlab,
    league_table = nma$TE.random,
    tau2 = nma$tau^2,
    reference = reference,
    tol = tol,
    tol_multiarm = tol_multiarm
  )
}


#' Print REML verification results
print_reml_verification <- function(v) {
  cat("\n")
  cat("=== Random-Effect NMA REML Verification ===\n\n")
  
  cat(sprintf("Observations: %d\n", v$summary$n_observations))
  cat(sprintf("Studies: %d\n", v$summary$n_studies))
  cat(sprintf("Parameters: %d\n", v$summary$n_parameters))
  cat(sprintf("Treatments: %s\n", paste(v$summary$treatments, collapse = ", ")))
  cat(sprintf("Reference: %s\n", v$summary$reference))
  cat(sprintf("tau²: %.6f (tau = %.4f)\n", v$summary$tau2, v$summary$tau))
  cat(sprintf("Tolerance: %.2e\n\n", v$tolerance))
  
  cat("--- Tests ---\n\n")
  
  for (name in names(v$tests)) {
    test <- v$tests[[name]]
    status <- if (test$passed) "PASS" else "FAIL"
    cat(sprintf("[%s] %s\n", status, test$property))
    cat(sprintf("       %s\n", test$description))
  }
  
  cat("\n")
  n_passed <- sum(sapply(v$tests, function(t) t$passed))
  cat(sprintf("Result: %d/%d tests passed\n\n", n_passed, length(v$tests)))
  
  if (v$is_valid_reml) {
    cat("CONCLUSION: Output satisfies REML conditions.\n")
  } else {
    cat("CONCLUSION: Verification FAILED.\n")
  }
  cat("\n")
}


# ============================================================
# Example
# ============================================================

if (sys.nframe() == 0) {
  
  cat("Random-Effect NMA REML Verifier\n")
  cat("===============================\n\n")
  
  # Load example data
  data(Senn2013, package = "netmeta")
  
  # Run NMA with random effects
  nma <- netmeta(
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
  
  cat("NMA completed. tau =", round(nma$tau, 4), "\n\n")
  
  # Verify REML conditions
  v <- verify_netmeta_reml(nma, tol = 1e-4)
  print_reml_verification(v)
  
  # Show detailed results
  cat("--- Detailed Results ---\n\n")
  cat("Fixed effects score vector:\n")
  print(round(v$tests$score_theta_zero$score_vector, 6))
  
  cat("\nREML score for tau²:", v$tests$score_tau2_zero$score_value, "\n")
  
  cat("\nREML log-likelihood at tau²:", 
      round(v$tests$is_maximum$loglik_at_tau2, 4), "\n")
  cat("  At tau² + delta:", round(v$tests$is_maximum$loglik_plus, 4), "\n")
  cat("  At tau² - delta:", round(v$tests$is_maximum$loglik_minus, 4), "\n")
}
