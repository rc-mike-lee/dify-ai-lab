# Dify AI Workload Lab

Stand up a realistic AI workload in a Kubernetes **test** cluster so RoonCyber can discover it
and raise findings: a Customer Support Copilot built on [Dify](https://github.com/langgenius/dify),
an open-source AI app platform. The agent answers from a knowledge base, looks customers up
through an MCP server backed by a database of **synthetic** PII, and calls a hosted model (Claude,
GPT or either through Amazon Bedrock) through an app-owned AI gateway.

About 1 hour hands-on, first findings within the hour. Model cost: a few dollars a month.

```
lab-driver ─► dify proxy ─► dify-api (agent) ─► dify-plugin-daemon ─► lab-litellm ─► your model provider
                               │                                         └─► lab-ollama (embeddings)
                               ├─► lab-mcp-crm ─► lab-customer-db (synthetic PII)
                               └─► weaviate (knowledge base)
```

## What's in this repo

The lab is two stages, each in its own folder so they can be deployed separately (by hand, or as
two Flux Kustomizations):

| Folder | Stage | Contents |
|---|---|---|
| `platform/` | **1. Dify** | Namespace, HelmRepository + HelmRelease for the community Dify chart, `values/dify-lab.yaml` (storage fixes, smaller footprint, one ServiceAccount per component), `README.md` |
| `lab/` | **2. AI workload** | `manifests/lab-supporting.yaml` (`lab-customer-db`, `lab-mcp-crm`, `lab-ollama`, `lab-litellm`), `manifests/lab-driver.yaml` (traffic driver), `providers/` (gateway routing per model provider), `data/acme-support-kb.md`, `README.md` |
| `docs/` | Both | Step-by-step guides with time estimates, pitfalls and what each step teaches |
| `dist/install-dify-standalone.sh` | 1 | Stage 1 as a single file: hand it to anyone who just needs Dify installed securely. Built by `tools/build-standalone.sh`; rebuild after changing anything in `platform/` |

Dify itself is not in this repo: it's installed from the community Helm chart, pinned to the tested version.

**Deploying with Flux:** see `platform/README.md` and `lab/README.md`. Each folder has a
`kustomization.yaml`; point one Flux Kustomization at `platform/` and a second at `lab/` with
`dependsOn` the first. The steps below are for plain `kubectl` and Helm.

## Detailed guides

The steps below are the short version. Each part has a guide with time estimates, things to
watch for, and what each step teaches:

1. [Lab requirements](docs/01-lab-requirements.md)
2. [Dify setup](docs/02-dify-setup.md)
3. [Supporting components](docs/03-supporting-components.md)
4. [Dify configuration](docs/04-dify-configuration.md)
5. [Driver setup](docs/05-driver-setup.md)

Dify and the supporting components can be installed in either order; both must be running
before you configure Dify.

## Before you start

- A Kubernetes **test** cluster with the RoonCyber sensor running on its nodes
- Permission to create a namespace and deploy into it
- `kubectl` and Helm 3.14+ (Helm 4 works)
- Outbound access from the cluster to your model provider's API, `marketplace.dify.ai`, `registry.ollama.ai`, `pypi.org`, `ghcr.io` and Docker Hub
- Access to one model provider (see step 1), ideally a test account
- About 2.5 vCPU, 6 GiB memory and 30 GiB of disk free (default StorageClass)

All data is synthetic. Use a test environment only.

## 1. Namespace and model provider

Pick the provider your organisation already uses. Only the chat model needs it; knowledge-base
embeddings always run locally on `lab-ollama`.

| Provider | Config file | Credential | Status |
|---|---|---|---|
| Anthropic API | `lab/providers/anthropic.yaml` | `ANTHROPIC_API_KEY` | Tested |
| OpenAI API | `lab/providers/openai.yaml` | `OPENAI_API_KEY` | Untested |
| Azure OpenAI | `lab/providers/azure-openai.yaml` | `AZURE_API_KEY`, `AZURE_API_BASE`, `AZURE_API_VERSION` | Untested |
| Claude on Amazon Bedrock | `lab/providers/bedrock-claude.yaml` | None with an IAM role (`lab/providers/bedrock-irsa.md`), or AWS keys | Untested |
| OpenAI models on Amazon Bedrock | `lab/providers/bedrock-openai.yaml` | Same as above | Untested |
| Local only (Ollama, no external model) | `lab/providers/ollama-local.yaml` | None. Shows fewer findings: nothing leaves the cluster | Untested |

Edit the chosen file first if it has placeholders (deployment name, Bedrock model ID, region).
Then create the namespace, the gateway's routing, and the credential. For Anthropic, with your
key copied to the clipboard:

```bash
kubectl create namespace dify-lab
kubectl create configmap lab-litellm-config -n dify-lab --from-file=config.yaml=lab/providers/anthropic.yaml
kubectl create secret generic lab-provider-keys -n dify-lab --from-literal=ANTHROPIC_API_KEY="$(pbpaste)"
```

Each provider file's header shows its exact Secret command. For Bedrock with an IAM role or for
local-only, create the Secret empty: `kubectl create secret generic lab-provider-keys -n dify-lab`.

On Linux, use `xclip -o -selection clipboard` or `wl-paste` instead of `pbpaste`. Keys are read
from the clipboard so they never appear in your shell history.

To switch provider later, recreate the ConfigMap and Secret, then
`kubectl rollout restart deploy/lab-litellm -n dify-lab`. Nothing in Dify changes: it always
asks the gateway for `copilot-model`.

## 2. Supporting services

```bash
kubectl apply -n dify-lab -f lab/manifests/lab-supporting.yaml
kubectl rollout status -n dify-lab deploy/lab-customer-db deploy/lab-mcp-crm deploy/lab-ollama deploy/lab-litellm --timeout=10m
```

Check that each answers. These run inside the existing `lab-mcp-crm` pod, so no extra pods
are created (one-off pods show up as AI applications in RoonCyber):

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

Expect a short reply from your model, a vector of numbers, and Avery Chen's synthetic customer record.
`lab-ollama` takes a minute or two after starting to download its embedding model.

## 3. Dify

```bash
./platform/install-dify.sh dify-lab
kubectl get pods -n dify-lab      # wait until everything is Running and Ready (about 10 minutes)
```

The script generates random credentials for every secret Dify uses (none of the chart's public
defaults remain), stores them in Secret `dify-secrets`, and installs the pinned community chart
with `platform/values/dify-lab.yaml`. Rerun it for upgrades; it reuses the same Secret.

Open Dify:

```bash
kubectl port-forward -n dify-lab svc/dify 8080:80
```

Go to http://localhost:8080, create the admin account on the first-run page, and keep the
password in your password manager. Port-forward drops after about 30 minutes idle; just rerun it.

## 4. Configure the Copilot in Dify

Menus are from Dify 1.16; other versions may differ slightly.

1. **Model provider.** **Integrations → Model Provider → Install model providers**, install
   **OpenAI-API-compatible**. On its card, **Add Model** twice:
   - `copilot-model`: type **LLM**, endpoint `http://lab-litellm:4000/v1`, API key `none`,
     mode **chat**, function calling **Tool Call**
   - `lab-embed`: type **Text Embedding**, endpoint `http://lab-litellm:4000/v1`, API key `none`

   Under **Default Models**, set `copilot-model` as the system model and `lab-embed` as the
   embedding model. Click **Show Models** and confirm both are listed.
2. **Knowledge base.** **Knowledge → Create Knowledge**, upload `lab/data/acme-support-kb.md`,
   choose **High Quality** indexing with `lab-embed`, name it *Acme Support KB*. Wait for
   **Completed**.
3. **MCP server.** **Integrations → Tools → MCP → Add MCP Server (HTTP)**: URL
   `http://lab-mcp-crm:3000/mcp`, name *CRM*, server identifier `crm`. The card should show
   **3 tools** and a green dot.
4. **The app.** **Studio → Create → Create from blank → Agent**, named *Customer Support Copilot*:
   - Model (top right): `copilot-model`
   - Instructions:
     ```text
     You are the Tier 1 support copilot for Acme. Help support agents resolve customer tickets.
     - Use the Acme Support KB for policy and how-to questions.
     - Use the CRM tools to look up customers, their plan, and their tickets when a customer is named.
     - Be concise and give the agent a suggested reply they can send.
     - Follow the KB's personal-data rules in anything meant for the customer.
     ```
   - **Knowledge → Add**: *Acme Support KB*
   - **Tools → Add**: the three CRM tools (`lookup_customer`, `get_customer_tickets`, `list_open_tickets`)
5. **Test.** In **Debug & Preview**, ask: *"Avery Chen says their invoice total looks wrong.
   What plan are they on, what tickets are open, and what should I tell them?"* Expand the tool
   steps: the agent called `lookup_customer` and received the full record, including the
   synthetic SSN and date of birth. Then **Publish**.

## 5. Traffic driver

In the Copilot, open **API Access → API Key → Create new secret key** and copy it. Then:

```bash
kubectl create secret generic lab-driver-key -n dify-lab --from-literal=key="$(pbpaste)"
kubectl apply -n dify-lab -f lab/manifests/lab-driver.yaml      # edit timeZone first if needed
kubectl create job --from=cronjob/lab-driver lab-driver-check -n dify-lab
kubectl logs -n dify-lab job/lab-driver-check -f
```

Expect `HTTP 200`, tool calls including `lookup_customer`, and `result: ok`.

## 6. What to look for in RoonCyber

| When | Where | What |
|---|---|---|
| 15–30 min | Analyst Console, namespace `dify-lab` | SHADOW-MCP-SERVER on `lab-mcp-crm`; SHADOW-LOCAL-INFERENCE on `lab-ollama`; AGENTIC-EXFIL and MODEL-OUTPUT-LEAK when customer data reaches the external model; PII exposure |
| A few hours | Component Catalog; AI Applications | `lab-litellm` as AI Gateway, `lab-ollama` as Model Server, Weaviate as Vector Store, your provider's API as External Model, grouped into an application discovered from the traffic |
| Days | Workload paths | Baselines: first-seen and deviating behaviour |

**Known behaviour**

- Downloads during setup (models, plugins) can open findings in the first hour. Triage them,
  or focus on findings opened after the first driver run.
- Dify runs every app it hosts inside the same containers, so apps share one runtime identity.
  This lab uses a single app for that reason.
- Dify's own containers are classified separately: app servers as Workflow Engines, the plugin
  runtime and UI as Applications, Weaviate as a Vector Store.

## Clean up

```bash
helm uninstall dify -n dify-lab
kubectl delete namespace dify-lab
```

This removes everything, including the synthetic data. Revoke the provider key if you created
it for this lab.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Dify pods Pending, PVCs Pending, no events | Your cluster has no default StorageClass, or values were changed. The lab uses ReadWriteOnce; set `storageClass` if needed |
| A new `dify-api` pod stuck Pending during an upgrade | Keep `updateStrategy: Recreate` for api, worker and plugin-daemon |
| `lab-litellm` stuck in `ContainerCreating` or `CreateContainerConfigError` | ConfigMap `lab-litellm-config` or Secret `lab-provider-keys` is missing (step 1) |
| Model test returns an authentication or model-not-found error | Wrong credential, model ID or region in the provider file; for Bedrock, model access not enabled or the IAM role not applied (`lab/providers/bedrock-irsa.md`) |
| `lab-mcp-crm` restarting | No outbound access to pypi.org |
| Embedding test fails right after install | `lab-ollama` is still pulling `nomic-embed-text`; wait a minute |
| Model shows as added but isn't listed | Add it again from the provider card; confirm with **Show Models** |
| Agent returns an error through the API | Agent apps only support streaming (the driver already uses it) |
| Plugin install fails | No outbound access to `marketplace.dify.ai` |
