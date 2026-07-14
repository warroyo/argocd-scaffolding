# Backlog

Tracked follow-up work for this repo, captured during the infra/refactor reviews
(including the round-3 "blind spots" review of day-2 / reverse-gear gaps).
Pick items from here in later sessions. Each item notes **why**, the **blocker**
(if any), and a rough **size**. Keep this file in sync — move done items to the
bottom or delete them.

Priority key: **P1** = correctness/security worth doing soon · **P2** = solid
improvement · **P3** = nice-to-have / hygiene.

## Open

### P1 — Defuse deletion (deletion semantics are designed nowhere, and armed)
- **What:** `cluster-provisioning` has `automated: {prune: true}` + the
  `resources-finalizer` — deleting, **renaming** (= delete + create), or
  reverting a cluster directory prunes the VKS `Cluster` CR and vSphere tears
  down the live cluster. Tenant removal ordering is also undefined: terraform
  destroys the supervisor namespace while workload clusters may still run in it,
  and the root app prunes the AppProject while tenant Applications reference it.
- **Action:** set ApplicationSet-level `spec.syncPolicy.preserveResourcesOnDeletion: true`
  on both appsets (Application deletion no longer cascades; deliberate teardown
  deletes the Cluster CR explicitly); write a teardown runbook (drain/delete
  cluster dirs → wait for deprovision → remove tenant from tenants.yaml →
  `make apply` → commit deletions); call out the rename trap in the template README.
- **Note:** appset Application names are now path-scoped to
  `{project}-{namespace_ref}-{cluster}` (so bare cluster names may repeat). The
  `preserveResourcesOnDeletion` flag is intentionally **not** set — teardown
  still relies on the Application finalizer cascading (`make destroy-apps`), and
  dir-deletion still deprovisions. The rename trap remains armed.
- **Size:** S.

### P1 — Rotate and externalize credentials
- **What:** `infrastructure/base/ako/ako.yaml` commits a real AVI
  username/password/CA (base64) and ships it to every cluster as
  `cluster-avi-secret`. This workload-side secret should move to
  Terraform/external-secrets instead of git.
- **Action:** Rotate the leaked credentials (they are in git history), then wire the
  workload secret through Terraform/external-secrets instead of git.
- **Owner note:** Intentionally left untouched on request.
- **Size:** M.

### P1 — ArgoCD human access (SSO + per-tenant RBAC)
- **What:** the only credential is a single shared admin password (TF var). The
  AppProject lockdown only matters once tenants authenticate as themselves —
  today it's either admin-for-everyone or ticket-driven.
- **Action:** SSO/OIDC on the ArgoCD instance (check what the
  `argocd-service.vsphere.vmware.com` operator CR exposes) + ArgoCD RBAC roles
  mapping tenant groups to their AppProjects.
- **Size:** M–L (depends on operator support).

### P1 — Platform DR: terraform state lives on the platform it manages
- **What:** state is a k8s Secret in a supervisor namespace on the same vCFA
  install terraform manages — if the platform dies, the state needed to rebuild
  it dies with it. Also one state file for ALL tenants: shared blast radius,
  serialized applies.
- **Action:** scheduled `terraform state pull` backup off-platform (cheap first
  step: a `make backup-state` target + CI artifact); longer term consider
  per-tenant state separation.
- **Size:** S (backup) / L (state split).

### P2 — Progressive rollout for fleet-wide changes
- **What:** Both ApplicationSets are `automated` + `prune` + `selfHeal`; a bad
  profile commit still hits every cluster in an environment at once.
- **Note:** version pins are now decoupled per environment (envs/{env} +
  feature sub-components) with per-cluster canary via `patches:` — that was the
  prerequisite. Remaining: ApplicationSet `strategy: RollingSync` keyed on the
  `gitops.platform/environment` label for intra-env staging.
- **Size:** M.

### P2 — Failure visibility (silent zero-Application mismatches)
- **What:** a supervisor namespace whose labels match no cluster directory (or
  vice versa) generates zero Applications and zero errors; sync failures notify
  nobody; terraform-side drift (quota edits in the vCFA UI) is silently absorbed
  on refresh.
