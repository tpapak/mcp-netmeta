#' Fixed-Effect Network Meta-Analysis MLE Verifier
#'
#' Verifies that NMA output (league table) is the unique MLE given the input data.
#' Handles multi-arm studies by reconstructing arm-level variances from contrasts
#' using the multiarmvars package (https://github.com/tpapak/multiarmvars).
#'
#' NOTE: This verifier uses the exact covariance structure derived from arm-level
#' variances. Some NMA software (including netmeta) uses an approximate method
#' that inflates variances to achieve approximate independence. The estimates
#' may differ slightly but both approaches are valid.
#'
#' Properties verified:
#' 1. Score equations = 0 (first-order optimality)
#' 2. Information matrix is positive definite (second-order condition)
#' 3. Solution is unique (network is connected)
#' 4. Multi-arm variance consistency (arm variances are consistent across contrasts)
#'
#' Dependencies:
#'   - netmeta: Network meta-analysis
#'   - multiarmvars: Arm variance decomposition (install with:
#'       remotes::install_github("tpapak/multiarmvars"))
#'   - igraph: Graph structures for multiarmvars

library(netmeta)
library(multiarmvars)
library(igraph)

#' Recover arm-level variances from contrast variances within a multi-arm study
#'
#' Uses the multiarmvars package to decompose contrast variances into arm-level
#' variances. For a k-arm study with contrasts d_ij, we have:
#'   Var(d_ij) = V_i + V_j
#'
#' Requirements for solvability:
#' - Minimum: n_contrasts >= k - 1 (connected graph of contrasts)
#' - Complete data: k(k-1)/2 contrasts (all pairs) - overdetermined, allows consistency check
#'
#' @param treatments Vector of treatment names in the study
#' @param treat1 Vector of first treatments for each contrast
#' @param treat2 Vector of second treatments for each contrast
#' @param seTE Vector of standard errors for each contrast
#' @param tol Tolerance for checking consistency in overdetermined systems
#' @return List with arm variances and consistency check
recover_arm_variances <- function(treatments, treat1, treat2, seTE, tol = 1e-6) {
  k <- length(treatments)
  n_contrasts <- length(treat1)
  n_complete <- k * (k - 1) / 2  # Number of contrasts if all pairs present
  min_contrasts <- k - 1
  
  if (k == 2) {
    # Two-arm study: can't uniquely determine arm variances
    # but we don't need them (no correlation)
    return(list(
      variances = NULL,
      is_consistent = TRUE,
      is_solvable = TRUE,
      n_arms = k,
      n_contrasts = n_contrasts,
      n_contrasts_complete = n_complete,
      n_contrasts_minimum = min_contrasts,
      residual = 0,
      message = "Two-arm study: no correlation to model"
    ))
  }
  
  # Check minimum contrasts required
  if (n_contrasts < min_contrasts) {
    return(list(
      variances = NULL,
      is_consistent = FALSE,
      is_solvable = FALSE,
      n_arms = k,
      n_contrasts = n_contrasts,
      n_contrasts_complete = n_complete,
      n_contrasts_minimum = min_contrasts,
      residual = NA,
      message = sprintf("Insufficient contrasts: have %d, need at least %d for %d-arm study",
                        n_contrasts, min_contrasts, k)
    ))
  }
  
  # Build igraph for multiarmvars
  # Create edge list from contrasts
  edges <- c(rbind(as.character(treat1), as.character(treat2)))
  g <- make_graph(edges, directed = FALSE)
  
  # Add variance as edge attribute
  E(g)$variance <- seTE^2
  
  # Check if graph is connected
  if (!is_connected(g)) {
    return(list(
      variances = NULL,
      is_consistent = FALSE,
      is_solvable = FALSE,
      n_arms = k,
      n_contrasts = n_contrasts,
      n_contrasts_complete = n_complete,
      n_contrasts_minimum = min_contrasts,
      residual = NA,
      message = "Contrasts don't form a connected graph: some treatments are isolated"
    ))
  }
  
  # Use multiarmvars to compute arm variances
  arm_vars_matrix <- tryCatch(
    arm_variances(g),
    error = function(e) NULL
  )
  
  if (is.null(arm_vars_matrix)) {
    return(list(
      variances = NULL,
      is_consistent = FALSE,
      is_solvable = FALSE,
      n_arms = k,
      n_contrasts = n_contrasts,
      n_contrasts_complete = n_complete,
      n_contrasts_minimum = min_contrasts,
      residual = NA,
      message = "multiarmvars::arm_variances failed to compute arm variances"
    ))
  }
  
  # Extract arm variances (result is a matrix with one column)
  arm_variance_values <- as.numeric(arm_vars_matrix)
  names(arm_variance_values) <- V(g)$name
  
  # Reorder to match input treatments order
  arm_variance_values <- arm_variance_values[treatments]
  
  # Verify consistency: check if recovered variances reproduce observed
  # Compute fitted contrast variances
  fitted_var <- numeric(n_contrasts)
  for (i in seq_len(n_contrasts)) {
    t1 <- as.character(treat1[i])
    t2 <- as.character(treat2[i])
    fitted_var[i] <- arm_variance_values[t1] + arm_variance_values[t2]
  }
  
  observed_var <- seTE^2
  residual <- sqrt(mean((observed_var - fitted_var)^2))  # RMSE
  max_residual <- max(abs(observed_var - fitted_var))
  
  # Check all variances are non-negative
  all_positive <- all(arm_variance_values >= -tol)
  
  # Determine system type
  if (n_contrasts == n_complete) {
    system_type <- "complete"
  } else if (n_contrasts > min_contrasts) {
    system_type <- "overdetermined"
  } else {
    system_type <- "exactly_determined"
  }
  
  is_consistent <- (max_residual < tol) && all_positive
  
  list(
    variances = arm_variance_values,
    is_consistent = is_consistent,
    is_solvable = TRUE,
    n_arms = k,
    n_contrasts = n_contrasts,
    n_contrasts_complete = n_complete,
    n_contrasts_minimum = min_contrasts,
    system_type = system_type,
    residual = residual,
    max_residual = max_residual,
    all_positive = all_positive,
    observed_var = observed_var,
    fitted_var = fitted_var,
    message = if (!is_consistent && !all_positive) {
      "Negative variance detected (data may be inconsistent)"
    } else if (!is_consistent) {
      sprintf("Contrast variances inconsistent (max residual: %.2e)", max_residual)
    } else if (system_type == "exactly_determined") {
      "Arm variances recovered (exactly determined, no consistency check possible)"
    } else {
      sprintf("Arm variances recovered and verified (%s system)", system_type)
    }
  )
}


