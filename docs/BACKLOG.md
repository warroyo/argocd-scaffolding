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
  dir-deletion still deprovisions. The rename trap remains armed. The
  root-app-prunes-AppProject race is defused *in the `make destroy-apps` path*:
  it quiesces the root app (drops automated `syncPolicy`, strips its finalizer)
  before deleting the appsets/apps, so AppProjects stay alive until the workload
  Applications finish finalizing. The general tenant-removal ordering (terraform
  destroying the namespace while clusters run) is still undefined.
- **Observed 2026-07-29 (the `dev2-cluster` wedge):** deletion also fails *open*
  in the other direction — an Application can hang in deletion indefinitely. The
  `dev2-cluster` directory was removed from git on 2026-07-15; the appset deleted
  its Application, but the `resources-finalizer` could not prune the `ArgoCluster`,
  whose own `field.vmware.com/argo-attach-cluster-cleanup` finalizer was trying to
  delete a secret in `infra-9lg5w` — a supervisor namespace that no longer existed
  (the infra namespace had been rebuilt as `infra-84jfn`). Permanent forbidden, so
  the object sat with a `deletionTimestamp` for **two weeks** unnoticed. Cleared by
  removing the dead finalizer by hand. Teardown ordering therefore has to cover
  rebuilding the *infra* namespace too, not just tenant namespaces — any
  ArgoCluster outliving its argo namespace is unfinalizable.
- **Size:** S.

### P1 — Rotate and externalize credentials
- **What:** `infrastructure/base/ako/ako.yaml` commits a real AVI
  username/password/CA (base64) and ships it to every cluster as
  `cluster-avi-secret`. This workload-side secret should move to
  Terraform/external-secrets instead of git.
- **Action:** Rotate the leaked credentials (they are in git history), then wire the
  workload secret through Terraform/external-secrets instead of git.
- **Owner note:** Intentionally left untouched on request.
- **Now unblocked:** the secret-store wiring (see Done) gives a working
  `ClusterSecretStore` — the AVI secret can move to a `KeyValueSecret` +
  `ExternalSecret`. Still out of scope until the creds are rotated.
- **Size:** M.

### P1 — ArgoCD human access (SSO + per-tenant RBAC)
- **What:** the only credential is a single shared admin password (TF var). The
  AppProject lockdown only matters once tenants authenticate as themselves —
  today it's either admin-for-everyone or ticket-driven.
- **Scope note:** this is the **ArgoCD UI/API** only. Human access on the
  *workload clusters* (Headlamp + kubectl, VCFA identity, per-namespace
  RoleBindings, policy-fenced) is done — see Done. A tenant still cannot create
  its own `Application` object without the platform applying it.
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
- **Sharpened 2026-07-29 — two real misses, both invisible for weeks:** (a) the
  `dev2-cluster` Application sat stuck-deleting for two weeks (see the deletion
  item); (b) `cluster-apps` reported **`Synced`** while its `AddonInstall` did not
  match git at all — ArgoCD's server-side diff dry-run was being rejected by a
  validating webhook, and a failed *comparison* leaves the previous status in
  place rather than surfacing `OutOfSync`. Only a hard refresh exposed the
  `ComparisonError`. So the check must not just diff git-dirs vs Applications: it
  needs to alert on `status.conditions[].type == ComparisonError`, on any
  non-empty `metadata.deletionTimestamp` older than ~1h, and on
  `operationState.phase == Failed` — none of which show up in the sync/health
  columns everyone actually looks at.
- **Size:** M.

### P1 — No cluster is attached to VKSM, so no policy is actually enforced
- **What:** every `ClusterPolicy` this repo manages is configured and projected
  correctly, and **none of them run**. The three containment policies read
  `enforcementAction: deny` at the org API, and the platform even projects each
  one down per cluster (`prj:<name>:cluster:dev1-cluster:supervisor-namespace:dev-1-y8qw4`,
  `inherited: true`) — but the guest has no engine to evaluate them: no
  `constraints.gatekeeper.sh` CRDs, no `policy.management.kubernetes.vmware.com`
  CRDs, no ValidatingAdmissionPolicies, no webhook, and `vmware-system-vksm`
  holds nothing but istio CA configmaps.