- **Action:** argocd-notifications (if the operator CR allows it) for sync
  failures; a periodic check comparing cluster dirs in git vs generated
  Applications; consider a scheduled `terraform plan` drift job.
- **Size:** M.

### P2 — Git boundary for tenants (CODEOWNERS / branch protection)
- **What:** tenants PR into `infrastructure/clusters/{their-project}/`, but
  nothing stops a tenant PR from editing profiles, appsets, terraform, or
  another tenant's directory. validate.sh checks correctness, not authorization.
- **Action:** CODEOWNERS mapping `infrastructure/clusters/{project}/` to tenant
  teams and everything else to the platform team; branch protection requiring
  owner review.
- **Size:** S.

### P2 — Tenant secrets pattern
- **What:** tenants deploying real apps need image-pull secrets and app
  credentials on day one; there's no external-secrets / sealed-secrets / SOPS
  pattern for them to follow — which is how credentials end up committed.
- **Action:** pick one (external-secrets fits the stack), ship it in the
  standard stack, document the tenant workflow.
- **Size:** M.

### P2 — ArgoCD instance upgrade ownership
- **What:** the ArgoCD version (`3.0.19` in chart values) is set at bootstrap
  and never reconciled afterwards; nobody owns upgrading the instances.
- **Action:** decide the path (bump chart value + `make apply-bootstrap` as the
  documented procedure, or move the ArgoCD CR under gitops management).
- **Size:** S (document) / M (gitops-manage).

### P2 — Tenant-to-tenant cluster isolation in AppProjects
- **What:** The tenant AppProject denies the in-cluster and supervisor-namespace
  destinations and drops the cluster-resource grant, but a tenant can still
  target ANOTHER tenant's workload clusters — cluster names carry no tenant
  prefix to match a destination glob on.
- **Options:** prefix workload cluster names with the project (join + validate
  changes), or per-tenant destination labels.
- **Size:** M.

### P2 — Bring cluster policy APIs under gitops (via Terraform)
- **What:** cluster policy APIs are not represented in the repo at all — any
  policies are applied out-of-band, invisible to review and drift detection.
  Constraint: cluster policy has to be managed through Terraform, so it cannot
  ride the kustomize tree / ApplicationSets like other addons.
- **Action:** model policies in `terraform/infra` — decide the input surface
  (per-tenant/per-namespace fields in `tenants.yaml` vs a dedicated policy
  vars file), add the policy resources to the infra run, and document the
  workflow (edit tenants.yaml → `make apply`, same as adding a tenant).
  Terraform ownership also means the scheduled-`terraform plan` drift idea
  under "Failure visibility" would cover policy drift.
- **Size:** M.

### P2 — Document the addon-addition workflow
- **What:** the repo has a clear addon pattern (VKS `AddonConfig` base with a
  `replace-me` version placeholder + optional-feature component + feature-scoped
  `envs/{env}/{feature}` version pin + per-cluster opt-in; apps-side stacks for
  non-AddonConfig software), but it's only discoverable by reading the istio
  example. Nothing in `docs/` walks through adding a brand-new addon end-to-end.
- **Action:** add a "adding an addon" guide (docs/ or ARCHITECTURE.md section):
  infra-side AddonConfig addons vs apps-side stacks, where the version pin
  goes, the `cluster-var-injector` ordering rule, the validate.sh
  `replace-me` check as the safety net, and a checklist mirroring the istio
  layout. Cross-link from the cluster-template README.
- **Size:** S.

### P2 — Commit `.terraform.lock.hcl` files
- **What:** Provider versions are pinned (`~>` constraints) but the dependency
  lock files are not committed, so CI still resolves fresh each run.
- **Action:** Run `terraform init` in each root (`-backend=false` is fine) and
  commit the lock files.
- **Blocker:** Needs registry access from a dev machine (provider binaries are
  fetched from github release assets).
- **Size:** XS.

### P3 — Headlamp addon
- **What:** no cluster UI ships with the standard stack; Headlamp is a
  lightweight candidate tenants could opt into per cluster.
- **Action:** add it via the standard addon pattern — check whether a VKS
  `AddonConfig` definition exists for Headlamp (infra-side addon) or ship it
  as an apps-side stack (helm chart via the package-installer / a
  `apps/components/stacks/` entry); include the auth story (SSO vs
  token) in the docs. Good first consumer of the addon-addition guide above.
