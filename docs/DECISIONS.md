# Decision records

Lightweight ADRs for the choices that make this reference architecture what it
is. Each records the context, the decision, and what it costs. The big picture
lives in [ARCHITECTURE.md](ARCHITECTURE.md).

---

## ADR-1: Two Terraform phases, with infra rendering bootstrap's wiring

**Context.** Bootstrapping ArgoCD into each supervisor namespace needs a helm
provider *per namespace* — but the namespaces (and their credentials) don't
exist until the provisioning apply finishes, and Terraform cannot `for_each`
provider blocks.

**Decision.** Two roots: `terraform/infra` provisions, `terraform/bootstrap`
installs. The infra run *renders* bootstrap's `providers.tf`/`main.tf` (one
provider + module per namespace) via `local_file` + `templatefile`, and exports
a `namespace_config` output carrying the suffixed names and labels.

**Consequences.** `make apply` is a two-step pipeline with a commit in the
middle (enforced by `check-generated-clean`). The generated files are pure
wiring — they change only when the *set* of namespaces changes, keeping diffs
reviewable. The alternative (one root, provider config unknown at plan time)
does not work in Terraform.

---

## ADR-2: Label-join decision model instead of names in git

**Context.** vcfa suffixes supervisor-namespace names at apply time
(`dev-1` → `dev-1-abcde`), so git cannot declare deployment targets by name.
Writing generated names back into git couples every apply to a bot commit and
makes the repo a mirror of runtime state.

**Decision.** Git declares logical identity only — the directory path
`infrastructure/clusters/{project}/{namespace_ref}/{cluster}`. The
`bootstrap-tenant` chart captures the suffixed name from `.Release.Namespace`
at install time and stamps it (plus the join keys) as labels on the ArgoCD
cluster registration. ApplicationSets template their git globs *from the label
values*, making the join exact, and read `destination.namespace` from the
label.

**Consequences.** The suffixed name flows vcfa → chart → label → ApplicationSet
without touching git. Cost: the join invariants (unique `(project,
namespace_ref)`, globally-unique cluster names, path/details agreement) must be
actively enforced — Terraform preconditions and `scripts/validate.sh` do so.

---

## ADR-3: Generated files are committed

**Context.** Some Terraform-derived values *must* be readable by kustomize at
sync time (tenant UUID, VPC path, the managing ArgoCD namespace), and ArgoCD
reads git, not Terraform state.

**Decision.** The infra run renders them into git (`argocd/projects/*`,
`infrastructure/clusters/{t}/vars/tenant-vars.yaml`, bootstrap wiring) and they
are committed. `make apply-bootstrap` refuses to run while they're dirty; CI
commits them between the two applies (staging deletions too).

**Consequences.** Terraform-derived state is PR-reviewable and ArgoCD-visible.
Cost: a class of files that are in git but must never be hand-edited — marked
by header comments and a CLAUDE.md manifest.

---

## ADR-4: Plain kustomize for cluster definitions, not helm

**Context.** Cluster definitions need inheritance (fleet defaults), per-env
values, optional features, and per-cluster overrides — templating engines make
that easy to write and hard to audit.

**Decision.** Profiles (env default set) + components (features) + env overlays
(real values / version pins) + a replacements-based injector, all plain
kustomize. No sync-time templating.

**Consequences.** `kustomize build <cluster-dir>` reproduces exactly what
ArgoCD deploys — reviewable, diffable, CI-testable with no cluster access.
Costs: kustomize's load restriction forces the apps tree to carry its own tiny
injector + vars duplicate (cross-checked by validate), and patch-based
composition is more verbose than template variables.

---

## ADR-5: Kubernetes state backend in a dedicated supervisor namespace

**Context.** CI runs on ephemeral runners and needs shared Terraform state;
requiring S3/Azure/GCS would bolt a second cloud onto a VCF reference.

**Decision.** State lives as Kubernetes Secrets in a dedicated, one-time,
out-of-band supervisor namespace (`terraform/state-namespace/`). A stateless
helper root (`terraform/state-backend/`) pulls a fresh namespace-scoped
kubeconfig on every run and renders the two gitignored files the backend needs.

**Consequences.** Zero external dependencies; portable across machines and CI.
Costs: the state lives on the platform it manages (back it up off-platform —
see BACKLOG), and backend init needs `-reconfigure` so cached expired tokens
are never reused.

---

## ADR-6: Bootstrap self-mints per-namespace tokens

**Context.** vcfa kubeconfig tokens are short-lived. Capturing them in infra
state and shuttling them to bootstrap via outputs meant stale tokens and a
refresh-only pre-apply hack.

**Decision.** The bootstrap root declares its own `data "vcfa_kubeconfig"` per
namespace (names come from `namespace_config`) and configures helm providers
from it — a fresh token on every plan/apply/destroy.

**Consequences.** No secrets shuttle between roots, no refresh hack, and
destroy ordering stays natural (bootstrap destroys while the namespaces still
exist). Cost: bootstrap needs the vcfa credentials too.

---

## ADR-7: No versions in bases

**Context.** A version pinned in a shared base rolls out to every cluster in
every environment simultaneously the moment it merges — with `selfHeal`
enforcing it. That forbids staged rollouts and canaries.

**Decision.** Bases carry `replace-me` placeholders. Always-on versions pin in
`components/envs/{env}` (applied via the profile); optional-feature versions
pin in feature-scoped sub-components (`envs/{env}/istio`,
`envs/{env}/observability`) the cluster includes alongside the feature;
per-cluster canary via the cluster's `patches:` block. `validate.sh` rejects
`replace-me` in rendered output, so a missed pin fails at PR time.

**Consequences.** A version bump is a one-line PR against one environment;
promotion is dev-soak-then-prod. Cost: enabling an optional feature is two
lines (feature + env sub-component) instead of one — forgetting the second
fails validation rather than deploying a placeholder.

---

## ADR-8: One repo for the platform and cluster definitions

**Context.** The label join, the rendered-file contract, and validation all
need a consistent view of Terraform config, ArgoCD config, and cluster
directories.

**Decision.** One repo holds all three; tenant *application* repos stay
external (see `docs/examples/sample-tenant-repo/` — tenants deploy into their
AppProject from their own repos).

**Consequences.** One `validate.sh` gate covers every join invariant in one
place; ApplicationSets need a single repo URL (`argocd/repo-config.yaml`).
Cost: platform and tenant-visible cluster config share a history, so the
tenant/platform write boundary must come from CODEOWNERS/branch protection
(see BACKLOG) rather than repo boundaries.
