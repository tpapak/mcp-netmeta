"""
R Bridge for NetMeta

Provides Python interface to the R netmeta package using subprocess.
This approach is more portable than rpy2 and avoids library linking issues.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


def _find_r_executable() -> str:
    """Find R executable, preferring conda environment R if available."""
    # First, check if R exists in the same environment as Python
    python_bin = Path(sys.executable).parent
    conda_r = python_bin / "R"
    if conda_r.exists():
        return str(conda_r)

    # Fall back to system R
    system_r = shutil.which("R")
    if system_r:
        return system_r

    raise RuntimeError("R is not installed or not in PATH")


class NetmetaBridge:
    """Bridge to R netmeta package for network meta-analysis."""

    def __init__(self):
        """Initialize and verify R environment."""
        # Find R executable
        self._r_executable = _find_r_executable()

        # Verify R works
        try:
            result = subprocess.run(
                [self._r_executable, "--version"],
                capture_output=True,
                text=True,
                check=True,
            )
        except FileNotFoundError:
            raise RuntimeError("R is not installed or not in PATH")

        # Verify netmeta is installed
        check_code = 'cat(requireNamespace("netmeta", quietly=TRUE))'
        result = self._run_r_code(check_code)
        if result.strip() != "TRUE":
            raise RuntimeError("R package 'netmeta' is not installed")

        # Store state file path for persisting netmeta results between calls
        self._state_file = Path(tempfile.gettempdir()) / "netmeta_state.rds"

    def _run_r_code(self, code: str) -> str:
        """Run R code and return stdout."""
        result = subprocess.run(
            [self._r_executable, "--vanilla", "--slave", "-e", code],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(f"R error: {result.stderr}")
        return result.stdout

    def _run_r_script(self, script: str) -> dict[str, Any]:
        """Run R script that outputs JSON and return parsed result."""
        # Wrap script to output JSON
        full_script = f"""
        suppressPackageStartupMessages({{
            library(netmeta)
            library(jsonlite)
        }})
        
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

        try:
            # Find the JSON output (last complete JSON object)
            output = result.stdout.strip()
            if not output:
                return {"error": "No output from R"}
            return json.loads(output)
        except json.JSONDecodeError as e:
            return {
                "error": f"Failed to parse R output: {e}",
                "raw_output": result.stdout,
            }

    def run_netmeta(
        self,
        data: list[dict[str, Any]],
        sm: str = "OR",
        reference: str | None = None,
        comb_fixed: bool = True,
        comb_random: bool = True,
    ) -> dict[str, Any]:
        """
        Run network meta-analysis.

        Args:
            data: List of pairwise comparisons
            sm: Summary measure
            reference: Reference treatment
            comb_fixed: Include fixed effects
            comb_random: Include random effects

        Returns:
            Network meta-analysis results
        """
        # Use empty string "" instead of NULL for no reference (netmeta quirk)
        ref_arg = f'"{reference}"' if reference else '""'
        data_json = json.dumps(data).replace("'", "\\'")

        script = f'''
        data <- fromJSON('{data_json}')
        
        result <- netmeta(
            TE = data$TE,
            seTE = data$seTE,
            treat1 = data$treat1,
            treat2 = data$treat2,
            studlab = data$study,
            sm = "{sm}",
            reference.group = {ref_arg},
            common = {"TRUE" if comb_fixed else "FALSE"},
            random = {"TRUE" if comb_random else "FALSE"}
        )
        
        # Save result for subsequent calls
        saveRDS(result, "{self._state_file}")
        
        # Build output
        output <- list(
            treatments = as.list(result$trts),
            n_studies = result$k,
            n_comparisons = nrow(data),
            sm = result$sm,
            reference = result$reference.group
        )
        
        # Add heterogeneity stats if random effects
        if (result$random) {{
            output$heterogeneity <- list(
                tau2 = result$tau^2,
                tau = result$tau,
                I2 = result$I2
            )
        }}
        
        # Add fixed effects estimates
        if (result$common) {{
            n <- length(result$trts)
            comparisons <- list()
            idx <- 1
            for (i in 1:(n-1)) {{
                for (j in (i+1):n) {{
                    comparisons[[idx]] <- list(
                        treat1 = result$trts[i],
                        treat2 = result$trts[j],
                        effect = result$TE.common[i, j],
                        ci_lower = result$lower.common[i, j],
                        ci_upper = result$upper.common[i, j]
                    )
                    idx <- idx + 1
                }}
            }}
            output$fixed_effects <- comparisons
        }}
        
        # Add random effects estimates
        if (result$random) {{
            n <- length(result$trts)
            comparisons <- list()
            idx <- 1
            for (i in 1:(n-1)) {{
                for (j in (i+1):n) {{
                    comparisons[[idx]] <- list(
                        treat1 = result$trts[i],
                        treat2 = result$trts[j],
                        effect = result$TE.random[i, j],
                        ci_lower = result$lower.random[i, j],
                        ci_upper = result$upper.random[i, j]
                    )
                    idx <- idx + 1
                }}
            }}
            output$random_effects <- comparisons
        }}
        
        cat(toJSON(output, auto_unbox = TRUE))
        '''

        return self._run_r_script(script)

    def _load_state_script(self) -> str:
        """Return R code to load saved state."""
        return f'''
        if (!file.exists("{self._state_file}")) {{
            cat(toJSON(list(error = "No netmeta result available. Run runnetmeta first."), auto_unbox = TRUE))
            quit(save = "no")
        }}
        result <- readRDS("{self._state_file}")
        '''

    def get_network_graph(self) -> dict[str, Any]:
        """Get network structure from last netmeta result."""
        script = f"""
        {self._load_state_script()}
        
        # Get treatments (nodes)
        nodes <- lapply(seq_along(result$trts), function(i) {{
            list(id = i, label = result$trts[i])
        }})
        
        # Get edges from the data
        edges_df <- data.frame(
            from = result$treat1,
            to = result$treat2,
            study = result$studlab,
            stringsAsFactors = FALSE
        )
        
        # Count studies per comparison
        edge_summary <- aggregate(study ~ from + to, data = edges_df, FUN = length)
        names(edge_summary)[3] <- "n_studies"
        
        edges <- lapply(1:nrow(edge_summary), function(i) {{
            list(
                from = edge_summary$from[i],
                to = edge_summary$to[i],
                n_studies = edge_summary$n_studies[i]
            )
        }})
        
        cat(toJSON(list(nodes = nodes, edges = edges), auto_unbox = TRUE))
        """

        return self._run_r_script(script)

    def get_league_table(self, random: bool = True) -> dict[str, Any]:
        """Get league table of pairwise comparisons."""
        effect_type = "random" if random else "common"

        script = f'''
        {self._load_state_script()}
        
        if ("{effect_type}" == "random") {{
            te <- result$TE.random
            lower <- result$lower.random
            upper <- result$upper.random
        }} else {{
            te <- result$TE.common
            lower <- result$lower.common
            upper <- result$upper.common
        }}
        
        # Convert matrices to nested lists for JSON
        n <- length(result$trts)
        effects_list <- lapply(1:n, function(i) as.list(te[i,]))
        lower_list <- lapply(1:n, function(i) as.list(lower[i,]))
        upper_list <- lapply(1:n, function(i) as.list(upper[i,]))
        
        cat(toJSON(list(
            treatments = as.list(result$trts),
            effects = effects_list,
            ci_lower = lower_list,
            ci_upper = upper_list,
            sm = result$sm
        ), auto_unbox = TRUE))
        '''

        return self._run_r_script(script)

    def get_ranking(self, random: bool = True) -> dict[str, Any]:
        """Get treatment rankings using P-scores."""
        effect_type = "random" if random else "common"

        script = f'''
        {self._load_state_script()}
        
        # Calculate P-scores
        ranking <- netrank(result, small.values = "undesirable")
        
        if ("{effect_type}" == "random") {{
            p_scores <- ranking$Pscore.random
        }} else {{
            p_scores <- ranking$Pscore.common
        }}
        
        # Create ranking data
        treatments <- names(p_scores)
        scores <- as.numeric(p_scores)
        ranks <- rank(-scores)
        
        # Sort by rank
        ord <- order(ranks)
        
        cat(toJSON(list(
            treatments = as.list(treatments[ord]),
            p_scores = as.list(scores[ord]),
            ranks = as.list(ranks[ord])
        ), auto_unbox = TRUE))
        '''

        return self._run_r_script(script)

    def get_forest_data(
        self, reference: str | None = None, random: bool = True
    ) -> dict[str, Any]:
        """Get data for forest plot visualization."""
        ref_arg = f'"{reference}"' if reference else "NULL"
        effect_type = "random" if random else "common"

        script = f'''
        {self._load_state_script()}
        
        ref <- {ref_arg}
        if (is.null(ref)) ref <- result$reference.group
        if (is.null(ref)) ref <- result$trts[1]
        
        if ("{effect_type}" == "random") {{
            te <- result$TE.random
            lower <- result$lower.random
            upper <- result$upper.random
        }} else {{
            te <- result$TE.common
            lower <- result$lower.common
            upper <- result$upper.common
        }}
        
        # Get effects vs reference
        ref_idx <- which(result$trts == ref)
        other_trts <- result$trts[-ref_idx]
        
        comparisons <- lapply(other_trts, function(trt) {{
            trt_idx <- which(result$trts == trt)
            list(
                treatment = trt,
                effect = te[trt_idx, ref_idx],
                ci_lower = lower[trt_idx, ref_idx],
                ci_upper = upper[trt_idx, ref_idx]
            )
        }})
        
        cat(toJSON(list(
            reference = ref,
            sm = result$sm,
            comparisons = comparisons
        ), auto_unbox = TRUE))
        '''

        return self._run_r_script(script)

    def pairwise_to_netmeta(
        self,
        data: list[dict[str, Any]],
        outcome_type: str = "binary",
    ) -> list[dict[str, Any]] | dict[str, Any]:
        """Convert arm-level data to pairwise contrasts."""
        data_json = json.dumps(data).replace("'", "\\'")

        if outcome_type == "binary":
            sm = "OR"
            args = "event = data$events, n = data$n"
        else:
            sm = "MD"
            args = "mean = data$mean, sd = data$sd, n = data$n"

        script = f'''
        library(meta)
        
        data <- fromJSON('{data_json}')
        
        # Use pairwise function from meta package
        pw <- pairwise(
            treat = data$treatment,
            {args},
            studlab = data$study,
            sm = "{sm}"
        )
        
        # Format output as list of comparisons
        comparisons <- lapply(1:nrow(pw), function(i) {{
            list(
                study = pw$studlab[i],
                treat1 = as.character(pw$treat1[i]),
                treat2 = as.character(pw$treat2[i]),
                TE = pw$TE[i],
                seTE = pw$seTE[i]
            )
        }})
        
        cat(toJSON(comparisons, auto_unbox = TRUE))
        '''

        return self._run_r_script(script)
