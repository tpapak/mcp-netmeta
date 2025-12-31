# Using NetMeta MCP Server

This guide explains how to use the NetMeta MCP server for network meta-analysis.

## Setup

### 1. Install the MCP Server

Follow the installation instructions in the main README.md to set up the native installation with conda.

### 2. Configure Your MCP Client

The NetMeta MCP server works with any MCP-compatible client. Below are configuration examples for popular options.

---

## MCP Client Configurations

### Claude Desktop

Add to your Claude Desktop configuration file:

- **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "netmeta": {
      "command": "/path/to/conda/envs/netmeta-mcp/bin/python",
      "args": ["-m", "netmeta_mcp.server"]
    }
  }
}
```

### OpenCode

Add the netmeta server to your OpenCode configuration file (`~/.config/opencode/opencode.json`):

```json
{
  "mcp": {
    "netmeta": {
      "type": "local",
      "command": [
        "/path/to/conda/envs/netmeta-mcp/bin/python",
        "-m",
        "netmeta_mcp.server"
      ],
      "enabled": true
    }
  }
}
```

### Cursor

Add to Cursor's MCP settings (Settings → MCP Servers):

```json
{
  "mcpServers": {
    "netmeta": {
      "command": "/path/to/conda/envs/netmeta-mcp/bin/python",
      "args": ["-m", "netmeta_mcp.server"]
    }
  }
}
```

### Cline (VS Code Extension)

Add to your Cline MCP settings in VS Code:

```json
{
  "mcpServers": {
    "netmeta": {
      "command": "/path/to/conda/envs/netmeta-mcp/bin/python",
      "args": ["-m", "netmeta_mcp.server"]
    }
  }
}
```

### Continue (VS Code/JetBrains Extension)

Add to your Continue configuration (`~/.continue/config.json`):

```json
{
  "mcpServers": [
    {
      "name": "netmeta",
      "command": "/path/to/conda/envs/netmeta-mcp/bin/python",
      "args": ["-m", "netmeta_mcp.server"]
    }
  ]
}
```

### HTTP Transport (Any Client)

For clients that support HTTP/SSE transport, run the HTTP server:

```bash
conda activate netmeta-mcp
python -m netmeta_mcp.http_server
```

Then configure your client to connect to:

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

## Example Conda Paths

Replace `/path/to/conda/envs/netmeta-mcp/bin/python` with your actual path:

| Platform | Path |
|----------|------|
| macOS (Homebrew) | `/opt/homebrew/Caskroom/miniconda/base/envs/netmeta-mcp/bin/python` |
| macOS (Miniforge) | `~/miniforge3/envs/netmeta-mcp/bin/python` |
| Linux | `~/miniconda3/envs/netmeta-mcp/bin/python` |
| Windows | `C:\Users\<user>\miniconda3\envs\netmeta-mcp\python.exe` |

**Tip:** Find your conda path with: `conda run -n netmeta-mcp which python`

---

## Using with ellmer (R)

[ellmer](https://github.com/tidyverse/ellmer) is an R package for calling LLM APIs. It supports MCP tools, making it ideal for R users who want to perform network meta-analysis through natural language.

### Installation

```r
# Install ellmer from CRAN
install.packages("ellmer")

# Or development version
# pak::pak("tidyverse/ellmer")
```

### Setup MCP Tools

First, start the HTTP server:

```bash
conda activate netmeta-mcp
python -m netmeta_mcp.http_server
```

Then in R, register the MCP tools:

```r
library(ellmer)

# Register netmeta MCP tools
netmeta_tools <- mcp_tools("http://localhost:8000/mcp")

# Create a chat with the tools
chat <- chat_openai(
  model = "gpt-4o",
  tools = netmeta_tools
)
```

### Example: Complete Network Meta-Analysis

```r
library(ellmer)