- **Where it stops (2026-08-25):** the VKSM-managed cluster object
  (`clusters.core.management.kubernetes.vmware.com`) sits at
  **`phase: ReadyToAttach`, `state: Unknown`** — for *all three* clusters in the
  install, across two projects, created 25 days apart. Attachment would create
  an `installers.tmc.cloud.vmware.com` `AgentInstall` on the Supervisor for the
  `tmc-agent-installer` CronJob (`svc-tmc-c9`, runs every minute) to act on;
  **zero `AgentInstall` objects exist**, so the job logs `no processing
  required` each run and the guest agents are never installed. Nothing here is
  cluster-specific and nothing in this repo can drive it: the managed Cluster's
  `spec` carries only a `selector`, attach is entirely controller-driven, and
  `ClusterPolicyInsights` is empty everywhere (no cluster has ever reported).
- **Why it matters:** the tenant containment story assumes admission is real.
  Today `tenant-sync-<tenant>`'s cluster-wide `admin` is **unfenced** —
  verified by impersonating it: a RoleBinding to `Group tenant-1-users` and one
  to a `kube-system` ServiceAccount were both accepted in a tenant namespace,
  which `rolebinding-subject-containment` at `deny` should reject outright.
- **Action:** platform/vendor side. Check whether policy management needs
  enabling per org/project in the VCFA UI, whether `svc-tmc-c9` is fully
  deployed (it holds only the installer CronJob, a SA, and a TLS configmap —
  no controller), and the appliance-side VKSM logs, which are not reachable
  through any kubeconfig here.
- **Until then:** treat every policy in `tenants.yaml` as documentation, not a
  boundary, regardless of its `enforcement:` value — and re-run the
  impersonation checks above before claiming the fence works.
- **Size:** unknown (not a repo change).

### P1 — Removed fields need a forced sync; `Synced` doesn't mean applied
- **What:** delete a component that patched a field into an existing object and
  the rendered manifest loses the field, but ArgoCD's diff compares live as a
  superset of desired — so the Application stays **`Synced`**, `selfHeal` never
  fires, and the live object keeps the field indefinitely. Verified 2026-08-25:
  `dev1-cluster` still carried `apiServerConfiguration.extraAuthentication` days
  after the `oidc-auth` revert; a **manual sync removed it in one pass**. So the
  apply path is correct and only the comparison is blind. See
  `docs/DECISIONS.md` #23.
- **Why it matters beyond this one field:** every `op: add` component in the
  repo has the same property — dropping one is not self-cleaning, and nothing in
  the UI says so. It is also why `disable-{addon}` components write the label as
  `disabled` instead of deleting it: writing a neutral value is a change the
  diff *can* see.
- **Action:** decide the mechanism — `syncOptions: ServerSideApply=true` on the
  appsets (ArgoCD's field manager then relinquishes removed fields and the diff
  is managed-fields-aware), or a repo rule that every additive component ships a
  paired opt-out writing the neutral value, plus an audit of existing components
  against it. SSA is the smaller diff but touches every synced object — canary
  one cluster first.
- **Interim:** after removing any field-adding component, sync the Application
  by hand and check the live object.
- **Size:** M.

### P1 — Headlamp bearer login parked (extraAuthentication kills anonymous auth → Concierge)
- **What:** the guest apiserver's structured `AuthenticationConfiguration`
  (`apiServerConfiguration.extraAuthentication`, shipped as
  `components/oidc-auth`) makes the cluster accept VCFA bearers — and as VKS
  applies it, it also **removes anonymous authentication**. Pinniped Concierge
  needs anonymous auth, so enabling the dashboard path **breaks the vcf CLI
  path** every cluster depends on. Not a trade: it's a regression.
- **Where:** branch `wip/headlamp-oidc-auth` (cut from `main` at `cc6fa73`), and
  the removal commit on `main` is its inverse. Parked pieces:
  `infrastructure/components/oidc-auth/`, `terraform/infra/oidc.tf` +
  `templates/oidc-auth.yaml.tftpl` + the `local_file.oidc_auth` block in
  `generate.tf`, `var.vcfa_oidc_audience`, the `hashicorp/tls` provider, the
  `validate.sh` claim-parity check and single-replica-CP warning, and the
  per-cluster opt-in lines.
- **Blocker:** a **VKS release** that keeps anonymous auth (or otherwise keeps
  Concierge working) when `extraAuthentication` is set. Nothing to do in this
  repo until then.