#' Build covariance matrix for all observations
#'
#' Constructs the full covariance matrix accounting for within-study
#' correlations in multi-arm studies.
#'
#' @param seTE Vector of standard errors
#' @param studlab Vector of study labels
#' @param treat1 Vector of first treatments
#' @param treat2 Vector of second treatments
#' @param tol Tolerance for arm variance recovery
#' @return List with covariance matrix and diagnostics
build_covariance_matrix <- function(seTE, studlab, treat1, treat2, tol = 1e-6) {
  n <- length(seTE)
  
  # Start with diagonal (variances)
  V <- diag(seTE^2)
  
  # Track multi-arm study diagnostics
  multiarm_checks <- list()
  
  # Find multi-arm studies
  study_counts <- table(studlab)
  multi_arm_studies <- names(study_counts[study_counts > 1])
  
  if (length(multi_arm_studies) == 0) {
    return(list(
      V = V,
      W = diag(1 / seTE^2),
      has_multiarm = FALSE,
      multiarm_consistent = TRUE,
      multiarm_checks = list()
    ))
  }
  
  # Process each multi-arm study
  all_consistent <- TRUE
  
  for (study in multi_arm_studies) {
    idx <- which(studlab == study)
    
    # Get treatments in this study
    trts_in_study <- unique(c(treat1[idx], treat2[idx]))
    
    # Recover arm variances
    arm_result <- recover_arm_variances(
      treatments = trts_in_study,
      treat1 = treat1[idx],
      treat2 = treat2[idx],
      seTE = seTE[idx],
      tol = tol
    )
    
    multiarm_checks[[study]] <- arm_result
    
    if (!arm_result$is_consistent) {
      all_consistent <- FALSE
    }
    
    if (!is.null(arm_result$variances) && arm_result$is_consistent) {
      # Fill in covariances
      # Cov(d_ij, d_ik) = V_i (shared arm)
      # Cov(d_ij, d_kl) = 0 (no shared arm)
      
      n_idx <- length(idx)
      for (a in 1:(n_idx - 1)) {
        for (b in (a + 1):n_idx) {
          i <- idx[a]
          j <- idx[b]
          
          # Find shared treatment
          trts_a <- c(as.character(treat1[i]), as.character(treat2[i]))
          trts_b <- c(as.character(treat1[j]), as.character(treat2[j]))
          shared <- intersect(trts_a, trts_b)
          
          if (length(shared) == 1) {
            # Covariance = variance of shared arm
            cov_val <- arm_result$variances[shared]
            V[i, j] <- cov_val
            V[j, i] <- cov_val
          }
        }
      }
    }
  }
  
  # Compute weight matrix (inverse of covariance)
  W <- tryCatch(
    solve(V),
    error = function(e) {
      # If V is singular, return NULL
      NULL
    }
  )
  
  list(
    V = V,
    W = W,
    has_multiarm = TRUE,
    multiarm_consistent = all_consistent,
    multiarm_checks = multiarm_checks
  )
}


