"""
NetMeta MCP Server

An MCP server that provides network meta-analysis capabilities using the R netmeta package.
"""

import csv
import io
import json
from typing import Any

from mcp.server.fastmcp import FastMCP

from .r_bridge import NetmetaBridge

# Initialize the MCP server
mcp = FastMCP(
    "NetMeta Server",
    instructions="""
    This MCP server provides network meta-analysis capabilities using the R netmeta package.
    
    Available tools:
    - csv_to_json: Convert CSV data to JSON format for netmeta
    - runnetmeta: Run a network meta-analysis on pairwise contrast data
    - get_network_graph: Get the network structure as edge list
    - get_league_table: Get the league table of treatment comparisons
    - get_ranking: Get treatment rankings (P-scores)
    - get_forest_data: Get data for forest plot visualization
    - pairwise_to_netmeta: Convert arm-level data to pairwise contrasts
    
    Data format for runnetmeta:
    The data should be a list of pairwise comparisons with fields:
    - study: Study identifier
    - treat1: First treatment name
    - treat2: Second treatment name  
    - TE: Treatment effect (e.g., log odds ratio, mean difference)
    - seTE: Standard error of the treatment effect
    """,
)

# Initialize R bridge
r_bridge = NetmetaBridge()


@mcp.tool()
def runnetmeta(
    data: list[dict[str, Any]],
    sm: str = "OR",
    reference: str | None = None,
    comb_fixed: bool = True,
    comb_random: bool = True,
) -> dict[str, Any]:
    """
    Run network meta-analysis using the R netmeta package.

    Args:
        data: List of pairwise comparisons. Each dict should have:
              - study: Study identifier
              - treat1: First treatment
              - treat2: Second treatment
              - TE: Treatment effect (log scale for ratios)
              - seTE: Standard error of treatment effect
        sm: Summary measure - "OR" (odds ratio), "RR" (risk ratio),
            "RD" (risk difference), "MD" (mean difference), "SMD" (standardized MD)
        reference: Reference treatment for rankings (optional)
        comb_fixed: Include fixed effect model (default: True)
        comb_random: Include random effects model (default: True)

    Returns:
        Dictionary containing:
        - treatments: List of treatments in the network
        - n_studies: Number of studies
        - n_comparisons: Number of direct comparisons
        - fixed_effects: Fixed effect estimates (if comb_fixed=True)
        - random_effects: Random effects estimates (if comb_random=True)
        - heterogeneity: Heterogeneity statistics (tau2, I2)
        - inconsistency: Inconsistency test results
    """
    return r_bridge.run_netmeta(
        data=data,
        sm=sm,
        reference=reference,
        comb_fixed=comb_fixed,
        comb_random=comb_random,
    )


@mcp.tool()
def get_network_graph() -> dict[str, Any]:
    """
    Get the network structure from the last network meta-analysis.

    Returns:
        Dictionary containing:
        - nodes: List of treatment nodes with labels
        - edges: List of edges with study counts and sample sizes
    """
    return r_bridge.get_network_graph()


@mcp.tool()
def get_league_table(random: bool = True) -> dict[str, Any]:
    """
    Get the league table of all pairwise treatment comparisons.

    Args:
        random: Use random effects model (True) or fixed effect model (False)

    Returns:
        Dictionary containing:
        - treatments: List of treatments (row/column labels)
        - effects: Matrix of treatment effects (lower triangle)
        - ci_lower: Matrix of lower confidence intervals
        - ci_upper: Matrix of upper confidence intervals
    """
    return r_bridge.get_league_table(random=random)


@mcp.tool()
def get_ranking(random: bool = True) -> dict[str, Any]:
    """
    Get treatment rankings using P-scores.

    Args:
        random: Use random effects model (True) or fixed effect model (False)

    Returns:
        Dictionary containing:
        - treatments: List of treatments
        - p_scores: P-score for each treatment (0-1, higher is better)
        - rank: Rank of each treatment (1 = best)
    """
    return r_bridge.get_ranking(random=random)


@mcp.tool()
def get_forest_data(
    reference: str | None = None, random: bool = True
) -> dict[str, Any]:
    """
    Get data for creating a forest plot of treatment effects vs reference.

    Args:
        reference: Reference treatment (uses network reference if not specified)
        random: Use random effects model (True) or fixed effect model (False)

    Returns:
        Dictionary containing:
        - reference: The reference treatment
        - comparisons: List of dicts with treatment, effect, ci_lower, ci_upper
    """
    return r_bridge.get_forest_data(reference=reference, random=random)


