#' Tests for R Code Generator
#'
#' Run with: Rscript verifiers/tests/test_generate_r_code.R

source("verifiers/generate_r_code.R")

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
cat("  Tests for generate_r_code.R\n")
cat("====================================================\n\n")

# ============================================================
# TEST 1: Generate code from synthetic data
# ============================================================

cat("--- Test 1: Code generation from data ---\n\n")

# Simple data
TE <- c(0.5, 0.6, 0.3)
seTE <- c(0.1, 0.15, 0.12)
treat1 <- c("A", "A", "B")
treat2 <- c("B", "C", "C")
studlab <- c("S1", "S2", "S3")

code1 <- generate_nma_code(
  TE = TE, seTE = seTE, treat1 = treat1, treat2 = treat2,
  studlab = studlab, sm = "MD", reference = "C"
)

test("Code is generated", nchar(code1) > 100)
test("Code contains library(netmeta)", grepl("library\\(netmeta\\)", code1))
test("Code contains data definition", grepl("data_matrix <- rbind", code1))
test("Code contains netmeta call", grepl("nma <- netmeta", code1))
test("Code contains reference group", grepl('reference.group = "C"', code1))

cat("\n")

# ============================================================
# TEST 2: Generate code from netmeta object
# ============================================================

cat("--- Test 2: Code generation from netmeta object ---\n\n")

data(Senn2013, package = "netmeta")

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

code2 <- generate_nma_code_from_netmeta(nma)

test("Code from netmeta is generated", nchar(code2) > 100)
test("Code contains all 28 comparisons", 
     length(gregexpr("c\\(\"", code2)[[1]]) >= 28)
test("Code contains ranking section", grepl("netrank", code2))
test("Code contains league table section", grepl("netleague", code2))
test("Code contains forest plot section", grepl("forest\\(nma", code2))

cat("\n")

# ============================================================
# TEST 3: Verify generated code reproduces results
# ============================================================

cat("--- Test 3: Code reproduces original results ---\n\n")

verification <- verify_generated_code(nma, code2)

test("Verification runs successfully", !is.null(verification))
test("Common effects match", verification$tests$common_effects$passed)
test("Random effects match", verification$tests$random_effects$passed)
test("Tau matches", verification$tests$tau$passed)
test("All tests pass", verification$passed)

cat("\n")

# ============================================================
# TEST 4: Optional sections can be disabled
# ============================================================

cat("--- Test 4: Optional sections ---\n\n")

code_minimal <- generate_nma_code_from_netmeta(
  nma,
  include_rankings = FALSE,
  include_league = FALSE,
  include_forest = FALSE,
  include_netgraph = FALSE
)

test("Minimal code is shorter", nchar(code_minimal) < nchar(code2))
test("No ranking in minimal code", !grepl("netrank", code_minimal))
test("No league in minimal code", !grepl("netleague", code_minimal))
test("No forest in minimal code", !grepl("forest\\(nma", code_minimal))
test("Still contains netmeta call", grepl("nma <- netmeta", code_minimal))

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