#' Build design matrix from input data
#'
#' @param treat1 Vector of first treatments
#' @param treat2 Vector of second treatments
#' @param reference Reference treatment
#' @return List with design matrix X and treatment info
build_design_matrix <- function(treat1, treat2, reference) {
  all_trts <- sort(unique(c(treat1, treat2)))
  n_obs <- length(treat1)
  
  non_ref <- setdiff(all_trts, reference)
  n_params <- length(non_ref)
  
  X <- matrix(0, nrow = n_obs, ncol = n_params)
  colnames(X) <- non_ref
  
  for (i in seq_len(n_obs)) {
    t1 <- as.character(treat1[i])
    t2 <- as.character(treat2[i])
    
    if (t1 %in% non_ref) X[i, t1] <- 1
    if (t2 %in% non_ref) X[i, t2] <- -1
  }
  
  list(
    X = X,
    treatments = all_trts,
    non_ref_treatments = non_ref,
    reference = reference,
    n_params = n_params
  )
}


#' Extract estimates from league table
#'
#' @param league_table Matrix of treatment effects (row vs column)
#' @param reference Reference treatment name
#' @return Named vector of effects vs reference
extract_estimates <- function(league_table, reference) {
  trts <- rownames(league_table)
  ref_idx <- which(trts == reference)
  beta_hat <- league_table[, ref_idx]
  beta_hat <- beta_hat[names(beta_hat) != reference]
  beta_hat
}


