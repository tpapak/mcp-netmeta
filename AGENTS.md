# Make MCP server for netmeta (mcp branc)
- the goal is to make a minimal working example of an mcp server that conducts
network meta-analysis to apply for its use to 
https://www.cochrane.org/about-us/news/call-proposals-ai-tools-transform-evidence-synthesis

## Implementation
- The backend sould be implemented in Python 
- Use miniconda
- we will use my forked branch of netmeta https://github.com/tpapak/netmeta/pull/new/mcp
- First create REST api that runs netmeta:netmeta and a couple of other commands for data manipulation

## Tools
Available commmands
- runnetmeta
    runs netowork meta-analysis and exports the netmeta object

## Deployment
- Docker
- hosted in cinema.med.auth.gr/mcp/netmeta

## Documentation
- make examples from the netmeta package
- build webpage to show how run examples cinema.med.auth.gr/mcp/howto.html
- I will record a screenshot using my local llm setup on how to use it and maybe an example with gpt and anthropic webuis 