- **Size:** S–M.

### P3 — Region dimension
- **What:** `region_name` is one global variable; VPC names embed it; zones
  default to one name; tenants.yaml has no region field. Multi-region means
  repo-per-region or adding a region dimension to tenants.yaml, profiles, and
  the label taxonomy.
- **Action:** decide the model BEFORE naming conventions calcify.
- **Size:** L.

### P3 — Per-tenant ArgoCD scaling path
- **What:** all provisioning and tenant apps flow through the single infra
  instance (controller CPU already at 4). The taxonomy half-supports per-tenant
  instances (`argo_namespace`/`deploy_argo` per tenant) but the appsets and root
  app assume the infra instance — untested, undocumented.
- **Action:** document/design the shard-out path before the shared instance
  saturates.
- **Size:** L.

### P3 — Workload backup
- **What:** no Velero (or similar) in any app stack — clusters are cattle but
  their PVs aren't.
- **Action:** add a backup stack tenants can opt into.
- **Size:** M.

### P3 — `infrastructure/clusters/infra-1/vars/`
- **What:** `kustomization.yaml` is committed but its `tenant-vars.yaml` is not
  (regenerated by `make apply-infra`). Harmless but untidy; the Apply workflow's
  `git add -A` will commit it on the next tenants.yaml change.
- **Size:** S.

### P3 — Add a `prod` profile when the first prod cluster lands
- **What:** Only `profiles/dev` (infra + apps) exists; `infra-1` is
  `environment: prod` with no cluster dir yet.
- **Action:** Copy the dev profiles + `envs/dev*` components to prod with prod
  values/versions (this is now also the mechanism for staged version rollouts).
  Consider a shared "common" profile to avoid duplicating the component list.
- **Size:** S.

### P3 — Parameterize TLS verification
- **What:** `allow_unverified_ssl = true` / `insecure = true` hardcoded — lab
  defaults, not prod.
- **Size:** S.

### P3 — Document the `vars/` directory reservation
- **What:** `infrastructure/clusters/{project}/vars/` is a sibling of the
  `{namespace_ref}` dirs; a namespace literally named `vars` would collide.
- **Size:** XS.

## Done
<!-- Move completed items here with the PR/commit that closed them. -->
- **Version decoupling** (branch `claude/terraform-kustomize-review-1bbie5`):
  bases carry `replace-me` placeholders; always-on versions (cluster class,
  k8s, AKO) pinned in `infrastructure/components/envs/{env}`; optional-feature
  versions in feature-scoped env sub-components (`envs/{env}/istio`);
  standard-stack versions in
  `apps/components/envs/{env}` via the apps profile; per-cluster canary via the
  cluster `patches:` block. Rendered output verified byte-identical.
- **Remote Terraform state backend** — kubernetes backend in the dedicated
  state supervisor namespace (PR #3–#5).
- **Second-review fixes** (branch `claude/terraform-kustomize-review-1bbie5`):
  CI-safe `terraform apply` (TF_APPLY_FLAGS); tenant AppProject lockdown
  (deny in-cluster/supervisor destinations, Namespace-only cluster grant,
  optional `source_repos`); bootstrap self-minted tokens (no kubeconfigs
  shuttle / refresh hack); repo URL single-sourced from `argocd/repo-config.yaml`;
  real preconditions (argo_namespace resolution, key-collision check); defaults
  consolidated into the tenant module; `vpc_name` from module output +
  `nsxt_t1_path` rendered whole; reusable `istio-ako-patch` via apps-side
  injector; validate.sh: replace-me grep, cluster-name uniqueness, apps vars
  check, template build-test; terraform fmt/validate CI job; `apply.yml` wider
  triggers + staged deletions; root app autoSync; env-specific os-image values
  moved to `envs/dev`; provider pins; dead code removed; `.yml`→`.yaml`.
- Environment profile layer for kustomize inheritance (PR for branch
  `claude/infra-refactor-review-hne0g6`).
- Terraform→ArgoCD suffixed-name handoff via `namespace_config`; bcrypt
  double-hash fix; `infra` AppProject rendering; exact `cluster-apps` join; istio
  addon-only; dead-code removal; `validate.yml`.