#' Verify fixed-effect NMA is the unique MLE
#'
#' @param TE Vector of observed treatment effects
#' @param seTE Vector of standard errors
#' @param treat1 Vector of first treatments
#' @param treat2 Vector of second treatments
#' @param studlab Vector of study labels
#' @param league_table Matrix of estimated effects (NMA output)
#' @param reference Reference treatment
#' @param tol Numerical tolerance for MLE conditions
#' @param tol_multiarm Tolerance for multi-arm variance consistency
#' @return List with verification results
verify_fixed_effect_mle <- function(TE, seTE, treat1, treat2, studlab,
                                     league_table, reference,
                                     tol = 1e-6,
                                     tol_multiarm = 1e-4) {
  
  # Build design matrix
  design <- build_design_matrix(treat1, treat2, reference)
  X <- design$X
  n_params <- design$n_params
  
  # Build covariance/weight matrix (handles multi-arm)
  cov_result <- build_covariance_matrix(seTE, studlab, treat1, treat2, tol_multiarm)
  W <- cov_result$W
  
  if (is.null(W)) {
    return(list(
      is_valid_mle = FALSE,
      error = "Could not compute weight matrix (covariance matrix singular)"
    ))
  }
  
  # Extract and reorder estimates
  beta_hat <- extract_estimates(league_table, reference)
  beta_hat <- beta_hat[colnames(X)]
  
  # ========== TEST 1: Score equations = 0 ==========
  y_hat <- X %*% beta_hat
  residuals <- TE - y_hat
  score <- t(X) %*% W %*% residuals
  
  max_score <- max(abs(score))
  score_ok <- max_score < tol
  
  # ========== TEST 2: Information matrix positive definite ==========
  info_matrix <- t(X) %*% W %*% X
  eigenvalues <- eigen(info_matrix, symmetric = TRUE, only.values = TRUE)$values
  min_eigenvalue <- min(eigenvalues)
  
  info_ok <- min_eigenvalue > tol * 1e-4
  
  # ========== TEST 3: Unique solution (full rank) ==========
  rank <- qr(info_matrix, tol = tol * 1e-4)$rank
  unique_ok <- rank == n_params
  
  # ========== TEST 4: Verify WLS solution ==========
  beta_wls <- solve(info_matrix) %*% t(X) %*% W %*% TE
  max_diff <- max(abs(beta_hat - beta_wls))
  wls_ok <- max_diff < tol
  
  # ========== TEST 5: Multi-arm consistency ==========
  multiarm_ok <- cov_result$multiarm_consistent
  
  # ========== Results ==========
  all_passed <- score_ok && info_ok && unique_ok && wls_ok && multiarm_ok
  
  list(
    is_valid_mle = all_passed,
    is_unique = unique_ok,
    
    tests = list(
      score_zero = list(
        passed = score_ok,
        property = "Score equations = 0",
        description = "Gradient of log-likelihood is zero at solution",
        max_score_component = max_score,
        score_vector = as.numeric(score),
        tolerance = tol
      ),
      
      positive_definite = list(
        passed = info_ok,
        property = "Information matrix positive definite",
        description = "Hessian confirms this is a maximum",
        min_eigenvalue = min_eigenvalue,
        all_eigenvalues = eigenvalues,
        tolerance = tol * 1e-4
      ),
      
      unique_solution = list(
        passed = unique_ok,
        property = "Unique solution",
        description = "Network is connected, solution is unique",
        rank = rank,
        n_params = n_params,
        condition_number = max(eigenvalues) / min_eigenvalue,
        tolerance = tol * 1e-4
      ),
      
      wls_solution = list(
        passed = wls_ok,
        property = "Matches WLS solution",
        description = "Estimates equal (X'WX)^{-1} X'Wy",
        max_difference = max_diff,
        tolerance = tol
      ),
      
      multiarm_consistent = list(
        passed = multiarm_ok,
        property = "Multi-arm variance consistency",
        description = "Contrast variances consistent with arm-level variances",
        has_multiarm = cov_result$has_multiarm,
        details = cov_result$multiarm_checks,
        tolerance = tol_multiarm
      )
    ),
    
    summary = list(
      n_observations = length(TE),
      n_parameters = n_params,
      n_studies = length(unique(studlab)),
      n_multiarm = sum(table(studlab) > 1),
      treatments = design$treatments,
      reference = reference
    ),
    
    tolerance = tol,
    tolerance_multiarm = tol_multiarm
  )
}