- **Reverting git was not enough (2026-08-25):** the live `Cluster` kept
  `extraAuthentication` until the Application was synced **by hand** — the diff
  never flagged it (see the forced-sync item above). Any cluster that enabled
  `oidc-auth` needs an explicit sync to shed the field, which rolls its control
  plane once.
- **Does not block tenant access:** the group binding resolves on the vcf CLI /
  Concierge path today (verified 2026-08-25) — only the *browser* login waits on
  this.
- **Still on `main`:** `components/headlamp-config` (UI via Gateway),
  `scripts/headlamp-token.sh` (prints the VCFA bearer — `auth whoami` only), and
  the Concierge `JWTAuthenticator` claim expressions in
  `infrastructure/base/argocd-attach-rbac/config`, which are the identity
  contract the parked config must match byte-for-byte on re-land.
- **Re-land checklist:** confirm anonymous auth survives on the new VKS build →
  merge the branch → restore the parity check → re-verify `auth whoami` on both
  paths (CLI cert AND pasted bearer) → then, and only then, bind bearer-carried
  subjects (`claims.groups + claims.roles`) in RBAC.
- **Size:** S to re-land, once unblocked.

### P3 — Per-org OIDC bundle when multi-org lands
- **What:** `components/oidc-auth` is TF-generated and **org-global** (one flat
  bundle for the single org this infra run targets). Multi-org re-keys it **per
  org**. **Depends on the parked bearer path above** — nothing to do while the
  bundle lives on `wip/headlamp-oidc-auth`.
- **Multi-org is a separate TF run per org.** The vcfa provider is **one org
  per state**, so a second org is a second infra run (its own state) rendering
  its own slice into this shared repo. At that point the OIDC bundle becomes
  `components/oidc-auth/{org}/` (mirrors the existing per-project
  AppProject/tenant-vars generation), and a cluster resolves its bundle via its
  tenant→org. This is part of the larger "partition every generated file by org
  so separate runs don't clobber" work — do it holistically with that, not as an
  OIDC-only change.
