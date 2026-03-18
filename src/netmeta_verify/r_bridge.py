"""
R Bridge for NetMeta Verifiers

Provides Python interface to the verifier R scripts using subprocess.
The verifier scripts live in mcp/verifier/ — a sibling directory inside
the parent mcp repo (or a submodule thereof).
The verifier scripts use:
  - netmeta: Network meta-analysis
  - multiarmvars: Arm variance decomposition (github.com/tpapak/multiarmvars)
  - igraph: Graph structures
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


def _find_r_executable() -> str:
    """Find R executable, preferring conda environment R if available."""
    python_bin = Path(sys.executable).parent
    conda_r = python_bin / "R"
    if conda_r.exists():
        return str(conda_r)
    system_r = shutil.which("R")
    if system_r:
        return system_r
    raise RuntimeError("R is not installed or not in PATH")


def _verifiers_dir() -> Path:
    """Return the path to the verifier R scripts.

    Resolution order:
    1. $VERIFIERS_DIR env var (explicit override)
    2. ../verifier  — sibling submodule inside the parent mcp repo
    3. /opt/mcp/verifier — Docker image path
    4. <package>/verifiers — wheel-bundled fallback
    """
    # Explicit override
    env_dir = os.environ.get("VERIFIERS_DIR")
    if env_dir:
        p = Path(env_dir)
        if p.is_dir():
            return p
        raise RuntimeError(f"VERIFIERS_DIR={env_dir} does not exist")

    here = Path(__file__).parent
    # repo root: src/netmeta_verify/ -> src/ -> mcp/netmeta/
    repo_root = here.parent.parent
    candidates = [
        repo_root.parent / "verifier",  # ../verifier  (sibling in mcp/)
        Path("/opt/mcp/verifier"),  # Docker path
        here / "verifiers",  # wheel-bundled copy
    ]
    for p in candidates:
        if p.is_dir() and any(p.iterdir()):
            return p
    raise RuntimeError(
        "Cannot locate verifier R scripts. Expected at:\n"
        f"  {repo_root.parent / 'verifier'}  (sibling submodule in mcp/)\n"
        "  /opt/mcp/verifier  (Docker)\n"
        "Run: git submodule update --init --recursive\n"
        "or set the VERIFIERS_DIR environment variable."
    )


class VerifyBridge:
    """Bridge to the verifier R scripts."""

    def __init__(self):
        self._r_executable = _find_r_executable()

        # Verify R works
        try:
            subprocess.run(
                [self._r_executable, "--version"],
                capture_output=True,
                text=True,
                check=True,
            )
        except (FileNotFoundError, subprocess.CalledProcessError):
            raise RuntimeError("R is not installed or not in PATH")

        # Verify required R packages
        missing = []
        for pkg in ("netmeta", "multiarmvars", "igraph", "jsonlite"):
            check = self._run_r_code(
                f'cat(requireNamespace("{pkg}", quietly=TRUE))'
            ).strip()
            if check != "TRUE":
                missing.append(pkg)

        if missing:
            hints = {
                "netmeta": (
                    "remotes::install_github("
                    "'guido-s/netmeta@5ecfc1d7739c3df360a694d60af0563bc43d68ea')"
                ),
                "multiarmvars": ("remotes::install_github('tpapak/multiarmvars')"),
                "igraph": "install.packages('igraph')",
                "jsonlite": "install.packages('jsonlite')",
            }
            msgs = [
                f"  {p}: {hints.get(p, f'install.packages("{p}")')}" for p in missing
            ]
            raise RuntimeError("Missing R packages:\n" + "\n".join(msgs))

        self._verifiers_dir = _verifiers_dir()

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _run_r_code(self, code: str) -> str:
        result = subprocess.run(
            [self._r_executable, "--vanilla", "--slave", "-e", code],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(f"R error: {result.stderr}")
        return result.stdout

    def _run_r_script(self, script: str) -> dict[str, Any]:
        """Run an R script that outputs a single JSON object."""
        verifiers_path = str(self._verifiers_dir).replace("\\", "/")
        full_script = f"""
        suppressPackageStartupMessages({{
            library(netmeta)
            library(multiarmvars)
            library(igraph)
            library(jsonlite)
        }})

        # Make verifiers/ available for sourcing sibling scripts
        .verifiers_dir <- "{verifiers_path}"

        tryCatch({{
            {script}
        }}, error = function(e) {{
            cat(toJSON(list(error = conditionMessage(e)), auto_unbox = TRUE))
        }})
        """
        result = subprocess.run(
            [self._r_executable, "--vanilla", "--slave", "-e", full_script],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            return {"error": f"R error: {result.stderr}"}

        output = result.stdout.strip()
        if not output:
            return {"error": "No output from R"}
        try:
            return json.loads(output)
        except json.JSONDecodeError as e:
            return {
                "error": f"Failed to parse R output: {e}",
                "raw_output": result.stdout,
            }

    def _data_r(self, data: list[dict[str, Any]]) -> str:
        """Serialize pairwise data to an inline R fromJSON() call."""
        return json.dumps(data).replace("'", "\\'")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def verify_fixed_effect_mle(
        self,
        data: list[dict[str, Any]],
        league_table: list[dict[str, Any]],
        reference: str,
        tol: float = 1e-6,
        tol_multiarm: float = 1e-4,
    ) -> dict[str, Any]:
        """
        Verify that a fixed-effect NMA league table is the unique MLE.

        Args:
            data: Pairwise contrasts (study, treat1, treat2, TE, seTE).
            league_table: List of dicts with treat1, treat2, effect (from NMA output).
            reference: Reference treatment name.
            tol: Numerical tolerance for MLE conditions.
            tol_multiarm: Tolerance for multi-arm variance consistency.

        Returns:
            Verification results dict with is_valid_mle, tests, summary.
        """
        data_json = self._data_r(data)
        lt_json = self._data_r(league_table)

        script = f"""
        source(file.path(.verifiers_dir, "verify_fixed_effect_mle.R"))

        pw_data <- fromJSON('{data_json}')
        lt_rows <- fromJSON('{lt_json}')

        # Rebuild the NxN league_table matrix from the list of comparisons
        all_trts <- sort(unique(c(pw_data$treat1, pw_data$treat2)))
        n_trts <- length(all_trts)
        lt_mat <- matrix(0, n_trts, n_trts,
                         dimnames = list(all_trts, all_trts))
        for (i in seq_len(nrow(lt_rows))) {{
            t1 <- lt_rows$treat1[i]
            t2 <- lt_rows$treat2[i]
            eff <- lt_rows$effect[i]
            lt_mat[t1, t2] <- eff
            lt_mat[t2, t1] <- -eff
        }}

        v <- verify_fixed_effect_mle(
            TE        = pw_data$TE,
            seTE      = pw_data$seTE,
            treat1    = pw_data$treat1,
            treat2    = pw_data$treat2,
            studlab   = pw_data$study,
            league_table = lt_mat,
            reference = "{reference}",
            tol       = {tol},
            tol_multiarm = {tol_multiarm}
        )

        # Flatten test results to JSON-friendly form
        tests_flat <- lapply(v$tests, function(t) {{
            t$score_vector    <- NULL  # too verbose
            t$all_eigenvalues <- NULL
            t
        }})

        out <- list(
            is_valid_mle = v$is_valid_mle,
            is_unique    = v$is_unique,
            tests        = tests_flat,
            summary      = v$summary,
            tolerance    = v$tolerance,
            tolerance_multiarm = v$tolerance_multiarm
        )
        cat(toJSON(out, auto_unbox = TRUE))
        """
        return self._run_r_script(script)

    def verify_random_effect_reml(
        self,
        data: list[dict[str, Any]],
        league_table: list[dict[str, Any]],
        tau2: float,
        reference: str,
        tol: float = 1e-4,
        tol_multiarm: float = 1e-4,
    ) -> dict[str, Any]:
        """
        Verify that a random-effects NMA league table satisfies REML conditions.

        Args:
            data: Pairwise contrasts (study, treat1, treat2, TE, seTE).
            league_table: List of dicts with treat1, treat2, effect (random effects).
            tau2: Between-study variance (τ²) from the NMA.
            reference: Reference treatment name.
            tol: Numerical tolerance.
            tol_multiarm: Tolerance for multi-arm consistency.

        Returns:
            Verification results dict with is_valid_reml, tests, summary.
        """
        data_json = self._data_r(data)
        lt_json = self._data_r(league_table)

        script = f"""
        source(file.path(.verifiers_dir, "verify_fixed_effect_mle.R"))
        source(file.path(.verifiers_dir, "verify_random_effect_reml.R"))

        pw_data <- fromJSON('{data_json}')
        lt_rows <- fromJSON('{lt_json}')

        all_trts <- sort(unique(c(pw_data$treat1, pw_data$treat2)))
        n_trts <- length(all_trts)
        lt_mat <- matrix(0, n_trts, n_trts,
                         dimnames = list(all_trts, all_trts))
        for (i in seq_len(nrow(lt_rows))) {{
            t1 <- lt_rows$treat1[i]
            t2 <- lt_rows$treat2[i]
            eff <- lt_rows$effect[i]
            lt_mat[t1, t2] <- eff
            lt_mat[t2, t1] <- -eff
        }}

        v <- verify_random_effect_reml(
            TE        = pw_data$TE,
            seTE      = pw_data$seTE,
            treat1    = pw_data$treat1,
            treat2    = pw_data$treat2,
            studlab   = pw_data$study,
            league_table = lt_mat,
            tau2      = {tau2},
            reference = "{reference}",
            tol       = {tol},
            tol_multiarm = {tol_multiarm}
        )

        tests_flat <- lapply(v$tests, function(t) t)

        out <- list(
            is_valid_reml = v$is_valid_reml,
            is_unique     = v$is_unique,
            tests         = tests_flat,
            summary       = v$summary,
            tolerance     = v$tolerance,
            tolerance_multiarm = v$tolerance_multiarm
        )
        cat(toJSON(out, auto_unbox = TRUE))
        """
        return self._run_r_script(script)

    def generate_nma_code(
        self,
        data: list[dict[str, Any]],
        sm: str = "MD",
        reference: str | None = None,
        common: bool = True,
        random: bool = True,
        method_tau: str = "REML",
        include_rankings: bool = True,
        include_league: bool = True,
        include_forest: bool = True,
        include_netgraph: bool = True,
    ) -> dict[str, Any]:
        """
        Generate a standalone R script that reproduces an NMA.

        Args:
            data: Pairwise contrasts (study, treat1, treat2, TE, seTE).
            sm: Summary measure (OR, RR, MD, SMD, …).
            reference: Reference treatment (first alphabetically if omitted).
            common: Include common-effect model.
            random: Include random-effects model.
            method_tau: Tau² estimation method (REML, DL, …).
            include_rankings: Include P-score rankings section.
            include_league: Include league table section.
            include_forest: Include forest plot section.
            include_netgraph: Include network graph section.

        Returns:
            Dict with 'code' (the R script string) and 'reference' used.
        """
        data_json = self._data_r(data)
        ref_r = f'"{reference}"' if reference else "NULL"

        script = f"""
        source(file.path(.verifiers_dir, "generate_r_code.R"))

        pw_data <- fromJSON('{data_json}')

        ref <- {ref_r}
        if (is.null(ref)) {{
            ref <- sort(unique(c(pw_data$treat1, pw_data$treat2)))[1]
        }}

        code <- generate_nma_code(
            TE       = pw_data$TE,
            seTE     = pw_data$seTE,
            treat1   = pw_data$treat1,
            treat2   = pw_data$treat2,
            studlab  = pw_data$study,
            sm       = "{sm}",
            reference = ref,
            common   = {"TRUE" if common else "FALSE"},
            random   = {"TRUE" if random else "FALSE"},
            method_tau = "{method_tau}",
            include_rankings = {"TRUE" if include_rankings else "FALSE"},
            include_league   = {"TRUE" if include_league else "FALSE"},
            include_forest   = {"TRUE" if include_forest else "FALSE"},
            include_netgraph = {"TRUE" if include_netgraph else "FALSE"}
        )

        cat(toJSON(list(code = code, reference = ref), auto_unbox = TRUE))
        """
        return self._run_r_script(script)