#' Wrapper for netmeta objects
#'
#' @param nma A netmeta object with common = TRUE
#' @param tol Tolerance for MLE conditions
#' @param tol_multiarm Tolerance for multi-arm consistency
#' @return Verification results
verify_netmeta_mle <- function(nma, tol = 1e-6, tol_multiarm = 1e-4) {
  if (!nma$common) {
    stop("netmeta object must have common = TRUE")
  }
  
  reference <- nma$reference.group
  if (is.null(reference) || reference == "") {
    reference <- nma$trts[1]
  }
  
  verify_fixed_effect_mle(
    TE = nma$TE,
    seTE = nma$seTE,
    treat1 = nma$treat1,
    treat2 = nma$treat2,
    studlab = nma$studlab,
    league_table = nma$TE.common,
    reference = reference,
    tol = tol,
    tol_multiarm = tol_multiarm
  )
}


#' Print verification results
print_verification <- function(v) {
  cat("\n")
  cat("=== Fixed-Effect NMA MLE Verification ===\n\n")
  
  cat(sprintf("Observations: %d\n", v$summary$n_observations))
  cat(sprintf("Studies: %d (%d multi-arm)\n", v$summary$n_studies, v$summary$n_multiarm))
  cat(sprintf("Parameters: %d\n", v$summary$n_parameters))
  cat(sprintf("Treatments: %s\n", paste(v$summary$treatments, collapse = ", ")))
  cat(sprintf("Reference: %s\n", v$summary$reference))
  cat(sprintf("Tolerance: %.2e (MLE), %.2e (multi-arm)\n\n", v$tolerance, v$tolerance_multiarm))
  
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
  
  if (v$is_valid_mle) {
    cat("CONCLUSION: Output is the UNIQUE maximum likelihood estimate.\n")
  } else {
    cat("CONCLUSION: Verification FAILED.\n")
  }
  cat("\n")
  
  # Print multi-arm details if present
  if (v$tests$multiarm_consistent$has_multiarm) {
    cat("--- Multi-arm Study Details ---\n\n")
    for (study in names(v$tests$multiarm_consistent$details)) {
      info <- v$tests$multiarm_consistent$details[[study]]
      status <- if (info$is_consistent) "OK" else if (!info$is_solvable) "UNSOLVABLE" else "INCONSISTENT"
      cat(sprintf("%s [%s]:\n", study, status))
      cat(sprintf("  %s\n", info$message))
      cat(sprintf("  Arms: %d, Contrasts: %d (complete: %d, minimum: %d)\n",
                  info$n_arms, info$n_contrasts, info$n_contrasts_complete, info$n_contrasts_minimum))
      if (!is.null(info$system_type)) {
        cat(sprintf("  System: %s\n", info$system_type))
      }
      if (!is.null(info$variances)) {
        cat(sprintf("  Arm variances: %s\n", 
                    paste(sprintf("%s=%.4f", names(info$variances), info$variances), 
                          collapse = ", ")))
        cat(sprintf("  Max residual: %.2e\n", info$max_residual))
      }
      cat("\n")
    }
  }
}