# Setup
netmeta_tools <- mcp_tools("http://localhost:8000/mcp")
chat <- chat_openai(model = "gpt-4o", tools = netmeta_tools)

# Run analysis through natural language
chat$chat("
I have data from trials comparing smoking cessation treatments.
Here's my CSV data:

study,treat1,treat2,TE,seTE
Study1,No contact,Self-help,0.49,0.40
Study2,No contact,Individual counselling,0.84,0.28
Study3,Self-help,Individual counselling,0.35,0.31
Study4,No contact,Group counselling,1.14,0.21
Study5,Individual counselling,Group counselling,0.30,0.28

Please:
1. Run a network meta-analysis with 'No contact' as reference
2. Show me the treatment rankings
3. Display the network structure
")
```

### Interactive Console

For exploratory analysis, use ellmer's live console:

```r
library(ellmer)

netmeta_tools <- mcp_tools("http://localhost:8000/mcp")
chat <- chat_openai(model = "gpt-4o", tools = netmeta_tools)

# Start interactive session
live_console(chat)

# Now chat naturally:
# > "What tools do you have available for network meta-analysis?"
# > "Convert this CSV and run an analysis: ..."
# > "Show me the league table"
```

### Programmatic Usage

For scripts and automated workflows:

```r
library(ellmer)

# Suppress streaming for programmatic use
netmeta_tools <- mcp_tools("http://localhost:8000/mcp")
chat <- chat_openai(model = "gpt-4o", tools = netmeta_tools, echo = "none")

# Prepare your data
csv_data <- "study,treat1,treat2,TE,seTE
Trial1,A,B,0.5,0.2
Trial2,A,C,0.8,0.25
Trial3,B,C,0.3,0.22"

# Run analysis
result <- chat$chat(paste0("
Run network meta-analysis on this data with treatment A as reference:

", csv_data, "

Return the treatment rankings as a formatted table.
"))

print(result)
```

### Using Different LLM Providers with ellmer

ellmer supports multiple providers:

```r
# OpenAI
chat <- chat_openai(model = "gpt-4o", tools = netmeta_tools)

# Anthropic Claude
chat <- chat_anthropic(model = "claude-sonnet-4-20250514", tools = netmeta_tools)

# Google Gemini
chat <- chat_gemini(model = "gemini-1.5-pro", tools = netmeta_tools)

# Local Ollama
chat <- chat_ollama(model = "llama3.1", tools = netmeta_tools)

# Azure OpenAI
chat <- chat_azure(
  endpoint = "https://your-resource.openai.azure.com",
  deployment_id = "gpt-4o",
  tools = netmeta_tools
)
```

---

## Restart Your Client

After updating any configuration, restart your MCP client to load the new server.

## Available Tools

Once configured, you'll have access to these tools:

| Tool | Description |
|------|-------------|
| `csv_to_json` | Convert CSV data to JSON format |
| `runnetmeta` | Run network meta-analysis |
| `get_network_graph` | Get network structure |
| `get_league_table` | Get pairwise comparisons |
| `get_ranking` | Get P-score rankings |
| `get_forest_data` | Get forest plot data |
| `pairwise_to_netmeta` | Convert arm-level to pairwise |

## Example Prompts

### Basic Network Meta-Analysis

**Prompt:**
```
Run a network meta-analysis on this data:

study,treat1,treat2,TE,seTE
Study1,Placebo,DrugA,0.5,0.2
Study2,Placebo,DrugB,0.8,0.25
Study3,DrugA,DrugB,0.3,0.22
Study4,Placebo,DrugA,0.6,0.18

Use odds ratio as the summary measure and Placebo as reference.
Show me the treatment rankings.
```

### From Arm-Level Binary Data

**Prompt:**
```
I have arm-level data from clinical trials comparing depression treatments.
Convert this to pairwise format and run a network meta-analysis:

study,treatment,events,n
Trial1,Placebo,20,100
Trial1,SSRI,35,100
Trial2,Placebo,18,80
Trial2,CBT,30,80
Trial3,SSRI,40,120
Trial3,CBT,45,120

Use Placebo as reference and show rankings.
```

### From Arm-Level Continuous Data

**Prompt:**
```
Analyze this continuous outcome data (mean pain reduction scores):

study,treatment,mean,sd,n
Study1,Placebo,2.1,1.5,50
Study1,DrugA,3.8,1.4,48
Study2,Placebo,2.3,1.6,60
Study2,DrugB,4.2,1.3,58
Study3,DrugA,3.5,1.5,45
Study3,DrugB,4.0,1.4,47

Run network meta-analysis with mean difference.
```

### Analyzing a CSV File

**Prompt:**
```
Read the file examples/smoking_pairwise.csv and run a network meta-analysis.
Use "No contact" as the reference treatment.
Show me:
1. The network structure
2. Treatment rankings
3. The league table
```

### Getting Specific Results

**Prompt:**
```
After running the network meta-analysis, show me:
- The forest plot data comparing all treatments to Placebo
- The league table with random effects
- Which treatment has the highest P-score
```

## Workflow Examples

### Complete Analysis Workflow

1. **Load data from CSV:**
   ```
   "Convert this CSV to JSON for netmeta: [paste CSV data]"
   ```

2. **Run the analysis:**
   ```
   "Run network meta-analysis with OR, using Placebo as reference"
   ```

3. **Get results:**
   ```
   "Show me the treatment rankings"
   "Get the network graph"
   "Show the league table"
   ```

### Iterative Analysis

```
"First, show me the network structure to understand the data"
"Now run the meta-analysis"
"The heterogeneity seems high - what's the I² value?"
"Show me the rankings using the random effects model"
```

## Tips

1. **Specify the summary measure:** Always mention if you want OR, RR, MD, etc.

2. **Set a reference:** Specify which treatment should be the reference for comparisons.

3. **Choose the model:** Mention if you want fixed effect (`comb_fixed`) or random effects (`comb_random`) results.

4. **Check heterogeneity:** Ask about I² and tau² to understand between-study variability.

5. **Use CSV format:** It's easier to paste CSV data than JSON in chat.

## Troubleshooting

### "netmeta tool not found"

- Check that the MCP server is properly configured
- Verify the Python path points to the correct conda environment
- Restart your MCP client after configuration changes

### "R error" or "netmeta not installed"

- Ensure netmeta R package is installed in the conda environment
- Run: `R -e "library(netmeta)"` to verify

### "No data found"

- Check CSV format has correct column names
- For pairwise: `study, treat1, treat2, TE, seTE`
- For arm-level binary: `study, treatment, events, n`
- For arm-level continuous: `study, treatment, mean, sd, n`

### ellmer: "Connection refused"

- Ensure the HTTP server is running: `python -m netmeta_mcp.http_server`
- Check the URL matches: `http://localhost:8000/mcp`
- Verify no firewall is blocking port 8000

### ellmer: "Tool not found"

- Verify MCP tools are registered: `print(netmeta_tools)`
- Ensure you passed `tools = netmeta_tools` when creating the chat

## Data Format Reference

### Pairwise Format

```csv
study,treat1,treat2,TE,seTE
```
- `TE`: Treatment effect (log scale for OR/RR)
- `seTE`: Standard error

### Arm-Level Binary

```csv
study,treatment,events,n
```
- `events`: Number of events
- `n`: Total sample size

### Arm-Level Continuous

```csv
study,treatment,mean,sd,n
```
- `mean`: Mean outcome
- `sd`: Standard deviation
- `n`: Sample size

## More Resources

- [netmeta R package documentation](https://cran.r-project.org/web/packages/netmeta/netmeta.pdf)
- [ellmer documentation](https://ellmer.tidyverse.org/)
- [MCP Protocol specification](https://modelcontextprotocol.io/)
