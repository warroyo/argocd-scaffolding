# Getting started: zero to a running app

This walkthrough takes you from a fresh VCF Automation org to a tenant
application running on a GitOps-managed workload cluster. Budget an afternoon:
about an hour of hands-on work, plus provisioning wait time.

It assumes nothing beyond the prerequisites below. If you want to understand
*why* a step works the way it does, [ARCHITECTURE.md](ARCHITECTURE.md) explains
the design and [DECISIONS.md](DECISIONS.md) explains the choices — but you
don't need either to finish this.

> **About the sample output:** blocks marked *you should see* are
> illustrative. Generated names (the `-abcde` style suffixes), counts, and
> timings will differ in your environment.

## Part 0 — What you need

**Tools** on your machine:

| Tool | Version | Used for |
|------|---------|----------|
| `terraform` | ≥ 1.9 | provisioning + rendering |
| `kustomize` | 5.x | `make validate` (same version CI pins) |
| `kubectl` | recent | one-time state-namespace setup, verification |
| `envsubst` | any (gettext) | rendering the state-namespace manifest (Part 1); macOS: `brew install gettext` |
| `vcf` CLI | recent | pointing kubectl at your VCF endpoint |
| `make`, `git` | any | orchestration |

**From your VCF Automation org** (ask your provider admin if unsure):

- the vcfa URL, org name, and an **API refresh token**
- the **region name**, a **zone name** in it, and a **storage policy** name —
  these vary per install and there are no safe defaults
- whether that region's **load balancer is AVI/NSX-ALB or NSX_LB** — this sets
  `TF_VAR_avi_enabled` (and, for AVI, a **Service Engine Group** name for
  `TF_VAR_seg_name`). Getting it wrong fails `apply-infra` at VPC creation. Ask
  your provider admin if unsure.

**A fork of this repo.** GitOps means ArgoCD pulls from git, so you need a
repo you can push to:

1. Fork, clone, `cd` into it.
2. Edit `argocd/repo-config.yaml` and set `repoURL` to your fork. This is the
   **single** place the repo URL lives — Terraform and the ApplicationSets
   both read it.

## Part 1 — One-time state backend (~10 min)