#' Compute the MLE using exact covariance structure
#'
#' Computes the WLS estimate using the exact covariance matrix derived
#' from arm-level variances. This can be compared to software outputs.
#'
#' @param TE Vector of observed treatment effects
#' @param seTE Vector of standard errors
#' @param treat1 Vector of first treatments
#' @param treat2 Vector of second treatments
#' @param studlab Vector of study labels
#' @param reference Reference treatment
#' @param tol_multiarm Tolerance for multi-arm consistency
#' @return List with estimates and covariance matrix
compute_exact_mle <- function(TE, seTE, treat1, treat2, studlab, 
                               reference, tol_multiarm = 1e-4) {
  
  # Build design matrix
  design <- build_design_matrix(treat1, treat2, reference)
  X <- design$X
  
  # Build covariance/weight matrix
  cov_result <- build_covariance_matrix(seTE, studlab, treat1, treat2, tol_multiarm)
  W <- cov_result$W
  
  if (is.null(W)) {
    stop("Could not compute weight matrix")
  }
  
  # Compute WLS estimate: beta = (X'WX)^{-1} X'Wy
  info_matrix <- t(X) %*% W %*% X
  beta_hat <- solve(info_matrix) %*% t(X) %*% W %*% TE
  
  # Standard errors
  var_beta <- solve(info_matrix)
  se_beta <- sqrt(diag(var_beta))
  
  # Build league table
  trts <- design$treatments
  n_trts <- length(trts)
  league <- matrix(0, n_trts, n_trts)
  rownames(league) <- colnames(league) <- trts
  
  ref_idx <- which(trts == reference)
  non_ref <- design$non_ref_treatments
  
  for (i in seq_along(non_ref)) {
    trt <- non_ref[i]
    trt_idx <- which(trts == trt)
    league[trt_idx, ref_idx] <- beta_hat[i]
    league[ref_idx, trt_idx] <- -beta_hat[i]
  }
  
  # Fill in all pairwise
  for (i in 1:(n_trts-1)) {
    for (j in (i+1):n_trts) {
      if (league[i, j] == 0 && i != ref_idx && j != ref_idx) {
        # Effect of i vs j = (i vs ref) - (j vs ref)
        league[i, j] <- league[i, ref_idx] - league[j, ref_idx]
        league[j, i] <- -league[i, j]
      }
    }
  }
  
  list(
    beta = as.numeric(beta_hat),
    se = se_beta,
    league_table = league,
    treatments = trts,
    reference = reference,
    info_matrix = info_matrix,
    covariance_matrix = cov_result$V,
    multiarm_details = cov_result$multiarm_checks
  )
}


# ============================================================
# Example
# ============================================================

if (sys.nframe() == 0) {
  
  data(Senn2013, package = "netmeta")
  
  cat("Fixed-Effect NMA MLE Verifier\n")
  cat("=============================\n\n")
  cat("Verifies MLE using ONLY input data and output league table.\n")
  cat("Reconstructs arm variances from contrast variances for multi-arm studies.\n\n")
  
  # Run NMA with netmeta
  nma <- netmeta(
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
  
  # Verify netmeta output against exact MLE
  cat("=== Verifying netmeta output ===\n")
  v <- verify_netmeta_mle(nma, tol = 1e-6, tol_multiarm = 1e-4)
  print_verification(v)
  
  # Compute exact MLE using our method
  cat("\n=== Computing exact MLE ===\n\n")
  exact <- compute_exact_mle(
    TE = Senn2013$TE,
    seTE = Senn2013$seTE,
    treat1 = Senn2013$treat1,
    treat2 = Senn2013$treat2,
    studlab = Senn2013$studlab,
    reference = "plac"
  )
  
  # Compare estimates
  cat("Comparison of estimates (vs placebo):\n\n")
  cat(sprintf("%-8s %12s %12s %12s\n", "Treat", "netmeta", "exact MLE", "difference"))
  cat(sprintf("%-8s %12s %12s %12s\n", "-----", "-------", "---------", "----------"))
  
  for (trt in exact$treatments) {
    if (trt != "plac") {
      nm_est <- nma$TE.common[trt, "plac"]
      ex_est <- exact$league_table[trt, "plac"]
      cat(sprintf("%-8s %12.4f %12.4f %12.6f\n", trt, nm_est, ex_est, nm_est - ex_est))
    }
  }
  
  # Verify exact MLE satisfies conditions
  cat("\n=== Verifying exact MLE output ===\n")
  v2 <- verify_fixed_effect_mle(
    TE = Senn2013$TE,
    seTE = Senn2013$seTE,
    treat1 = Senn2013$treat1,
    treat2 = Senn2013$treat2,
    studlab = Senn2013$studlab,
    league_table = exact$league_table,
    reference = "plac",
    tol = 1e-6,
    tol_multiarm = 1e-4
  )
  print_verification(v2)
}
