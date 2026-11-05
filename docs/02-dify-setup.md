# 2. Dify setup

Install Dify, the open-source AI app platform the Copilot runs on.

| | Hands-on time | Elapsed time |
|---|---|---|
| Install | 5 min | 10–15 min (image pulls, database start-up) |
| Admin account | 2 min | — |

## Steps

1. Create the namespace:

   ```bash
   kubectl create namespace dify-lab
   ```

2. Install Dify with the lab's install script:

   ```bash
   ./platform/install-dify.sh dify-lab
   ```

   It generates random values for every credential Dify uses (app key, internal service keys,
   sandbox key, Postgres and Redis passwords, Weaviate key), stores them in Secret
   `dify-secrets`, and installs the community chart 0.38.0 with `platform/values/dify-lab.yaml`.
   None of the chart's published default credentials remain.

3. Wait until every pod is Running and Ready:

   ```bash
   kubectl get pods -n dify-lab -w
   ```

   Expect 12 Dify workloads: api, worker, beat, web, proxy, plugin-daemon, sandbox,
   agent-backend, local-sandbox, postgresql, redis-master and weaviate.

4. Open Dify:

   ```bash
   kubectl port-forward -n dify-lab svc/dify 8080:80
   ```

   Go to http://localhost:8080, create the admin account on the first-run page, and store the
   password in your password manager.

## Optional: reach Dify without port-forward

Port-forward works everywhere but drops when idle and only works from your machine. For a
stable address your team can share, add an **internal** ingress:

1. Copy `platform/values/ingress-example.yaml` and set your ingress class, host name and TLS
   (ask your platform team which internal ingress class and DNS domain to use).
2. Re-run the install with it. This is a Helm upgrade; Dify's web and API pods restart
   briefly, and data is kept:

   ```bash
   EXTRA_VALUES=my-ingress.yaml ./platform/install-dify.sh dify-lab
   ```

3. Open `https://<your host>` from the VPN or private network.

Keep it internal. Dify's sign-in page and the lab's synthetic customer data shouldn't be
reachable from the internet.

## Be mindful of

- **Create `dify-secrets` once and keep it.** The Postgres and Redis passwords are fixed when the
  databases are first created. Regenerating the Secret later would lock Dify out of its data;
  the script refuses to overwrite it. Rerunning the install script for upgrades is safe.
- **The chart's defaults are public.** Installing the chart directly with `helm install` and no
  overrides leaves published passwords and keys in place. Use the script.
- **Pods stuck Pending with no events** almost always means a storage problem: no default
  StorageClass, or ReadWriteMany volumes (if the values file wasn't used).
- **Upgrades restart Dify.** The api, worker and plugin-daemon use the `Recreate` strategy (the
  old pod stops before the new one starts) because they share a single-attach volume. Expect a
  minute or two of downtime per upgrade.
- **Port-forward drops** after about 30 minutes idle. Rerun the command; nothing is lost.
- **The chart is community-maintained**, not by the Dify team. The lab pins chart 0.38.0
  (Dify 1.16.1), the tested combination. Newer versions may change menus and settings.

## What you'll learn here

- **Dify is many services, not one.** Its API server runs the apps and agents; workers handle
  background jobs; the plugin daemon runs model-provider plugins (every model call goes through
  it); the sandbox runs code; Weaviate stores knowledge-base vectors; Postgres and Redis hold app
  data and queues.
- **How RoonCyber sees it.** Each workload is a separate component. In our testing the API
  server and worker were classified as Workflow Engines, Weaviate as a Vector Store, and the
  plugin daemon and web UI as Applications. Proxy, scheduler, database and cache are ordinary
  infrastructure and aren't treated as AI components.
- **Shared runtime.** Every app you build in Dify runs inside these same containers, under the
  same identities. That's normal for low-code AI platforms, and it's why this lab builds a
  single app.
