# Claude Instructions for argocd-scaffolding

## README hygiene

After **any** change to the following, update `README.md` to stay in sync —
and keep `docs/ARCHITECTURE.md` (including its mermaid diagrams and the
pattern-vs-lab seams table), `docs/DECISIONS.md`, and `docs/GETTING-STARTED.md`
(its commands, file paths, and expected-output blocks) accurate when the flow,
contracts, or design decisions they describe change:
- Directory structure (new dirs, renamed dirs, removed dirs)
- Key technologies (added/removed tools or frameworks)
- Workflow steps (new tenant, new cluster, deploying apps)
- Terraform layout, modules, or the `terraform/infra/templates/` generators
- GitHub Actions workflows (`.github/workflows/`) — triggers and behavior
- The cluster directory layout and label/decision model

Do not leave `README.md` describing a state that no longer exists in the repo.

## Comment hygiene

Comments in code/config/manifest files (`.yaml`, `.tf`, `.rego`, etc.) stay to
1-2 lines: what/why plus a pointer to the doc that carries the full
reasoning. Never restate design or rationale already covered in `README.md`,
`docs/ARCHITECTURE.md`, or `docs/DECISIONS.md` — link to it instead. Long
comment blocks drift out of sync with the docs and bloat the file.

## Generated files — do not edit manually

All generation now happens inside the **infra Terraform run** (`local_file` +
`templatefile`, see `terraform/infra/generate.tf` and `terraform/infra/templates/`).
There is no Python generator and no ytt. These files are produced/refreshed by
`make apply-infra` and must not be edited by hand:

