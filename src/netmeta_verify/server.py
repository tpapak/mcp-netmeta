"""
NetMeta Verify MCP Server

An MCP server that provides verification tools for network meta-analysis
results, and generates reproducible R code.

Tools:
  - verify_fixed_effect_mle   : Check that a fixed-effect NMA league table
                                 is the unique MLE.
  - verify_random_effect_reml : Check that a random-effects NMA satisfies
                                 REML optimality conditions.
  - generate_nma_code         : Generate a standalone R script that
                                 reproduces an NMA analysis.
"""

from typing import Any

from mcp.server.fastmcp import FastMCP

from .r_bridge import VerifyBridge

mcp = FastMCP(
    "NetMeta Verify Server",
    instructions="""
    This MCP server provides verification and reproducibility tools for
    network meta-analysis (NMA) results produced by the netmeta R package.

    Available tools:
    - verify_fixed_effect_mle:   Verify a fixed-effect NMA league table is
                                 the unique Maximum Likelihood Estimate.
    - verify_random_effect_reml: Verify a random-effects NMA satisfies the
                                 REML optimality conditions (τ² and θ).
    - generate_nma_code:         Generate a standalone, reproducible R script
                                 for an NMA (suitable for publication).

    All tools accept pairwise contrast data in the same format used by the
    netmeta-mcp server (study, treat1, treat2, TE, seTE).

    Required R packages: netmeta, multiarmvars, igraph, jsonlite.
    Install multiarmvars with:
      R -e "remotes::install_github('tpapak/multiarmvars')"
    """,
)

# Lazy-initialised so the server starts even when R / packages are absent
_bridge: VerifyBridge | None = None


def _get_bridge() -> VerifyBridge:
    global _bridge
    if _bridge is None:
        _bridge = VerifyBridge()
    return _bridge


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


@mcp.tool()
def verify_fixed_effect_mle(
    data: list[dict[str, Any]],
    league_table: list[dict[str, Any]],
    reference: str,
    tol: float = 1e-6,
    tol_multiarm: float = 1e-4,
) -> dict[str, Any]:
    """
    Verify that a fixed-effect NMA league table is the unique MLE.

    Checks:
    1. Score equations equal zero (first-order optimality).
    2. Information matrix is positive definite (second-order condition).
    3. Solution is unique (network is connected / full rank).
    4. Estimates match the closed-form WLS solution.
    5. Multi-arm variance consistency (arm variances recoverable from contrasts).

    Args:
        data: Pairwise contrasts. Each dict must have:
              - study: Study identifier
              - treat1: First treatment
              - treat2: Second treatment
              - TE: Treatment effect
              - seTE: Standard error
        league_table: NMA output as a list of dicts, each with:
                      - treat1: First treatment
                      - treat2: Second treatment
                      - effect: Estimated effect of treat1 vs treat2
        reference: Reference treatment name.
        tol: Numerical tolerance for MLE conditions (default 1e-6).
        tol_multiarm: Tolerance for multi-arm variance consistency (default 1e-4).

    Returns:
        Dict with:
        - is_valid_mle: True if all tests pass
        - is_unique: True if the solution is unique
        - tests: Dict of individual test results (passed, property, description, …)
        - summary: n_observations, n_parameters, n_studies, treatments, reference
    """
    return _get_bridge().verify_fixed_effect_mle(
        data=data,
        league_table=league_table,
        reference=reference,
        tol=tol,
        tol_multiarm=tol_multiarm,
    )


@mcp.tool()
def verify_random_effect_reml(
    data: list[dict[str, Any]],
    league_table: list[dict[str, Any]],
    tau2: float,
    reference: str,
    tol: float = 1e-4,
    tol_multiarm: float = 1e-4,
) -> dict[str, Any]:
    """
    Verify that a random-effects NMA satisfies REML optimality conditions.

    Checks:
    1. Fixed-effects score = 0 given the supplied τ².
    2. REML score for τ² = 0 (or ≤ 0 at the boundary τ² = 0).
    3. Information matrix is positive definite.
    4. τ² ≥ 0.
    5. Solution is unique (full rank).
    6. Estimates match the GLS closed form given τ².
    7. REML log-likelihood is at a local maximum (perturbation test).

    Args:
        data: Pairwise contrasts (study, treat1, treat2, TE, seTE).
        league_table: Random-effects NMA output as a list of dicts
                      (treat1, treat2, effect).
        tau2: Between-study variance τ² from the NMA.
        reference: Reference treatment name.
        tol: Numerical tolerance (default 1e-4).
        tol_multiarm: Tolerance for multi-arm consistency (default 1e-4).

    Returns:
        Dict with:
        - is_valid_reml: True if all tests pass
        - is_unique: True if the solution is unique
        - tests: Dict of individual test results
        - summary: n_observations, n_parameters, n_studies, treatments,
                   reference, tau2, tau
    """
    return _get_bridge().verify_random_effect_reml(
        data=data,
        league_table=league_table,
        tau2=tau2,
        reference=reference,
        tol=tol,
        tol_multiarm=tol_multiarm,
    )


@mcp.tool()
def generate_nma_code(
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
    Generate a standalone, reproducible R script for a network meta-analysis.

    The generated script:
    - Embeds the data directly (no external files needed).
    - Runs netmeta() with the specified options.
    - Optionally includes rankings, league table, forest plot, network graph.
    - Includes basic verification / Q-statistics output.

    Suitable for inclusion in publications or supplementary materials.

    Args:
        data: Pairwise contrasts (study, treat1, treat2, TE, seTE).
        sm: Summary measure — "OR", "RR", "RD", "MD", "SMD" (default "MD").
        reference: Reference treatment (first alphabetically if omitted).
        common: Include common (fixed) effect model (default True).
        random: Include random effects model (default True).
        method_tau: Tau² estimation method — "REML", "DL", "PM", … (default "REML").
        include_rankings: Add P-score rankings section (default True).
        include_league: Add league table section (default True).
        include_forest: Add forest plot section (default True).
        include_netgraph: Add network graph section (default True).

    Returns:
        Dict with:
        - code: The complete R script as a string
        - reference: The reference treatment used
    """
    return _get_bridge().generate_nma_code(
        data=data,
        sm=sm,
        reference=reference,
        common=common,
        random=random,
        method_tau=method_tau,
        include_rankings=include_rankings,
        include_league=include_league,
        include_forest=include_forest,
        include_netgraph=include_netgraph,
    )


def main():
    """Run the MCP server (stdio transport)."""
    mcp.run()


if __name__ == "__main__":
    main()
