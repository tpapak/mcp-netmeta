# NetMeta MCP Server

An MCP (Model Context Protocol) server that provides network meta-analysis capabilities using the R [netmeta](https://github.com/guido-s/netmeta) package.

## netmeta Version

This MCP server uses a pinned version of netmeta from the develop branch:

| Property | Value |
|----------|-------|
| Repository | [guido-s/netmeta](https://github.com/guido-s/netmeta) |
| Branch | develop |
| Version | 3.3-0 |
| Commit | `5ecfc1d7739c3df360a694d60af0563bc43d68ea` |
| Date | 2025-10-29 |

See `NETMETA_VERSION` file for details.

## Overview

This server enables AI assistants to perform network meta-analysis, a statistical technique for comparing multiple treatments simultaneously using both direct and indirect evidence from randomized controlled trials.

## Available Tools

| Tool | Description |
|------|-------------|
| `csv_to_json` | Convert CSV data to JSON format for netmeta |
| `runnetmeta` | Run network meta-analysis on pairwise contrast data |
| `get_network_graph` | Get the network structure as nodes and edges |
| `get_league_table` | Get all pairwise treatment comparisons |
| `get_ranking` | Get treatment rankings using P-scores |
| `get_forest_data` | Get data for forest plot visualization |
| `pairwise_to_netmeta` | Convert arm-level data to pairwise contrasts |

---

## Deployment Options

### Option 1: Public Hosted Server

A public hosted server will soon be available at:

| Server | URL | Status |
|--------|-----|--------|
| CINeMA | `https://cinema.med.auth.gr/mcp-netmeta` | Coming soon |

No installation required for hosted servers. Simply configure your MCP client to connect to the URL:

```json
{
  "mcpServers": {
    "netmeta": {
      "url": "https://cinema.med.auth.gr/mcp-netmeta"
    }
  }
}
```

---

### Option 2: Self-Hosted (Native Installation)

For local development or when you want to run your own server.

#### Prerequisites
- Python 3.10+
- R 4.0+
- Conda (recommended) or pip

#### Step 1: Clone and Setup

```bash
# Clone the repository
git clone https://github.com/tpapak/mcp-netmeta.git
cd mcp-netmeta

# Create conda environment
conda env create -f environment.yml
conda activate netmeta-mcp
```

#### Step 2: Install netmeta R package

Install the pinned version of netmeta from GitHub:

```bash
conda activate netmeta-mcp
R -e "remotes::install_github('guido-s/netmeta@5ecfc1d7739c3df360a694d60af0563bc43d68ea')"
```

#### Step 3: Install the MCP Server

```bash
pip install -e .
```

#### Step 4: Run the Server

**Stdio transport (for local MCP clients):**
```bash
conda activate netmeta-mcp
netmeta-mcp
```

**HTTP transport (for web access):**
```bash
conda activate netmeta-mcp
python -m netmeta_mcp.http_server
```
Server runs at `http://localhost:8000/mcp`

#### MCP Client Configuration (Native - Stdio)

```json
{
  "mcpServers": {
    "netmeta": {
      "command": "/path/to/conda/envs/netmeta-mcp/bin/python",
      "args": ["-m", "netmeta_mcp.server"],
      "cwd": "/path/to/mcp-netmeta"
    }
  }
}
```

Example conda paths:
- **macOS (Homebrew):** `/opt/homebrew/Caskroom/miniconda/base/envs/netmeta-mcp/bin/python`
- **macOS (Miniforge):** `~/miniforge3/envs/netmeta-mcp/bin/python`
- **Linux:** `~/miniconda3/envs/netmeta-mcp/bin/python`

#### MCP Client Configuration (Native - HTTP)

```json
{
  "mcpServers": {
    "netmeta": {
      "url": "http://localhost:8000/mcp"
    }
  }
}
```

---

## Usage Guide

For detailed usage instructions, including:

- **MCP client configurations** (Claude Desktop, Cursor, Cline, Continue, OpenCode)
- **ellmer (R) integration** with examples
- **Example prompts** and workflows
- **Data format reference**
- **Troubleshooting**

See the **[Usage Guide](docs/USAGE.md)**.

---

## Quick Example

```
Run a network meta-analysis on this data:

study,treat1,treat2,TE,seTE
Study1,Placebo,DrugA,0.5,0.2
Study2,Placebo,DrugB,0.8,0.25
Study3,DrugA,DrugB,0.3,0.22

Use odds ratio as the summary measure and Placebo as reference.
Show me the treatment rankings.
```

## License

GPL-3.0 License

## References

- Rücker G, Krahn U, König J, Efthimiou O, Davies A, Papakonstantinou T, Schwarzer G (2024). netmeta: Network Meta-Analysis using Frequentist Methods. R package.
- ellmer: Call LLM APIs from R. https://github.com/tidyverse/ellmer