| File | Rendered by (template) |
|------|------------------------|
| `argocd/projects/*.yaml` | `terraform/infra` → `templates/appproject.yaml.tftpl` |
| `argocd/projects/kustomization.yaml` | `terraform/infra` → `templates/projects-kustomization.yaml.tftpl` |
| `infrastructure/clusters/*/vars/tenant-vars.yaml` | `terraform/infra` → `templates/tenant-vars.yaml.tftpl` (needs state: `argo_namespace`) |
| `infrastructure/clusters/*/vars/kustomization.yaml` | `terraform/infra` → `templates/vars-kustomization.yaml.tftpl` |
| `terraform/bootstrap/providers.tf` | `terraform/infra` → `templates/bootstrap-providers.tf.tftpl` |
| `terraform/bootstrap/main.tf` | `terraform/infra` → `templates/bootstrap-main.tf.tftpl` |
| `.kube-backend.config` | `terraform/state-backend` → `local_sensitive_file` in `generate.tf` (kubeconfig with host + token for the kubernetes backend; each root's `backend.tf` sets `config_path` to it; holds a token; **gitignored**, never commit) |
| `.kube-backend.env` | `terraform/state-backend` → `local_sensitive_file` in `generate.tf` (`KUBE_NAMESPACE` — the one backend setting not read from the kubeconfig; sourced by the Makefile; **gitignored**, never commit) |

Note: the `infra`-type tenant's AppProject is always rendered as
`argocd/projects/infra.yaml` (named `infra` — the project the ApplicationSets
target), regardless of the tenant's name. There is no separate hand-authored
`infra` AppProject.

## Source of truth files — edit these, not the generated output

| File | Controls |
|------|---------|
| `terraform/infra/tenants.yaml` | Tenants, namespaces (incl. `environment`), ArgoCD bootstrap, cluster labels, optional `source_repos` (tenant AppProject scoping), `vpc_private_cidr`, and `policies` (per-tenant custom cluster policy catalog — see "Adding a policy") |
| `terraform/infra/policies.tf`, `terraform/infra/rego/*.rego` | The custom cluster policy catalog (`local.policy_catalog`) — one entry per policy kind, referenced by name from a tenant's `policies:` block in `tenants.yaml`. See "Adding a policy". |
| `supervisor-addons/{addon}.yaml` | Registers a third-party helm chart repo as an installable VKS addon (`AddonRepository`/`AddonRepositoryInstall` in `vmware-system-vks-public`). **Not Terraform, not GitOps** — `vmware-system-vks-public` is genuine Supervisor-scope, unreachable by this repo's org-admin (`kubernetes.vcfa-org`) or per-tenant-namespace credentials. Hand-authored, applied manually out-of-band with `kubectl` by a human holding Supervisor-admin access; commands in `docs/GETTING-STARTED.md` Part 1.2. See "Adding a custom helm addon". |
| `terraform/modules/cluster-policy/`, `terraform/modules/cluster-policy-template/` | Vendored from [warroyo/vcfa-terraform-examples](https://github.com/warroyo/vcfa-terraform-examples/tree/main/cluster-policy-custom) (split into two modules — see "Adding a policy" for why). Not tenant-specific; do not edit for a new policy, only to change the underlying `ClusterPolicy`/`ClusterPolicyTemplate` mechanics. |
| `infrastructure/profiles/{env}/`, `apps/profiles/{env}/` | The inherited default set per environment (bases + always-on components + the add-on bundle + env overlay). Edit to change every cluster in an environment at once. |
| `infrastructure/components/addon-bundles/{bundle}/` | Which add-ons a bundle turns on, as one cluster label (`addons.kubernetes.vmware.com/profile`). See "VKS add-ons" → add-on bundles. |
| `infrastructure/components/envs/{env}/`, `apps/components/envs/{env}/` | Real per-environment values AND version pins (bases hold only `replace-me` placeholders). Always-on versions (cluster class, k8s, AKO; package bundle/baseline) apply via the profiles; shared add-on versions live in feature-scoped sub-components (`envs/{env}/istio`, `envs/{env}/headlamp` — `releaseFilter.ref.name`, an `AddonRelease` name) included by the namespace's `namespace-resources` kustomization. Per-cluster canary: `patches:` in the cluster kustomization. |
| `infrastructure/clusters/{project}/{namespace_ref}/{cluster}/` | Hand-authored cluster: `kustomization.yaml` (references a profile + deltas + override patches), `apps/kustomization.yaml`, `cluster-details.yaml` |
| `terraform/bootstrap/locals.tf` | Merges secrets (argo_password) into the per-namespace config from the infra run's `namespace_config` output; repo_url defaults from `argocd/repo-config.yaml`. The `gitops.platform/*` label taxonomy and suffixed namespace names are computed in `terraform/infra/main.tf`. Per-namespace helm tokens are minted fresh by `terraform/bootstrap/vcfa.tf` (no kubeconfigs shuttle). |
| `argocd/repo-config.yaml` | Single repo URL used by all ApplicationSets |
| `docs/examples/cluster-template/` | Copy-me template for a new cluster |
| `docs/examples/namespace-resources-template/` | Copy-me template for a namespace's `namespace-resources/` dir (shared add-on installs) |
| `terraform/state-namespace/{project,state-namespace}.yaml` | CCI `Project` + `SupervisorNamespace` CRs for the Terraform-state backend. Applied once out-of-band with `kubectl` (README → Backend Configuration explains the design; the commands live in `docs/GETTING-STARTED.md` Part 1.1). |
| `terraform/state-backend/namespace.auto.tfvars` | The captured (generated) state-namespace name fed to the stateless `terraform/state-backend` helper. Non-secret; committed. |

## Decision model (label-based targeting)

Each supervisor namespace registers to ArgoCD with `clusterLabels`
(`type: supervisor-ns`, `gitops.platform/project`, `gitops.platform/namespace-ref`,
`gitops.platform/environment`, and `gitops.platform/namespace` = the vcfa-suffixed
name captured at install). The `cluster-provisioning` ApplicationSet joins a cluster
directory to its supervisor namespace on `(project, namespace_ref)` — which is also
the directory path `infrastructure/clusters/{project}/{namespace_ref}/{cluster}/`.
`namespace_ref` must be unique per project (enforced by a precondition in
`terraform/infra/generate.tf`).

The workload `ArgoCluster` registrations mirror this taxonomy (`type: tenant` as
the coarse selector, plus `gitops.platform/project` and
`gitops.platform/namespace-ref` injected by `cluster-var-injector`). The
`cluster-apps` ApplicationSet uses both join keys, so its git path is exact —
`infrastructure/clusters/{project}/{namespace_ref}/{cluster}/` — not a wildcard.

## Local testing

Run `make validate` (or `./scripts/validate.sh`) before pushing — it build-tests every
kustomize entrypoint (argocd root + each cluster's infra and `apps/` dirs + each
`namespace-resources/` dir + temp copies of `docs/examples/cluster-template` and
`docs/examples/namespace-resources-template`), checks each `cluster-details.yaml` against its directory
path, rejects `replace-me` in rendered output (a cluster missing its env overlay), and
cross-checks the apps-side `vars` cluster_name and project. If `opa` is on PATH it also
`opa check`s the `terraform/infra/rego/` policy catalog (skipped cleanly if absent — not a
hard dependency). CI runs the same script, plus `terraform fmt -check` / `terraform
validate` in `validate.yml`. Requires `kustomize`.

## Workflows

### Adding a new tenant
1. Add an entry to `terraform/infra/tenants.yaml` (set per-namespace `environment`).
2. Run `make apply` (or push to `main` — the Apply workflow runs it; it triggers on
   `terraform/**` and `charts/bootstrap-tenant/**`). `apply-infra` provisions the
   namespaces and renders the AppProject, tenant-vars, and bootstrap wiring; commit
   those, then bootstrap runs (`apply-bootstrap` refuses while rendered files are
   uncommitted — `SKIP_GENERATED_CHECK=1` overrides).

### Adding a new cluster
1. `cp -r docs/examples/cluster-template infrastructure/clusters/{project}/{namespace_ref}/{cluster}`
2. Edit `cluster-details.yaml` (`cluster_name`, `project`, `namespace_ref` — must match
   the directory path; `validate.yml` enforces this).
3. In `kustomization.yaml` / `apps/kustomization.yaml`, reference the environment
   profile (`profiles/{env}`) and add only the optional feature components / app
   stacks and any override patches. CNI first: exactly ONE `cni-*` component
   (template defaults to `cni-antrea` + `antrea-nsx`; day-0 only, immutable
   after creation). Add-ons come from the profile's bundle
   (`addon-bundles/standard` — istio, external-secrets, observability); opt out
   per cluster with `disable-istio` / `disable-external-secrets` /
   `disable-observability`. Add `ako-istio` only when the cluster runs AKO/AVI,
   and `components/istio-config` only for per-cluster istio value overrides.
   The shared `AddonInstall` and its version pin live in the
   namespace's `namespace-resources/` dir — if the namespace doesn't have one,
   copy `docs/examples/namespace-resources-template`. (headlamp is dev-only via
   `envs/dev`; opt out with `disable-headlamp`, no version to pin.) Keep `cluster-var-injector` **last** in the infra
   component list (it rewrites resources brought in by the profile and the components).
   The apps-side injector (`apps/components/cluster-var-injector`, also last)
   and its `vars` configMapGenerator (`cluster_name` **and** `project` — the
   apps tree can't read `../cluster-details.yaml`, kustomize load
   restrictions) are **required on every cluster**, not just ones using
   `apps/base/istio-ako-patch` — the standard app stack's `apps/base/tenant-sync`
   (this tenant's ArgoCD sync-impersonation identity, see "Adding a policy" and
   `docs/ARCHITECTURE.md`) needs `project` injected everywhere. `validate.sh`
   cross-checks both against the directory path.
4. Commit. The `cluster-provisioning` ApplicationSet picks it up via label join — the
   vcfa-generated namespace name is resolved from the cluster registration, not git.

### Adding a policy
Full design (why Terraform not GitOps, the label-ownership model, sync
impersonation) is in `docs/ARCHITECTURE.md` → "Cluster policy + namespace
self-service"; rationale in `docs/DECISIONS.md`. This section is the recipe.

1. Write `terraform/infra/rego/{policy-name}.rego` — rule bodies only, the
   `cluster-policy-template` module prepends `package <template_name>`
   (Rego syntax matches the vendored
   [warroyo/vcfa-terraform-examples](https://github.com/warroyo/vcfa-terraform-examples/tree/main/cluster-policy-custom)
   reference: `violation[{"msg": msg}] { ... }` partial-set rules).
2. Add an entry to `local.policy_catalog` in `terraform/infra/policies.tf`:
   `template_name` (lowercase of `constraint_kind` — Gatekeeper requirement),
   `constraint_kind`, `rego` (via `file()`), `parameters_schema`,
   `target_resources`, and `selector_mode` (`"none"` for a cluster-scoped kind
   like `Namespace`; `"in"` / `"not_in"` to scope by
   `gitops.platform/project` on namespaced kinds).
3. Enable it per tenant in `tenants.yaml` under that tenant's `policies:` key
   (`enforcement: dryrun` first — always). `project` and `syncServiceAccounts`
   are computed by Terraform and always win the merge — do not try to
   override them from `parameters:`.

Three constraints that shape every policy here:
- **`ClusterPolicyTemplate` is an org-wide singleton** (`@org` namespace) —
  `policies.tf` creates one per unique enabled `policy_name` across ALL
  tenants (`local.enabled_templates`), never per-tenant. Adding a policy adds
  one catalog entry, not one per tenant.
- **Project scope only** — cluster-scoped `ClusterPolicy` needs a
  `cluster_name`/`supervisor_namespace_name` Terraform can't know (clusters
  are born from git via the `cluster-provisioning` ApplicationSet).
- **Scope `target_resources` narrowly.** The Gatekeeper webhook backing this
  (VKSM) only auto-exempts `gatekeeper-system` / `kube-system` /
  `vmware-system-vksm` — no `vmware-system-*` wildcard (verified live). A
  policy targeting a broad kind like `Pod` would evaluate in every other
  platform namespace and duplicate VKSM's own built-in pod-security policies.
  The four shipped policies stay narrow (`Namespace`; ingress/Service kinds
  only) specifically to avoid this — keep new policies just as narrow, or use
  `selector_mode` to scope by tenant ownership instead of an exclude-list.

Identity: policies that gate on the tenant's own gitops flow key on
`system:serviceaccount:platform-gitops:tenant-sync-<tenant>` — the per-tenant
ArgoCD sync-impersonation identity (`apps/base/tenant-sync`, named by
`apps/components/cluster-var-injector`, wired via the AppProject's
`destinationServiceAccounts`). Per-tenant, not shared: a tenant landing on
another tenant's cluster (the AppProject's `destinations` allow any
registered cluster by name — see its own comment) impersonates its own name,
which doesn't exist as a service account there, so the sync fails outright
rather than silently acting under a trusted identity.

### Adding a custom helm addon
Some add-ons (e.g. `external-secrets`) aren't in the built-in VKS catalog
(unlike istio/headlamp, which VMware ships pre-registered) — VKS 3.7+ lets a
helm chart repo be registered as an installable addon directly with a plain
CR, no Carvel packaging pipeline needed. Full rationale in `docs/DECISIONS.md`
#14. This section is the recipe; once registered, consumption is the exact
same Variant A pattern as any other add-on (CLAUDE.md "VKS add-ons").

**Two hard prerequisites — check both before registering anything:**
- **Every cluster on the Supervisor needs helm-controller**, which means a
  **3.7+ cluster class** (`builtin-generic-v3.7.0`, pinned in
  `components/envs/{env}`). The 3.7 class makes the platform auto-label the
  Cluster `addon.addons.kubernetes.vmware.com/helm-controller: automatic`; a
  built-in `AddonInstall` then installs it, which is what creates the
  `HelmRepository` CRD and `vmware-system-helm` namespace a helm add-on
  renders into. On a 3.6 class none of that exists and the add-on fails.
- **Registration is Supervisor-wide, not tenant-scoped.** See the blast-radius
  warning below. Verify the whole fleet is on 3.7 first.

1. Write `supervisor-addons/{addon}.yaml`: an `AddonRepository`
   (`spec.fetch.helmRepository.url`, `spec.addonFilters` — the upstream
   `chart_name` and the `versions` list to make selectable, `spec.version` as
   the catalog-entry version, bumped when `versions` changes, not the chart
   version) plus an `AddonRepositoryInstall` referencing it, both in
   `vmware-system-vks-public`. The `AddonRepository` **must** carry the
   `addons.kubernetes.vmware.com/package-offerings` annotation — a JSON string
   with `repositoryVersion` (= `spec.version`) and a `packages` map mirroring
   `spec.addonFilters`. It is undocumented in the CRD but enforced by the
   validating webhook, which rejects the object outright without it. **Not
   Terraform, not GitOps** —
   `AddonRepository`/`AddonRepositoryInstall` need genuine Supervisor-admin
   access; this repo's org-admin (`kubernetes.vcfa-org`) and per-tenant
   credentials can't reach that namespace (read-only at best). Apply by hand:
   `kubectl apply -f supervisor-addons/{addon}.yaml` using your own
   Supervisor-admin session — see `docs/GETTING-STARTED.md` Part 1.2. Re-apply
   only when the file changes (new chart version, etc.) — never via `make
   apply` or CI.
2. `infrastructure/base/{addon}/` — the `AddonInstall`, same shape as any
   other add-on, with one difference: `releaseFilter.ref.name` is
   `"<chart_name>.<version>"` instead of the vendor's longer `AddonRelease`
   name. Registration *does* mint an `AddonRelease` (verified live:
   `external-secrets.2.8.0`), so the `namespace` field works the same as any
   other add-on and only the naming convention differs.
3. Everything else — env version pin, default-on/opt-in label, namespace-
   resources wiring — follows CLAUDE.md "VKS add-ons" exactly.

**Blast radius — the reason to think twice.** Registering the repo makes the
platform auto-create a `helm-repo` `AddonInstall` in `vmware-system-vks-public`
with `clusters: []` and `crossNamespaceSelection: Allowed`, which per the CRD
means *every cluster on the Supervisor*, including other tenants'. Any cluster
without helm-controller then fails that ClusterAddon and error-loops the shared
addon controller until it gets one. There is **no way to scope this** (all
verified live): the CRs are rejected outside `vmware-system-vks-public`,
`AddonRepositoryInstall` has no selector field, and the generated `helm-repo`
`AddonInstall` can be neither patched nor deleted — even by Supervisor-admin.
Registering a custom helm repo is therefore a fleet-wide decision, not a
tenant one.

### Changing every cluster in an environment
Edit `infrastructure/profiles/{env}` (or `apps/profiles/{env}`) — every cluster that
references that profile inherits the change. Real per-environment values live in
`infrastructure/components/envs/{env}`.

### VKS add-ons: one pattern, two variants
The design (diagram, variant table, CRD semantics) lives in
`docs/ARCHITECTURE.md` → "VKS add-on pattern"; rationale in `docs/DECISIONS.md`
#9. This section is the recipe.

Conventions (every add-on): all addon resources labeled
`app.kubernetes.io/name: {addon}`; all kustomize patches target by
`labelSelector`, never exact name; bases carry `replace-me` where an env pin is
mandatory (`validate.sh` rejects it in rendered output).

**Variant A — installable add-on (istio, headlamp).** ONE shared `AddonInstall`
per supervisor namespace, gated by a cluster label — never a per-cluster install:
1. `infrastructure/base/{addon}/` — the `AddonInstall`: the two-selector
   profile block below, `stopMatchingBehavior: Delete`, and
   `releaseFilter.ref: {name: replace-me, namespace: vmware-system-vks-public}`.
   The version pin is the `releaseFilter` (an `AddonRelease` name) — the API has
   **no `AddonInstall.spec.version` field**; a value set there is pruned by the
   API server and the add-on silently floats to the latest release.
2. `infrastructure/components/envs/{env}/{addon}/` — pins the `AddonRelease`
   (patches `/spec/releaseFilter/ref/name`).
3. `infrastructure/clusters/{project}/{namespace_ref}/namespace-resources/` — a
   kustomization pulling in `base/{addon}` + the `envs/{env}/{addon}` component
   (copy `docs/examples/namespace-resources-template`). The `namespace-resources`
   ApplicationSet syncs this dir ONCE into the supervisor namespace (one owner,
   even when clusters share the namespace).
4. Enablement — see "Add-on profiles" below. Default-on: join a bundle. Add a
   `disable-{addon}` component (`op: add`, value `disabled`) so clusters can opt
   out; `Delete` handles uninstall when the label flips.
5. Per-cluster value overrides are OPT-IN and separate: a
   `components/{addon}-config` component pulling `base/{addon}-config` — an
   `AddonConfig` named `cluster-{addon}` (injector-prefixed to
   `<cluster>-{addon}`, matching the controller's default
   `addonConfigNameTemplate`), values only. Omit `addonConfigDefinitionRef` and
   `clusterName` — the addon controller fills both, and auto-generates the whole
   `AddonConfig` for clusters that ship none (so a cluster on defaults ships
   nothing). Istio is wired this way (`base/istio` + `base/istio-config`).

**Add-on bundles.** Clusters carry a bundle label —
`addons.kubernetes.vmware.com/profile: standard`, added by
`components/addon-bundles/{bundle}` and inherited via `profiles/{env}` — that
every add-on in the bundle selects on. Membership lives in the add-on's own
`AddonInstall`, not in the env layer. Current bundle `standard` = istio +
external-secrets + observability. The **label key stays `.../profile`** even
though the directory is `addon-bundles/` — it's the vendor-namespaced,
cluster-facing selector already written into every `AddonInstall`; the
directory name is what keeps "bundle" distinct from `profiles/{env}` (the env
composition root). Copy this selector block verbatim, swapping the add-on key:
```yaml
clusters:
- selector:            # profile grants it, unless explicitly disabled
    matchExpressions:
    - {key: addons.kubernetes.vmware.com/profile, operator: In,    values: ["standard"]}
    - {key: addons.kubernetes.vmware.com/{addon}, operator: NotIn, values: ["disabled"]}
- selector:            # explicit opt-in, no profile required
    matchExpressions:
    - {key: addons.kubernetes.vmware.com/{addon}, operator: In,    values: ["enabled"]}
```
Three rules that make it work — get one wrong and the override silently stops
working (rationale: `docs/DECISIONS.md` #15):
- `spec.clusters` entries **OR**. A per-add-on label can never be a second
  selector for opt-*out* — it would only add clusters. The negation must be an
  extra `matchExpressions` entry in the *same* selector, where they AND.
- `NotIn` matches clusters that **lack** the key, so a profile-only cluster
  installs. Never write the opt-out as `In [enabled]`-style logic.
- Built-in add-ons (observability, AKO) have an `AddonInstall` we don't author,
  so they can't get a profile selector. Bundle membership for those = the
  profile component setting their **native** label
  (`automated-monitoring`, `ako.kubernetes.vmware.com/install`).

Env-scoped add-ons stay out of bundles: headlamp is dev-only, so its label is
an `op: add` in `components/envs/dev`. Pairing components stay out too —
`ako-istio` is per-cluster because istio doesn't imply AKO/AVI.

**Variant B — auto-installed core add-on (ako, antrea).** The platform installs
it; there is no `AddonInstall` to author. Per-cluster `AddonConfig` only
(`base/{addon}`, injector-prefixed name), overrides only. AKO pins its
`AddonConfigDefinition` in `envs/{env}` (use the real definition name — `---`
separator, not `+`); antrea has no version to pin. Antrea's
`owned-for-deletion: "true"` annotation is vendor-recommended — keep it.
Auto-installed add-ons are delivered by BUILT-IN AddonInstalls
(in `vmware-system-vks-public`, `stopMatchingBehavior: Delete`): AKO selects
`ako.kubernetes.vmware.com/install: "true"` (platform-added label; opt out with
`components/disable-ako`), prometheus/telegraf select
`addons.kubernetes.vmware.com/automated-monitoring: enabled` (set by
`addon-bundles/standard`; `disable-observability` / `enable-observability`
flip it). Antrea is
NOT label-gated — it's the cluster's CNI, selected in the Cluster spec
(`spec.topology.variables` → `bootstrapAddons.cniRef`); only its settings go
through the AddonConfig. Every cluster declares its CNI explicitly: exactly ONE
`cni-*` component (`cni-antrea` | `cni-cilium` | `cni-calico`), never in the
profile — **day-0 only** (`bootstrapAddons` is immutable after creation,
k8s 1.35+). `cni-antrea` (the default made explicit) also brings the antrea
AddonConfig; `antrea-nsx` is a settings-only patch included after it.

### Rolling a version
Versions are never pinned in bases. Bump the pin in the env layer —
`infrastructure/components/envs/{env}` (cluster class, k8s, AKO),
`envs/{env}/istio`, `envs/{env}/headlamp` (shared add-on `AddonRelease` pins,
applied via namespace-resources), or `apps/components/envs/{env}`
(package bundle, cert-manager) — dev first, then prod. Canary a
single cluster with a `patches:` override in its kustomization before bumping the
env pin (for shared add-ons, canary per namespace: a `patches:` override in one
namespace-resources kustomization).