- **Scope key is org, never env** (`docs/DECISIONS.md` #21). The cheap seam is
  already kept: nothing is env-keyed today.
- **Size:** L (rides the multi-org repo partition).

### P2 — Sync identity can still *read* outside its namespaces
- **What:** `tenant-sync-<tenant>` holds the built-in `admin` bound
  cluster-wide (it must — the namespaces it writes into don't exist until it
  creates them). `gitops-namespace-containment` at `deny` now blocks its
  *writes* everywhere but its own labeled namespaces, including `Pod` and
  `ReplicaSet`. Reads are invisible to admission, so the SA can still list
  Secrets/ConfigMaps in `kube-system`, `default`, and platform namespaces.
  Practical impact depends on what those namespaces hold (modern k8s doesn't
  auto-create SA token Secrets), but it is a real residual.
- **Action:** replace the cluster-wide `admin` binding with a narrow
  cluster-wide role (namespaces + roles/rolebindings + `bind` on an allow-list
  of ClusterRoles) and have the sync SA self-grant `admin` **inside** each
  namespace it creates, fenced by the same containment policy. Escalation
  prevention then caps it at the allow-listed roles, and nothing outside its
  namespaces is readable.
- **Blocker:** needs a live soak — the self-grant is a chicken-and-egg on the
  first sync of a brand-new namespace, and ArgoCD sync-wave ordering has to put
  the RoleBinding before the workloads. See `docs/DECISIONS.md` #22.
- **Size:** M.

### P2 — Git boundary for tenants (CODEOWNERS / branch protection)
- **What:** tenants PR into `infrastructure/clusters/{their-project}/`, but
  nothing stops a tenant PR from editing profiles, appsets, terraform, or
  another tenant's directory. validate.sh checks correctness, not authorization.
- **Action:** CODEOWNERS mapping `infrastructure/clusters/{project}/` to tenant
  teams and everything else to the platform team; branch protection requiring
  owner review.
- **Size:** S.

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

### P3 — Revisit `ns_ref` vs. Terraform-owned suffixed directories
- **What:** the directory/join spine uses a logical `namespace_ref` (`dev-1`);
  the vcfa-suffixed name (`dev-1-abcde`) is carried as a sync-time label and,
  now, a TF-rendered `ns-vars.yaml`. An alternative is to drop `ns_ref` and let
  Terraform scaffold `{project}/{suffixed-ns}/` directories, so the appsets join
  directly on the suffix and the `(project, ns_ref)` uniqueness invariant goes
  away.
- **Why revisit:** removes one layer of logical/physical indirection and one
  concept. Originally justified by suffix-rotation resilience — but the suffix
  is immutable-for-life and namespace deletion is all-or-nothing (every cluster
  in it dies with it), so that resilience argument does **not** hold. The real
  trade-off is ergonomics/coupling, not durability. See `docs/DECISIONS.md`
  (namespace handles) for the analysis and why we kept `ns_ref` for now.
- **Trade-offs:** current (A) = human-readable paths, human-owned dir layout,
  CI-validatable, no TF ownership of structure. Option B = simpler join, suffix
  correct-by-construction, but Terraform owns the namespace directory (extends
  the existing generated-files coupling to dir structure). Option C (human types
  the suffixed dir) is worst — hand-copied opaque suffix, and CI can't validate
  it (the registration is runtime).
- **Blocker/scope:** rewrites the join in all three appsets
  (`cluster-provision`, `cluster-apps`, `namespace-resources`), `validate.sh`,
  and the directory contract in the docs. Orthogonal to any feature.
- **Size:** M.

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

### P3 — Add a `prod` profile when the first prod cluster lands
- **What:** Only `profiles/dev` (infra + apps) exists; `infra-1` is
  `environment: prod` with no cluster dir yet.
- **Action:** Add `profiles/prod` (infra + apps) and `components/envs/prod` with
  prod values/versions (this is now also the mechanism for staged version
  rollouts).
- **Note:** the shared-`common`-profile prerequisite is done — `profiles/common`
  holds the whole component list, so each env profile is a two-line file
  referencing it plus its `envs/{env}` overlay. Adding prod is now genuinely small.
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
- **Tenant RBAC story: human access + rolebinding containment** — closes the
  parked `wip/rolebinding-subject-containment-policy` branch (rego rewritten,
  branch can be deleted). Tenants are **read-only** on their clusters: one
  hand-authored `ClusterRoleBinding` in `apps/base/tenant-users`, identical for
  every tenant, binds the tenant's own VCFA/IdP group to the built-in `view`;
  only the subject is generated, as a `tenant_group` key in the existing
  `tenant-vars` ConfigMap that `cluster-var-injector` fills. Verified
  live that a workload cluster trusts two issuers with different subjects — a
  VCFA bearer carries `claims.groups + claims.roles` and never the supervisor's
  derived `view-…`/`edit-…` SSO groups — so an earlier design that bound the
  derived group was dead on both paths; the `project_id` derivation and
  `var.vcfa_project_group_domain` are gone with it. `apps/base/tenant-users`
  also ships `tenant-user-extras` (aggregated into `admin`/`edit`) and
  `tenant-user-extras-view` (into `view`, incl. CRD read Headlamp needs),
  replacing `tenant-sync`'s own copies of those roles.
  `rolebinding-subject-containment` restricts the gitops path to same-namespace
  ServiceAccounts; `Pod`/`ReplicaSet` added to `gitops-namespace-containment`
  targets to close the bare-Pod-in-a-platform-namespace laundering path; the
  three containment policies promoted from `dryrun` to **`deny`**. Docs:
  ARCHITECTURE "Tenant human access", DECISIONS #22. **Verified live 2026-08-25**
  on the vcf CLI / Concierge path: tenant user resolves to
  `[tenant-1-users Organization User system:authenticated]`, reads pods/CRDs/
  Gateways/ExternalSecrets cluster-wide, denied Secrets, denied every write. The
  parked bearer path is needed only for the Headlamp browser login.
- **OIDC bundle generated by Terraform (issuer + CA derived, audience a var)** —
  `components/oidc-auth/kustomization.yaml` is now rendered by the infra run
  (`terraform/infra/oidc.tf` + `templates/oidc-auth.yaml.tftpl`, `local_file` in
  `generate.tf`). `issuer` = `${var.vcfa_url}/oidc`; `certificateAuthority` is
  pulled live from the VCFA TLS endpoint via a `hashicorp/tls`
  `tls_certificate` data source (so a CA roll is just `make apply-infra`); only
  `audiences` is hand-supplied (`var.vcfa_oidc_audience` — a registered client
  id, not derivable). Killed the earlier `openssl`/PEM hand-paste. First the
  bundle was collapsed from a per-env component (`envs/{env}/oidc-auth`) to one
  org-global component, then generated. `claimMappings` stay static in the
  template and byte-identical to the Concierge `JWTAuthenticator` (validate.sh
  parity). **Backed out of `main` 2026-08-25** — the apiserver config it renders
  breaks Concierge (see the P1 park item in Open); the work is intact on
  `wip/headlamp-oidc-auth`. Remaining: per-org re-key (see Open, rides multi-org).
- **Headlamp istio-sidecar injection on `ako-istio` clusters** — shipped
  `apps/base/headlamp-istio-patch` (commit `1d2d704`). Injects a ytt overlay into
  the addon's own guest `PackageInstall`
  (`ext.packaging.carvel.dev/ytt-paths-from-secret-name`, same mechanism as
  `apps/base/istio-ako-patch`), so kapp keeps the change instead of stripping it.
  Two load-bearing stanzas: label `Namespace/headlamp` `istio-injection=enabled`
  (makes the injection webhook eligible) **and** add `sidecar.istio.io/inject:
  "true"` to the headlamp Deployment pod template (forces the one rollout that
  realizes it — a namespace label alone never rolls an existing pod). Verified
  the addon framework offers no overlay/label passthrough at any CRD level
  (AddonInstall/AddonConfig/AddonRelease/ClusterAddon + the ACD schema), and the
  `createNamespace: false` alternative was rejected for the ArgoCD/kapp ns
  ordering race. Wired to `dev1-cluster`; opt-in line in the cluster-template
  example. Verified live: pod rolled with `istio-proxy` native sidecar, in mesh.
- **Cluster policy APIs under gitops (via Terraform)** — modelled in
  `terraform/infra/policies.tf` as `local.policy_catalog` (one entry per policy
  kind) over `terraform/infra/rego/*.rego`, enabled per tenant from a `policies:`
  block in `tenants.yaml`, on the vendored `cluster-policy` /
  `cluster-policy-template` modules. Four policies ship
  (`gitops-namespace-containment`, `hostname-ownership`,
  `require-namespace-labels`, `service-exposure`). Gating identity is the
  per-tenant ArgoCD sync-impersonation SA (`tenant-sync-<tenant>`). Recipe:
  CLAUDE.md "Adding a policy"; design: ARCHITECTURE "Cluster policy + namespace
  self-service"; rationale: DECISIONS #10–#11.
- **Addon-addition workflow documented** — CLAUDE.md "VKS add-ons: one pattern,
  two variants" (Variant A/B, the add-on-config required-vs-optional test, the
  bundle selector block and its three rules, and the full new-add-on checklist)
  plus "Adding a custom helm addon" for chart repos outside the VKS catalog;
  ARCHITECTURE "VKS add-on pattern" carries the diagram; README the summary.
  DECISIONS #9, #14, #15, #16, #18 hold the rationale.