@mcp.tool()
def pairwise_to_netmeta(
    data: list[dict[str, Any]],
    outcome_type: str = "binary",
) -> list[dict[str, Any]]:
    """
    Convert arm-level data to pairwise contrast format for netmeta.

    Args:
        data: List of study arms. Each dict should have:
              For binary outcomes:
              - study: Study identifier
              - treatment: Treatment name
              - events: Number of events
              - n: Total sample size

              For continuous outcomes:
              - study: Study identifier
              - treatment: Treatment name
              - mean: Mean outcome
              - sd: Standard deviation
              - n: Sample size

        outcome_type: "binary" or "continuous"

    Returns:
        List of pairwise contrasts ready for runnetmeta
    """
    return r_bridge.pairwise_to_netmeta(data=data, outcome_type=outcome_type)


@mcp.tool()
def csv_to_json(
    csv_content: str,
    data_format: str = "pairwise",
) -> dict[str, Any]:
    """
    Convert CSV data to JSON format for network meta-analysis.

    Args:
        csv_content: CSV content as a string. The CSV should have a header row.

            For pairwise format (data_format="pairwise"), required columns:
            - study: Study identifier
            - treat1: First treatment name
            - treat2: Second treatment name
            - TE: Treatment effect (log scale for OR/RR)
            - seTE: Standard error of treatment effect

            For arm-level binary format (data_format="arm_binary"), required columns:
            - study: Study identifier
            - treatment: Treatment name
            - events: Number of events
            - n: Total sample size

            For arm-level continuous format (data_format="arm_continuous"), required columns:
            - study: Study identifier
            - treatment: Treatment name
            - mean: Mean outcome
            - sd: Standard deviation
            - n: Sample size

        data_format: One of "pairwise", "arm_binary", or "arm_continuous"

    Returns:
        Dictionary containing:
        - data: List of records ready for runnetmeta or pairwise_to_netmeta
        - n_records: Number of records parsed
        - columns: List of column names found
        - format: The data format
        - next_step: Suggested next step to run
    """
    # Parse CSV
    reader = csv.DictReader(io.StringIO(csv_content.strip()))
    records = list(reader)

    if not records:
        return {"error": "No data found in CSV"}

    columns = list(records[0].keys())

    # Validate and convert based on format
    if data_format == "pairwise":
        required = {"study", "treat1", "treat2", "TE", "seTE"}
        missing = required - set(columns)
        if missing:
            return {
                "error": f"Missing required columns for pairwise format: {missing}",
                "found_columns": columns,
                "required_columns": list(required),
            }

        # Convert numeric fields
        data = []
        for row in records:
            data.append(
                {
                    "study": row["study"],
                    "treat1": row["treat1"],
                    "treat2": row["treat2"],
                    "TE": float(row["TE"]),
                    "seTE": float(row["seTE"]),
                }
            )

        return {
            "data": data,
            "n_records": len(data),
            "columns": columns,
            "format": "pairwise",
            "next_step": "Use runnetmeta(data=result['data'], sm='OR') to run network meta-analysis",
        }

    elif data_format == "arm_binary":
        required = {"study", "treatment", "events", "n"}
        missing = required - set(columns)
        if missing:
            return {
                "error": f"Missing required columns for arm_binary format: {missing}",
                "found_columns": columns,
                "required_columns": list(required),
            }

        data = []
        for row in records:
            data.append(
                {
                    "study": row["study"],
                    "treatment": row["treatment"],
                    "events": int(row["events"]),
                    "n": int(row["n"]),
                }
            )

        return {
            "data": data,
            "n_records": len(data),
            "columns": columns,
            "format": "arm_binary",
            "next_step": "Use pairwise_to_netmeta(data=result['data'], outcome_type='binary') to convert, then runnetmeta()",
        }

    elif data_format == "arm_continuous":
        required = {"study", "treatment", "mean", "sd", "n"}
        missing = required - set(columns)
        if missing:
            return {
                "error": f"Missing required columns for arm_continuous format: {missing}",
                "found_columns": columns,
                "required_columns": list(required),
            }

        data = []
        for row in records:
            data.append(
                {
                    "study": row["study"],
                    "treatment": row["treatment"],
                    "mean": float(row["mean"]),
                    "sd": float(row["sd"]),
                    "n": int(row["n"]),
                }
            )

        return {
            "data": data,
            "n_records": len(data),
            "columns": columns,
            "format": "arm_continuous",
            "next_step": "Use pairwise_to_netmeta(data=result['data'], outcome_type='continuous') to convert, then runnetmeta()",
        }

    else:
        return {
            "error": f"Unknown data_format: {data_format}",
            "valid_formats": ["pairwise", "arm_binary", "arm_continuous"],
        }


def main():
    """Run the MCP server."""
    mcp.run()


if __name__ == "__main__":
    main()
