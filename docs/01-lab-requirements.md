# 1. Lab requirements

What you need before you start, and what to line up early because it takes the longest.

| | Hands-on time | Elapsed time |
|---|---|---|
| Checking prerequisites | 15–30 min | — |
| Getting access you don't already have (namespace, permissions, outbound access, a model provider) | 5–10 min to ask | **Hours to days**, depending on your approval process |

Approvals are almost always the long pole. Start them first; the hands-on lab takes about an hour.

## Checklist

| Requirement | Why | How to check |
|---|---|---|
| A Kubernetes **test** cluster | Dify and the supporting services run as ordinary workloads | `kubectl config current-context` shows a non-production cluster |
| RoonCyber sensor running on the cluster's nodes | Without it, nothing in this lab is detected | `kubectl get daemonset -A`, then look for the RoonCyber sensor with all pods Ready |
| Permission to create a namespace and deploy into it | The lab creates Deployments, StatefulSets, Services, ConfigMaps, Secrets, ServiceAccounts, PVCs, Jobs and CronJobs | `kubectl auth can-i create deployments -n dify-lab` (and the same for the other kinds) |
| `pods/exec`, `pods/log`, `pods/portforward` | Health checks, logs and opening Dify's UI | `kubectl auth can-i create pods/portforward -n dify-lab` |
| A default StorageClass (ReadWriteOnce is fine) | Dify's database, cache, vector store and file storage | `kubectl get storageclass` shows one marked `(default)` |
| About 2.5 vCPU, 6 GiB memory and 30 GiB disk free | The lab's resource requests | `kubectl top nodes`, or your cluster dashboard |
| Outbound internet from the cluster | Image pulls, Dify's plugin marketplace, model downloads, Python packages, your model provider | See the list below |
| `kubectl` and Helm 3.14+ (Helm 4 works) on your machine | Installing everything | `helm version` |
| One model provider (see below) | The Copilot's chat model | A test key, or an AWS account with Bedrock access |

**Outbound access needed:** your model provider's API (for example `api.anthropic.com`),
`marketplace.dify.ai`, `registry.ollama.ai`, `pypi.org`, `ghcr.io` and Docker Hub.

## Choosing a model provider

Use whatever your organisation already approves. Only the chat model needs a provider; the
knowledge base's embeddings run locally in the cluster.

| Provider | What you need | Notes |
|---|---|---|
| Anthropic API | An API key | Tested |
| OpenAI API | An API key | Untested |
| Azure OpenAI | Key, endpoint, API version, a deployment of a model that supports tool calling | Untested |
| Claude or OpenAI models on Amazon Bedrock | Bedrock model access enabled in your account, plus an IAM role for the gateway (no key) or AWS keys | Untested; the IAM role usually needs your cloud team |
| Local only | Nothing external; more memory for a local chat model | Untested; shows fewer findings because nothing leaves the cluster |

Model usage costs a few dollars a month at the lab's default schedule.

## Be mindful of

- **Test environments only.** The lab deliberately sends (synthetic) personal data to an AI
  model. Never run it against production, and never load real customer data.
- **The sensor must cover the cluster.** It's the most common reason a lab shows nothing.
  Check it before you start, not after.
- **Shared storage.** Dify's chart asks for ReadWriteMany volumes by default. Most clusters,
  including EKS out of the box, don't offer them. The lab's values switch to ReadWriteOnce, so
  you don't need anything special, as long as you use the provided values file.
- **Locked-down egress.** If your cluster blocks the internet, plan for pre-pulled images and
  an offline Dify plugin install. Ask before starting rather than debugging timeouts later.
- **Key ownership.** Use a key from a test account you control. Some teams share demo keys
  whose owner nobody remembers; the lab's traffic would be billed to them.

## What you'll learn here

- **AI apps are mostly ordinary infrastructure.** Dify, a gateway, a model server, a vector
  store, an MCP server and a database: about 16 workloads in total. That's typical of real AI
  apps, and it's why runtime visibility on Kubernetes matters.
- **Where AI risk enters.** The two things you're approving here, outbound access to a model
  provider and a key to use it, are exactly the controls that decide whether data can leave
  your environment for an AI model. The lab makes that flow visible.