- **Headlamp addon** — shipped as a Variant A installable add-on
  (`infrastructure/base/headlamp/install` + `components/envs/dev/headlamp`
  version pin, wired through each namespace's `namespace-resources/`).
  Deliberately **not** in the `standard` bundle: it is dev-only, enabled by an
  `op: add` label in `components/envs/dev`, with a `disable-headlamp` opt-out.
- **Commit `.terraform.lock.hcl` files** — all three roots (`infra`,
  `bootstrap`, `state-backend`) have committed lock files.
- **`infrastructure/clusters/infra-1/vars/`** — `tenant-vars.yaml` is now
  committed alongside its `kustomization.yaml`.
- **Tenant secrets pattern (secret-store wiring)** — external-secrets now
  consumes the VCF Secret Store Service (OpenBao). Shipped `apps/base/secret-store`
  (SA + `system:auth-delegator` CRB + `vcf-cluster-store` `ClusterSecretStore`)
  in the standard app stack (default-on, `disable-secret-store` opt-out);
  per-namespace `ns-vars` (TF-generated suffixed namespace) feeds the injected
  mount/role; endpoint IP (infra `envs/{env}`) + CA bundle (apps `envs/{env}`)
  are env values; `tenant-sync-external-secrets` RBAC lets tenants create their
  own `ExternalSecret`s. Docs: ARCHITECTURE "Secret store", DECISIONS (namespace
  handles), GETTING-STARTED capture + smoke test. Tenant workflow examples:
  `docs/examples/keyvaluesecret.yaml`, `docs/examples/externalsecret.yaml`.
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
