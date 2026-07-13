# Design decisions

The *why* behind the big choices in this repo. Each decision answers three
questions: **what problem came up, what we chose, and what it costs**. The big
picture — how the pieces fit together — lives in
[ARCHITECTURE.md](ARCHITECTURE.md).

---

## 1. Why does Terraform run twice?

**The problem.** Installing ArgoCD into each supervisor namespace needs a Helm
connection *per namespace* — but those namespaces (and the credentials to reach
them) don't exist until the provisioning apply finishes. Terraform also can't
create provider connections in a loop: each one has to be written out as its
own block.

**The choice.** Split Terraform into two runs. `terraform/infra` provisions the
namespaces. It also *writes out* the second run's connection blocks
(`terraform/bootstrap/providers.tf` and `main.tf` — one Helm provider and one
module per namespace) and exports a `namespace_config` output carrying the
generated namespace names and labels. `terraform/bootstrap` then installs
ArgoCD using that wiring.

**The trade-off.** `make apply` is a two-step pipeline with a git commit in the
middle (enforced — `apply-bootstrap` refuses to run while generated files are
uncommitted). In return, the generated files contain no values, only wiring —
they change only when a namespace is added or removed, so their diffs stay
small and reviewable. The one-run alternative simply doesn't work in Terraform.

---

## 2. Why do ApplicationSets join on labels instead of reading names from git?

**The problem.** VCF Automation generates supervisor-namespace names at apply
time: ask for `dev-1`, get `dev-1-abcde`. GitOps wants deployment targets
declared in git ahead of time — but git can never know that generated name.
Writing the names back into git after every apply would work, but it couples
every apply to a bot commit and turns the repo into a mirror of runtime state.

**The choice.** Git only ever declares *logical* names — the directory path
`infrastructure/clusters/{project}/{namespace_ref}/{cluster}`. At install time,
the bootstrap chart reads the real (suffixed) namespace name it was installed
into and stamps it, along with the project and namespace-ref, as **labels on
the ArgoCD cluster registration**. The ApplicationSets build their git search
paths *from those label values*, so each registration finds exactly its own
directories, and the deployment target comes from the label — never from git.

**The trade-off.** The generated name flows from VCF → chart → label →
ApplicationSet without ever touching git. The cost is that the join has rules
that must hold: `(project, namespace_ref)` must be unique, cluster names must
be unique everywhere, and each `cluster-details.yaml` must match its directory
path. All three are actively checked — by Terraform preconditions and by
`scripts/validate.sh` on every PR.

---

## 3. Why are generated files committed to git?

**The problem.** Some values only exist after Terraform runs (the tenant's
UUID, the VPC path, the ArgoCD namespace name) — but kustomize needs them at
sync time, and ArgoCD reads git, not Terraform state.

**The choice.** The infra run renders them into the repo
(`argocd/projects/*`, `infrastructure/clusters/{tenant}/vars/tenant-vars.yaml`,
and the bootstrap wiring) and they get committed. CI commits them
automatically between the two applies; locally, `make apply-bootstrap` refuses
to run until you commit them.

**The trade-off.** Terraform-derived values become reviewable in PRs and
visible to ArgoCD. The cost: a class of files that live in git but must never
be edited by hand. Each one carries a "do not edit" header, and CLAUDE.md
keeps the full list.

---

## 4. Why plain kustomize instead of Helm for cluster definitions?

**The problem.** Cluster definitions need inheritance (fleet-wide defaults),
per-environment values, optional features, and per-cluster overrides.
Templating engines make that easy to *write* — and hard to *audit*, because
what actually gets deployed depends on values resolved at deploy time.

**The choice.** Everything is plain kustomize: profiles (the default set per
environment), components (optional features), env overlays (real values and
version pins), and a replacements-based injector for cluster identity. Nothing
is templated at sync time.

**The trade-off.** `kustomize build <cluster-dir>` reproduces byte-for-byte
what ArgoCD deploys — reviewable, diffable, and testable in CI with no cluster
access. The costs: kustomize won't let one directory read a *file* from
another, so the apps tree carries its own small injector and a duplicated
cluster name (cross-checked by validation), and patch-based composition is
wordier than template variables.

---

## 5. Why is Terraform state stored in Kubernetes?

**The problem.** CI runs on throwaway machines, so Terraform state has to live
somewhere shared — and requiring an S3 bucket or an Azure storage account
would bolt a second cloud onto a VCF reference architecture.

**The choice.** State is stored as Kubernetes Secrets in a small, dedicated
supervisor namespace created once, by hand (`terraform/state-namespace/`). A
stateless helper (`terraform/state-backend/`) fetches a fresh, namespace-scoped
kubeconfig on every run and writes the two gitignored files the backend reads.

**The trade-off.** No external dependencies; any machine or CI runner with VCF
credentials can run the pipeline. The costs: the state lives on the same
platform it manages (back it up off-platform — see the backlog), and backend
init must use `-reconfigure` so an expired cached token is never reused.

---

## 6. Why does the bootstrap phase mint its own tokens?

**The problem.** VCF kubeconfig tokens are short-lived. Originally, the infra
run captured them in its state and the Makefile shuttled them to bootstrap —
so a standalone bootstrap run would authenticate with whatever (possibly
long-expired) token the last infra apply had captured.

**The choice.** The bootstrap run requests its own fresh token for each
namespace at plan/apply time (`terraform/bootstrap/vcfa.tf`), using the
namespace names from `namespace_config`.

**The trade-off.** No secrets pass between the two Terraform runs, no
refresh-the-state workaround, and teardown ordering stays natural (bootstrap
can always reach namespaces that still exist). The only cost: bootstrap needs
the same VCF credentials as infra.

---

## 7. Why are no versions pinned in the kustomize bases?

**The problem.** A version pinned in a shared base rolls out to every cluster
in every environment the moment it merges — and self-healing sync enforces it.
That makes staged rollouts (dev first, then prod) and single-cluster canaries
impossible without forking the base.

**The choice.** Bases carry `replace-me` placeholders instead of versions.
Real pins live in the environment layer: always-on versions in
`components/envs/{env}` (inherited through the profile), optional-feature
versions in small feature-scoped components (`envs/{env}/istio`) that a cluster
includes alongside the feature. A
single cluster can canary ahead via a `patches:` block. Validation rejects any
rendered output that still contains `replace-me`.

**The trade-off.** A version bump is a one-line PR against one environment,
and promotion is "let dev soak, then update prod". The cost: turning on an
optional feature takes two lines (the feature plus its env component) instead
of one — but forgetting the second line fails validation instead of silently
deploying a placeholder.

---

## 8. Why one repo for everything?

**The problem.** The label join, the committed generated files, and the
validation checks all need one consistent view of the Terraform config, the
ArgoCD config, and the cluster directories. Splitting them across repos means
cross-repo ordering problems and no single place to enforce the rules.

**The choice.** One repo holds the platform (Terraform + ArgoCD config) and
the cluster definitions. Tenant *application* repos stay separate — tenants
deploy into their own ArgoCD project from their own repos (see
`docs/examples/sample-tenant-repo/`).

**The trade-off.** One `validate.sh` covers every invariant in one place, and
the ApplicationSets need a single repo URL (`argocd/repo-config.yaml`). The
cost: platform config and tenant-visible cluster config share one history, so
the write boundary between platform team and tenants has to come from code
ownership rules and branch protection (see the backlog), not from repo
boundaries.
