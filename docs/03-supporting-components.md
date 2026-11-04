# 3. Supporting components

Deploy the services the Copilot uses besides Dify: a database of synthetic customers, an MCP
server in front of it, a local model server for embeddings, and an AI gateway to your model
provider.

| | Hands-on time | Elapsed time |
|---|---|---|
| Provider config and credential | 5 min | — |
| Deploy | 2 min | 3–5 min (Python packages, embedding-model download) |
| Health checks | 3 min | — |

## What gets deployed

| Component | What it does | Real-world equivalent |
|---|---|---|
| `lab-customer-db` | Postgres with 12 synthetic customers and 9 support tickets | A CRM or customer database |
| `lab-mcp-crm` | MCP server with `lookup_customer`, `get_customer_tickets`, `list_open_tickets` | A tool server giving an agent access to company data |
| `lab-ollama` | Local model server; generates knowledge-base embeddings (`nomic-embed-text`) | Self-hosted inference, often run without security's knowledge |
| `lab-litellm` | AI gateway: `copilot-model` → your provider, `lab-embed` → `lab-ollama` | A platform team's central model gateway |

## Steps

1. Pick your provider's file in `lab/providers/` and fill in any placeholders (deployment name,
   Bedrock model ID, region). Create the gateway's routing from it:

   ```bash
   kubectl create configmap lab-litellm-config -n dify-lab --from-file=config.yaml=lab/providers/anthropic.yaml
   ```

2. Create the credential. Copy the key to your clipboard, then run the command from your
   provider file's header. For Anthropic:

   ```bash
   kubectl create secret generic lab-provider-keys -n dify-lab --from-literal=ANTHROPIC_API_KEY="$(pbpaste)"
   ```

   For Bedrock with an IAM role, or local-only, create it empty:
   `kubectl create secret generic lab-provider-keys -n dify-lab`. Then follow
   `lab/providers/bedrock-irsa.md` for the role.

3. Deploy:

   ```bash
   kubectl apply -n dify-lab -f lab/manifests/lab-supporting.yaml
   kubectl rollout status -n dify-lab deploy/lab-customer-db deploy/lab-mcp-crm deploy/lab-ollama deploy/lab-litellm --timeout=10m
   ```

4. Check each one answers. This runs inside the existing `lab-mcp-crm` pod, so it doesn't
   create any new pods:

   ```bash
   kubectl exec -n dify-lab deploy/lab-mcp-crm -- python -c "
   import json, urllib.request as u
   def post(url, body, h={}):
       r = u.Request(url, json.dumps(body).encode(), {'Content-Type': 'application/json', **h})
       return u.urlopen(r, timeout=90).read().decode()[:160]
   print('model  :', post('http://lab-litellm:4000/v1/chat/completions', {'model': 'copilot-model', 'max_tokens': 20, 'messages': [{'role': 'user', 'content': 'Say hello.'}]}))
   print('embed  :', post('http://lab-litellm:4000/v1/embeddings', {'model': 'lab-embed', 'input': 'reset password'}))
   print('mcp-crm:', post('http://lab-mcp-crm:3000/mcp', {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call', 'params': {'name': 'lookup_customer', 'arguments': {'query_text': 'avery'}}}, {'Accept': 'application/json, text/event-stream'}))
   "
   ```

   Expect a short reply from your model, a list of numbers (an embedding), and Avery Chen's
   synthetic customer record.

## Be mindful of

- **Don't test with throwaway pods.** A quick `kubectl run curl …` looks harmless, but
  RoonCyber discovers AI applications from traffic, so a one-off pod calling the gateway can
  show up as its own "application". The check above reuses an existing pod for that reason.
- **Keys stay out of history and chat.** Read them from the clipboard as shown. Never paste a
  key into a command line, a ticket or an AI assistant.
- **`lab-ollama` needs a minute** after starting to download its model. An embedding error
  right after deploy usually just means "wait".
- **`lab-mcp-crm` installs Python packages at startup.** If the cluster can't reach pypi.org it
  will restart repeatedly.
- **Unique names matter.** Everything is prefixed `lab-` so it can't be confused with other AI
  workloads in the same cluster. In testing, same-named components in different namespaces were
  sometimes merged in the platform's inventory.
- **Use your own gateway**, not a shared one from another team. Shared gateways bring their
  owners' keys, schedules and other callers, all of which muddy the results.

## What you'll learn here

- **The MCP server is deliberately over-generous.** `lookup_customer` returns the whole record,
  including SSN and date of birth, even when the agent only needs a plan name. That's very
  common in real integrations, and it's what lets data flow further than intended.
- **Why a gateway.** Routing all model calls through one service means the provider can change
  without touching the app, keys live in one place, and policies (guardrails, budgets) can be
  applied centrally. RoonCyber classifies it as an AI Gateway and attaches the provider's API
  to the application as an External Model.
- **Local models are AI too.** `lab-ollama` only computes embeddings, but a self-hosted model
  server doing inference is exactly what RoonCyber flags as shadow local inference.
