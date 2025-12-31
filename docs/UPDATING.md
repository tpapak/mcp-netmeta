# Updating netmeta Version

This document describes how to update the pinned version of the netmeta R package used by the MCP server.

## Current Version

The current pinned version is tracked in the `NETMETA_VERSION` file in the repository root.

## When to Update

Update the netmeta version when:
- A new feature is needed from the develop branch
- A bug fix is available
- Preparing a new release of the MCP server

## Update Procedure

### Step 1: Get the Latest Commit SHA

```bash
# Get the latest commit from guido-s/netmeta develop branch
curl -s "https://api.github.com/repos/guido-s/netmeta/commits/develop" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(f'SHA: {d[\"sha\"]}\nDate: {d[\"commit\"][\"committer\"][\"date\"]}\nMessage: {d[\"commit\"][\"message\"].split(chr(10))[0]}')"
```

Or visit: https://github.com/guido-s/netmeta/commits/develop

### Step 2: Update NETMETA_VERSION

Edit `NETMETA_VERSION` with the new commit information:

```
NETMETA_REPO=guido-s/netmeta
NETMETA_BRANCH=develop
NETMETA_COMMIT=<new-commit-sha>
NETMETA_DATE=<commit-date>
NETMETA_MESSAGE=<commit-message>
```

### Step 3: Update environment.yml

Edit `environment.yml` and update the comment with the new SHA:

```yaml
# After creating the environment, install netmeta from GitHub:
#   R -e "remotes::install_github('guido-s/netmeta@<new-commit-sha>')"
```

### Step 4: Update README.md

Edit the version table in `README.md`:

```markdown
| Commit | `<new-commit-sha>` |
| Date | <commit-date> |
```

### Step 5: Test the Update

```bash
# Recreate conda environment
conda deactivate
conda env remove -n netmeta-mcp -y
conda env create -f environment.yml
conda activate netmeta-mcp

# Install new netmeta version
R -e "remotes::install_github('guido-s/netmeta@<new-commit-sha>')"

# Install MCP server
pip install -e .

# Run tests
python -c "
from netmeta_mcp.server import runnetmeta, get_ranking
data = [
    {'study': 'S1', 'treat1': 'A', 'treat2': 'B', 'TE': 0.5, 'seTE': 0.2},
    {'study': 'S2', 'treat1': 'A', 'treat2': 'C', 'TE': 0.8, 'seTE': 0.25},
]
result = runnetmeta(data, sm='OR')
print(f'Success! Treatments: {result[\"treatments\"]}')
"
```

### Step 6: Commit Changes

```bash
git add NETMETA_VERSION environment.yml README.md
git commit -m "Update netmeta to <new-commit-sha>"
```

## Rollback Procedure

If issues arise with a new version:

1. Revert to previous commit SHA in all files
2. Recreate the conda environment
3. Reinstall the netmeta R package

## Version History

Track significant version updates here:

| Date | Commit | Notes |
|------|--------|-------|
| 2025-10-29 | `5ecfc1d7739c3df360a694d60af0563bc43d68ea` | Initial pinned version |
