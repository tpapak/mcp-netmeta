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

### Option 1: Public Hosted Servers

A list of publicly available hosted servers will be documented here as they become available.

<!-- Public server URLs will be added here -->

No installation required for hosted servers. Simply configure your MCP client to connect to the URL.

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
git clone https://github.com/tpapak/netmeta.git
cd netmeta
git checkout mcp

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
      "cwd": "/path/to/netmeta"
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

## Usage with ellmer (R)

[ellmer](https://github.com/tidyverse/ellmer) is an R package for calling LLM APIs. You can use it to interact with the netmeta MCP server.

### Installation

```r
# Install ellmer from CRAN
install.packages("ellmer")

# Or development version from GitHub
# pak::pak("tidyverse/ellmer")
```

### Example: Network Meta-Analysis with ellmer

```r
library(ellmer)

# Initialize chat with your preferred provider
chat <- chat_openai(model = "gpt-4o")  
# Or: chat <- chat_claude(), chat_gemini(), etc.

# Define MCP tools for netmeta
# (Configure your MCP client to connect to the netmeta server first)

# Example conversation for network meta-analysis
chat$chat("
I have data from a network meta-analysis comparing smoking cessation treatments.
Here's my CSV data:

study,treat1,treat2,TE,seTE
Study1,Placebo,NRT,0.5,0.2
Study2,Placebo,Counseling,0.3,0.18
Study3,NRT,Counseling,-0.2,0.22
Study4,Placebo,NRT,0.6,0.25
Study5,NRT,Combined,0.4,0.19

Please run a network meta-analysis with Placebo as reference and show me:
1. The treatment rankings
2. The network structure
")
```

### Interactive Console

For interactive exploration, use ellmer's live console:

```r
library(ellmer)

chat <- chat_openai(model = "gpt-4o")
live_console(chat)
# Now you can interactively ask questions about network meta-analysis
```

### Programmatic Usage

```r
library(ellmer)

# Suppress streaming output for programmatic use
chat <- chat_openai(model = "gpt-4o", echo = "none")

# Run analysis
result <- chat$chat("
Convert this CSV to JSON and run network meta-analysis:
study,treat1,treat2,TE,seTE
Trial1,A,B,0.5,0.2
Trial2,A,C,0.8,0.25
Trial3,B,C,0.3,0.22
")

print(result)
```

---

## Data Format

### CSV Input (Recommended)

The easiest way to provide data is via CSV. Use `csv_to_json` to convert.

**Pairwise format CSV:**
```csv
study,treat1,treat2,TE,seTE
Study1,Placebo,DrugA,0.5,0.2
Study2,Placebo,DrugB,0.8,0.25
Study3,DrugA,DrugB,0.3,0.22
```

**Arm-level binary CSV:**
```csv
study,treatment,events,n
Study1,Placebo,10,100
Study1,DrugA,15,100
Study2,Placebo,20,150
Study2,DrugB,35,150
```

**Arm-level continuous CSV:**
```csv
study,treatment,mean,sd,n
Study1,Placebo,5.2,1.5,50
Study1,DrugA,4.1,1.4,48
Study2,Placebo,5.5,1.6,60
Study2,DrugB,3.8,1.3,58
```

### JSON Format

For `runnetmeta`, provide data as a list of pairwise comparisons:

```json
[
  {
    "study": "Study identifier",
    "treat1": "First treatment name",
    "treat2": "Second treatment name",
    "TE": 0.5,
    "seTE": 0.2
  }
]
```

- `TE`: Treatment effect (log scale for ratios like OR, RR)
- `seTE`: Standard error of the treatment effect

### Arm-Level Data

For `pairwise_to_netmeta`, provide arm-level data:

**Binary outcomes:**
```json
[
  {"study": "Study 1", "treatment": "A", "events": 10, "n": 100},
  {"study": "Study 1", "treatment": "B", "events": 15, "n": 100}
]
```

**Continuous outcomes:**
```json
[
  {"study": "Study 1", "treatment": "A", "mean": 5.2, "sd": 1.5, "n": 50},
  {"study": "Study 1", "treatment": "B", "mean": 4.8, "sd": 1.4, "n": 50}
]
```

## Summary Measures

| Code | Description | Outcome Type |
|------|-------------|--------------|
| `OR` | Odds Ratio | Binary |
| `RR` | Risk Ratio | Binary |
| `RD` | Risk Difference | Binary |
| `MD` | Mean Difference | Continuous |
| `SMD` | Standardized Mean Difference | Continuous |

## Example Workflows

### Workflow 1: From Pairwise CSV

```
1. csv_to_json(csv_content, data_format="pairwise")
2. runnetmeta(data, sm="OR", reference="Placebo")
3. get_ranking()
```

### Workflow 2: From Arm-Level Binary CSV

```
1. csv_to_json(csv_content, data_format="arm_binary")
2. pairwise_to_netmeta(data, outcome_type="binary")
3. runnetmeta(pairwise_data, sm="OR", reference="Placebo")
4. get_ranking()
```

### Workflow 3: From Arm-Level Continuous CSV

```
1. csv_to_json(csv_content, data_format="arm_continuous")
2. pairwise_to_netmeta(data, outcome_type="continuous")
3. runnetmeta(pairwise_data, sm="MD", reference="Placebo")
4. get_ranking()
```

## License

MIT License

## References

- Rücker G, Krahn U, König J, Efthimiou O, Davies A, Papakonstantinou T, Schwarzer G (2024). netmeta: Network Meta-Analysis using Frequentist Methods. R package.
- ellmer: Call LLM APIs from R. https://github.com/tidyverse/ellmer
