# 5. Driver setup

Start steady, realistic traffic so RoonCyber has a pattern to learn from, and confirm the
whole chain works end to end.

| | Hands-on time | Elapsed time |
|---|---|---|
| API key and driver | 5 min | 1 min for the check run |
| First findings | — | 15–30 min |
| Application view filled in | — | A few hours |
| Baselines (first-seen, deviating) | — | Days |

## Steps

1. In Dify, open the Copilot → **API Access → API Key → Create new secret key**, and copy it.
2. Store it and deploy the driver. Edit `timeZone` in `lab/manifests/lab-driver.yaml` first if
   you're not on US Eastern time.

   ```bash
   kubectl create secret generic lab-driver-key -n dify-lab --from-literal=key="$(pbpaste)"
   kubectl apply -n dify-lab -f lab/manifests/lab-driver.yaml
   ```

3. Run it once now instead of waiting for the schedule:

   ```bash
   kubectl create job --from=cronjob/lab-driver lab-driver-check -n dify-lab
   kubectl logs -n dify-lab job/lab-driver-check -f
   ```

   Expect:

   ```text
   prompt 3/10: Sam Okafor wants 25 more seats before month end. ...
   HTTP 200
   tool calls: "tool": "lookup_customer;search_kb" ...
   result: ok
   ```

4. From now on the driver asks one question every 15 minutes, weekdays 08:00–18:00, rotating
   through ten realistic support questions.

## What to look for in RoonCyber

| When | Where | What |
|---|---|---|
| 15–30 min | Analyst Console, filter namespace `dify-lab` | SHADOW-MCP-SERVER on `lab-mcp-crm`; SHADOW-LOCAL-INFERENCE on `lab-ollama`; AGENTIC-EXFIL and MODEL-OUTPUT-LEAK when customer data reaches the external model; PII exposure |
| A few hours | Component Catalog; AI Applications | `lab-litellm` as AI Gateway, `lab-ollama` as Model Server, Weaviate as Vector Store, your provider's API as External Model, grouped into an application discovered from traffic |
| Days | Workload paths | Baselines that make new or deviating behavior stand out |

## Be mindful of

- **Agent apps only answer in streaming mode.** The driver handles it; if you write your own
  client, a "blocking" request to an agent app returns an error.
- **The schedule is deliberate.** Business hours only, so token spend stays at a few dollars a
  month and the traffic looks like a working day. Run the check job any time you need traffic now.
- **Setup noise.** Findings that opened while you installed (model and plugin downloads) aren't
  about the Copilot. Triage them, or review only findings after your first driver run.
- **The application view lags.** Applications are built from observed traffic and fill in over
  hours. Early on you may see several small fragments rather than one application.
- **Shared identity.** Everything the Copilot does is attributed to Dify's own containers
  (`dify-api` and friends), not to "the Copilot". That's how Dify works, not a lab fault.
- **Stopping it:** `kubectl patch cronjob lab-driver -n dify-lab -p '{"spec":{"suspend":true}}'`.
  Set `suspend` back to `false` to resume.

## What you'll learn here

- **Detection works on normal behavior.** Nothing in the driver is an attack. The findings
  come from an ordinary support agent doing its job with an over-broad tool and an external
  model. That's the everyday risk most AI deployments carry.
- **How the platform builds its picture.** First individual findings, then components and their
  types, then applications from the traffic between them, then baselines over days. Checking
  back at each stage shows how runtime evidence turns into inventory.
- **What to write down.** A short post-mortem is the quickest way to review results with
  RoonCyber:

  | Section | What goes in it |
  | --- | --- |
  | What was built | Provider, Dify version, anything changed from these guides |
  | Who did what | Each step done by hand or by an assistant (such as Claude Code), and how long it took |
  | Problems and workarounds | Anything that failed, and the fix |
  | What RoonCyber showed | Components and applications discovered; findings, with when they appeared; anything expected that didn't appear |
  | Noise | Findings you judged to be setup noise or false positives, and why |
  | Questions | Anything to explain or follow up |