Terraform state lives as Kubernetes Secrets in a small, dedicated supervisor
namespace, so any machine (or CI) with VCF credentials can run the pipeline.
That namespace is created once, by hand. Its `regionName` / `vpcName` / zone /
storage policy vary per install with **no safe defaults**, so
`state-namespace.yaml` ships as `${...}` placeholders filled from your `.env` —
create `.env` now (you'll finish filling it in Part 2), set the region and the
three `STATE_NS_*` values, then render the manifest with `envsubst`:

```sh
vcf context use <your-vcfa-context>     # points kubectl at the vcfa endpoint

cp .env.example .env
# edit .env: set TF_VAR_region_name and STATE_NS_VPC / STATE_NS_ZONE /
# STATE_NS_STORAGE_POLICY to match your install (the rest can wait for Part 2)

set -a; . ./.env; set +a                # load .env into this shell
kubectl create -f terraform/state-namespace/project.yaml
NAME=$(envsubst < terraform/state-namespace/state-namespace.yaml | kubectl create -f - -o jsonpath='{.metadata.name}')
echo "namespace = \"$NAME\"" > terraform/state-backend/namespace.auto.tfvars
git add terraform/state-backend/namespace.auto.tfvars
git commit -m "capture state namespace name"
```

*You should see* a generated name land in the tfvars file:

```
$ cat terraform/state-backend/namespace.auto.tfvars
namespace = "tf-state-bh7q6"
```

Two things worth knowing:

- It's `kubectl create` (not `apply`) because the namespace uses
  `generateName` — the API assigns the real name. Re-running `create` makes a
  *second* namespace, so this is deliberately a one-time step.
- `envsubst` substitutes an empty string for any value left blank in `.env`;
  the API then rejects the object (empty `regionName`/`vpcName`/zone are
  invalid), so a missed value surfaces as a failed `create`, not a
  misconfigured namespace.

You never touch this again. Every `make` target refreshes its own short-lived
credentials against this namespace automatically.

## Part 2 — Tenants and the GitOps control plane (~20 min)

### 2.1 Credentials

You created `.env` in Part 1 (region + `STATE_NS_*`). Now finish the vcfa
values (`TF_VAR_vcfa_url`, `TF_VAR_vcfa_org`, `TF_VAR_vcfa_refresh_token`). The
Makefile loads `.env` into every Terraform run — no per-directory tfvars
needed.

**Set your load-balancer mode.** `.env` defaults to `TF_VAR_avi_enabled=false`
(NSX_LB). If your region uses **AVI/NSX-ALB**, set `TF_VAR_avi_enabled=true` and
uncomment `TF_VAR_seg_name` with your Service Engine Group — a mismatch fails
`apply-infra` at VPC creation. For NSX_LB, leave `TF_VAR_seg_name` commented (it
must stay unset, not empty).

For the ArgoCD admin password, the chart expects a **bcrypt hash**, not the
plain password:

```sh
htpasswd -bnBC 10 "" 'your-password' | tr -d ':\n'
```

Put the hash in `TF_VAR_argo_password`. Leave `TF_VAR_repo_url` empty — it
defaults to `argocd/repo-config.yaml`, which you already set.

### 2.2 Declare your tenants

`terraform/infra/tenants.yaml` is the source of truth. You need exactly one
`type: infra` tenant (it hosts the ArgoCD that manages everything) and, for
this walkthrough, one developer tenant:

```yaml
tenants:
  - name: "tenant-1"
    type: tenant
    argo_namespace: "infra"        # which infra namespace's ArgoCD manages it
    namespaces:
      - name: "dev-1"
        environment: dev           # selects the kustomize profile
        zone_name: "z-wld-a"       # SET EXPLICITLY — zone names vary per region
        storage_limit: "200Gi"
        mem_limit: "30Gi"
        cpu_limit: "20000M"
  - name: "infra-1"
    type: infra
    argo_namespace: infra
    namespaces:
      - name: "infra"
        environment: prod
        zone_name: "z-wld-a"       # your zone here too
        deploy_argo: true          # this namespace runs the ArgoCD instance
        storage_limit: "20Gi"
        mem_limit: "4Gi"
        class_name: large
```

Anything you don't set (`class_name`, `storage_policy`, …) gets a default from
`terraform/modules/tenant/variables.tf` — check the storage-policy default
matches your install.

### 2.3 Provision

```sh
make apply-infra
```

*You should see* Terraform create the projects, VPCs, and supervisor
namespaces, then render config into the repo:

```
Apply complete! Resources: 14 added, 0 changed, 0 destroyed.

$ git status --short
 M argocd/projects/kustomization.yaml
?? argocd/projects/tenant-1.yaml
 M infrastructure/clusters/tenant-1/vars/tenant-vars.yaml
 M terraform/bootstrap/providers.tf
 M terraform/bootstrap/main.tf
```

Those rendered files are the Terraform → ArgoCD handoff. **Commit and push
them** — ArgoCD reads git, not your working tree:

```sh
git add argocd/projects infrastructure/clusters/*/vars terraform/bootstrap/{providers,main}.tf
git commit -m "rendered config for tenants" && git push
```

Then install the control plane:

```sh
make apply-bootstrap
```

*You should see* one helm release per namespace
(`module.bootstrap_tenant_1_dev_1…`, `module.bootstrap_infra_1_infra…`).

**If not:** `apply-bootstrap` refusing with *"generated files are
uncommitted"* is the guard working, not a bug — commit the rendered files
first. An authentication error usually means an expired token in `.env`.

### 2.4 Verify ArgoCD is up

The infra namespace got a vcfa-suffixed name (e.g. `infra-kyrtt`). Find it and
look inside (service/pod names come from the vSphere ArgoCD operator, so use
discovery rather than exact names — your environment may differ):

```sh
vcf context use <your-vcfa-context>
kubectl get ns | grep infra           # find the suffixed name
kubectl get pods,svc -n infra-kyrtt   # ArgoCD pods + a UI service
```

Open the UI via the service's external address (or port-forward it) and log
in as `admin` with the password you hashed in 2.1.

*You should see* in ArgoCD:

- one Application: `root-bootstrap` (synced — it deploys the `argocd/` dir)
- AppProjects `infra` and `tenant-1`
- ApplicationSets `cluster-provisioning` and `cluster-apps`
- **zero generated Applications — this is correct.** No cluster directories
  exist in git yet, so the ApplicationSets have nothing to generate. That's
  the next part.

## Part 3 — Your first cluster (~30 min + provisioning time)

### 3.1 Create the cluster directory

```sh
cp -r docs/examples/cluster-template \
  infrastructure/clusters/tenant-1/dev-1/dev1-cluster
```

The three path segments are the join keys: `tenant-1` (the tenant), `dev-1`
(the namespace you declared in tenants.yaml), `dev1-cluster` (your new
cluster's name, which need only be unique within this `(tenant, namespace)`).
ArgoCD matches this directory to the right supervisor namespace by these names —
nothing else links them.

Edit `infrastructure/clusters/tenant-1/dev-1/dev1-cluster/cluster-details.yaml`
so the three values match the path exactly:

```yaml
data:
  cluster_name: dev1-cluster
  project: tenant-1
  namespace_ref: dev-1
```

Then open `kustomization.yaml` in the same directory: it already inherits the
dev profile; uncomment optional features you want. **Pair every feature with
its `envs/dev` sub-component** (e.g. istio needs `components/istio`,
`components/ako-istio`, AND `components/envs/dev/istio` — the last one pins
the version). Same idea in `apps/kustomization.yaml` for app stacks.

### 3.2 Validate before pushing

```sh
make validate
```

*You should see:*

```
building argocd
building infrastructure/clusters/tenant-1/dev-1/dev1-cluster
building infrastructure/clusters/tenant-1/dev-1/dev1-cluster/apps
building docs/examples/cluster-template (temp copy)
OK: all kustomize entrypoints build
```

**If not**, the two most common failures:

```
::error::…/cluster-details.yaml: cluster_name is 'my-cluster' but path implies 'dev1-cluster'
```
→ `cluster-details.yaml` doesn't match the directory path (step 3.1).

```
::error::…: rendered output contains 'replace-me' — an environment overlay (components/envs/{env}) is missing or incomplete
```
→ you enabled a feature without its `envs/dev` sub-component.

### 3.3 Push and watch

```sh
git add infrastructure/clusters/tenant-1 && git commit -m "add dev1-cluster" && git push
```

Within a sync interval, *you should see* in ArgoCD a new Application named
**`tenant-1-dev-1-dev1-cluster-provision`** (`{project}-{namespace_ref}-{cluster}-provision`).
It creates the VKS `Cluster` in the
supervisor namespace — watch it come up (10–20 min is normal):

```sh
kubectl get cluster -n dev-1-abcde -w      # your suffixed dev namespace
NAME           PHASE          AGE
dev1-cluster   Provisioning   2m
dev1-cluster   Provisioned    14m
```

Once the cluster is ready, its `ArgoCluster` registration attaches it to
ArgoCD, and a second Application appears: **`dev1-cluster-apps`** — the app
stack (package repo, cert-manager, anything you enabled) reconciling onto the
new cluster.

**If no Application ever appears** — this failure is *silent* by design of
ApplicationSets, so check the join: the cluster registration's
`gitops.platform/project` and `gitops.platform/namespace-ref` labels must
equal the first two directory segments. Mismatch means the ApplicationSet
found no pairing. The label model is explained in
[ARCHITECTURE.md](ARCHITECTURE.md#the-decision-model-label-join).

## Part 4 — A tenant deploys their app

Everything so far was the platform team. Now the payoff: tenants deploy from
**their own repos** — the platform repo never carries tenant manifests.

`docs/examples/sample-tenant-repo/` shows the shape of a tenant's repo: plain
kustomize app manifests plus one ArgoCD `Application` pointing at them:

```yaml
# the tenant's app.yaml (see docs/examples/sample-tenant-repo/tenant-1/app.yaml)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: music-store-app
spec:
  project: tenant-1                  # their AppProject — this is the boundary
  source:
    repoURL: https://github.com/<the-tenant>/<their-repo>
    targetRevision: main
    path: tenant-1/clusters/dev1-cluster
  destination:
    name: dev1-cluster               # their cluster, by registration name
    namespace: music-store
  syncPolicy:
    automated: {prune: true, selfHeal: true}
```

The Application resource itself lives in the managing ArgoCD's namespace.
Today that means the platform operator applies it (or the tenant uses the
ArgoCD UI/CLI — per-tenant SSO/RBAC is tracked in [BACKLOG.md](BACKLOG.md)):

```sh
kubectl apply -f app.yaml -n infra-kyrtt    # the suffixed infra namespace
```

The `tenant-1` AppProject is the enforcement boundary: it denies the
supervisor-namespace and in-cluster destinations and allows no cluster-scoped
resources except `Namespace` — a tenant Application can deploy workloads to
workload clusters, and nothing else.

*You should see* the app sync, and on the workload cluster:

```sh
kubectl get pods -n music-store     # against dev1-cluster's kubeconfig
NAME                        READY   STATUS    RESTARTS   AGE
cart-5f6c…                  1/1     Running   0          1m
catalog-7d9b…               1/1     Running   0          1m
```

## You're done — and what you have now

- **Add a namespace or tenant:** edit `tenants.yaml`, `make apply`, commit the
  rendered files (or push to `main` and let the Apply workflow do all of it).
- **Add a cluster:** copy the template, edit three values, push (Part 3).
- **Roll a version:** bump one pin in `components/envs/dev`, let it soak,
  mirror to prod — see the README's *Version management* section.
- **Change every dev cluster at once:** edit `infrastructure/profiles/dev`.

One warning before you experiment freely:

- **Deletion is live.** Deleting — or *renaming* — a cluster directory
  deletes the actual cluster (a rename is a delete + recreate to ArgoCD).
  Guardrails are tracked in [BACKLOG.md](BACKLOG.md).

Where to go next: [ARCHITECTURE.md](ARCHITECTURE.md) for how it all fits
together (including what to swap for your environment — *Pattern vs lab*),
[DECISIONS.md](DECISIONS.md) for why it's built this way.
