# 4. Dify configuration

Build the Customer Support Copilot inside Dify: connect the model gateway, create the knowledge
base, register the MCP server, and assemble the agent.

| | Hands-on time | Elapsed time |
|---|---|---|
| Model provider | 5 min | 1–2 min plugin install |
| Knowledge base | 3 min | 1–2 min indexing |
| MCP server | 2 min | — |
| Agent app and test | 10 min | — |

Menus below are from Dify 1.16; other versions differ slightly. Keep the port-forward from
step 2 running and sign in at http://localhost:8080.

## Steps

### Model provider

1. **Integrations → Model Provider → Install model providers**, and install
   **OpenAI-API-compatible** from the marketplace.
2. On its card, **Add Model**:
   - **Name** `copilot-model`, type **LLM**, endpoint `http://lab-litellm:4000/v1`, API key
     `none`, mode **chat**, function calling **Tool Call**
3. **Add Model** again:
   - **Name** `lab-embed`, type **Text Embedding**, endpoint `http://lab-litellm:4000/v1`, API key `none`
4. **Default Models** (top right): system model `copilot-model`, embedding model `lab-embed`.
5. Click **Show Models** on the card and confirm **both** models are listed.

### Knowledge base

1. **Knowledge → Create Knowledge**, upload `lab/data/acme-support-kb.md`.
2. Choose **High Quality** indexing with `lab-embed`; name it *Acme Support KB*.
3. Wait until the document shows **Completed**.

### MCP server

1. **Integrations → Tools → MCP → Add MCP Server (HTTP)**.
2. URL `http://lab-mcp-crm:3000/mcp`, name *CRM*, server identifier `crm`.
3. The card should show **3 tools** and a green status dot.

### Agent app

1. **Studio → Create → Create from blank → Agent**, named *Customer Support Copilot*.
   The app's **Orchestrate** page shows a **LEGACY AGENT** badge. That's expected: Dify 1.16
   labels this app type as legacy while it introduces a newer agent builder (**Agents**, marked
   BETA, in the left sidebar). This lab is built and tested on the classic agent type; it works
   fully, so ignore the badge and don't use the BETA Agents section for this lab.
2. Model (top right): `copilot-model`.
3. **Instructions:**

   ```text
   You are the Tier 1 support copilot for Acme. Help support agents resolve customer tickets.
   - Use the Acme Support KB for policy and how-to questions.
   - Use the CRM tools to look up customers, their plan, and their tickets when a customer is named.
   - Be concise and give the agent a suggested reply they can send.
   - Follow the KB's personal-data rules in anything meant for the customer.
   ```

4. **Knowledge → Add**: *Acme Support KB*.
5. **Tools → Add**: the three CRM tools.
6. **Debug & Preview**: ask *"Avery Chen says their invoice total looks wrong. What plan are
   they on, what tickets are open, and what should I tell them?"* Expand the tool steps in the
   answer.
7. **Publish** (top right).

## Be mindful of

- **Verify, don't trust "saved".** Dify sometimes shows success for a change that didn't stick
  (in one version, adding a model returned success without saving it). After each step, check:
  models listed under **Show Models**, KB status **Completed**, MCP card with **3 tools**.
- **Order matters.** The gateway and MCP server must already be running (step 3). Dify tests each
  model and MCP server when you register it, and fails the registration if they don't answer.
- **Use the exact names** `copilot-model` and `lab-embed`. They're how the gateway routes
  requests, and the driver and checks depend on them.
- **Plugin install needs internet** (`marketplace.dify.ai`). In a locked-down cluster, install
  the plugin from an offline package instead.
- **One app only.** Every Dify app shares the same containers and identity, so a second app's
  traffic blends with the first in RoonCyber. Keep the lab to one app unless you're
  deliberately testing that.

## What you'll learn here

- **How an agent uses tools.** In the tool steps you'll see the agent decide to call
  `lookup_customer`, receive the full customer record, search the knowledge base, then write a
  reply. The model never "knew" the customer; it was given the data by a tool.
- **Where sensitive data actually goes.** The synthetic SSN and date of birth travel from the
  database, through the MCP server, through Dify, through the gateway, to an external model,
  even though the suggested reply leaves them out. That hidden flow is what RoonCyber detects as
  agentic exfiltration and model output leak.
- **Apps are configuration, not infrastructure.** The Copilot didn't create any new containers.
  It's a few rows in Dify's database. That's why apps on shared platforms are hard to inventory
  from infrastructure alone.
