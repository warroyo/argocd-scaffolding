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
that must hold: `(project, namespace_ref)` must be unique, and each
`cluster-details.yaml` must match its directory path. Both are actively checked
— by Terraform preconditions and by `scripts/validate.sh` on every PR. Cluster
names need only be unique within a `(project, namespace_ref)` (the directory
layout guarantees it); the appset Application names are path-scoped
(`{project}-{namespace_ref}-{cluster}`), so bare names may repeat across
tenants/namespaces.

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
`components/envs/{env}` (inherited through the profile), shared add-on versions
in small feature-scoped components (`envs/{env}/istio`, `envs/{env}/headlamp`)
that a namespace's `namespace-resources` kustomization includes alongside the
add-on base (see decision 9). A
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

---

## 9. Why are add-ons installed with shared label-gated AddonInstalls?

**The problem.** VKS add-ons were wired three different ways: istio as a
per-cluster `AddonInstall` whose selector the injector rewrote to one exact
cluster name, headlamp as a shared label-selected `AddonInstall`, and ako/antrea
as bare `AddonConfig`s with inconsistent label keys. Every new add-on had to
pick a style, and the per-cluster istio install duplicated an object the CRD
model already fans out for free.

**The choice.** One pattern, two variants, following the VKS addon CRD model:

- **Installable add-on** (istio, headlamp): ONE shared `AddonInstall` per
  supervisor namespace (`infrastructure/base/{addon}`, delivered by the
  `namespace-resources` ApplicationSet), selecting clusters on
  `addons.kubernetes.vmware.com/{addon}: enabled` with
  `stopMatchingBehavior: Delete`. Enablement is a Cluster label (default-on
  add-ons set it in `envs/{env}` with a `disable-{addon}` opt-out; opt-in
  add-ons get a `components/{addon}` label component). The version is pinned in
  exactly one place: `releaseFilter.ref.name` (an `AddonRelease` name — the
  API has no `AddonInstall.spec.version` field; a value set there is pruned and
  the addon silently floats), via `components/envs/{env}/{addon}`.
- **Auto-installed core add-on** (ako, antrea): the platform installs it, so
  there is no `AddonInstall` to author — only a per-cluster `AddonConfig`.
  (Antrea isn't even label-gated: it's the cluster's CNI, selected in the
  Cluster spec via `bootstrapAddons.cniRef` — the AddonConfig only tunes its
  settings.)

`AddonConfig` is always per-cluster overrides ONLY, and opt-in
(`components/istio-config`): the addon controller auto-generates an
`AddonConfig` named `{cluster}-{addon}` (its default `addonConfigNameTemplate`)
for clusters without one, filling `addonConfigDefinitionRef` and `clusterName`
itself — which is why authored configs omit both fields. Every addon resource
carries `app.kubernetes.io/name: {addon}` and all patches target by
`labelSelector`, never by exact name.

**The trade-off.** Enabling an add-on for a cluster is one label component;
uninstalling is removing it (`Delete` handles cleanup). The costs: an add-on's
version rolls per namespace-environment, not per cluster (canary = a `patches:`
override in one namespace-resources dir), and a cluster that needs custom
values takes a second component (`{addon}-config`) — but a cluster on defaults
ships nothing at all.

See `docs/ARCHITECTURE.md` → "VKS add-on pattern" for the diagram and the
per-add-on variant table.

---

## 10. Why is custom cluster policy in Terraform, keyed on per-tenant sync impersonation?

**The problem.** Tenants manage namespaces through git, synced by a shared
ArgoCD instance — but the workload cluster's registration identity
(`argo-attach-sa`, cluster-admin) is the same for every sync, tenant and
platform alike. Nothing at the cluster API server can tell them apart, so
"self-service namespaces via git" otherwise means "tenant is cluster-admin."
VCF Automation's policy CRDs (`ClusterPolicyTemplate`, org-scoped) are also
org-admin-only — a tenant's own ArgoCD project could never author them even
if policy were pushed through GitOps.

**The choice.** Two decisions, not one:

- **Policy lives in Terraform** (`terraform/infra/policies.tf` +
  `terraform/infra/rego/`), not GitOps, because `ClusterPolicyTemplate` is an
  org singleton only an org admin can create — putting it outside any
  tenant's ArgoCD project by construction, the same reason the AppProjects
  themselves are Terraform-rendered rather than hand-authored.
- **ArgoCD sync impersonation gives each tenant its own identity**
  (`destinationServiceAccounts` on the generated AppProject → a per-tenant
  `tenant-sync-<tenant>` service account, `apps/base/tenant-sync`, named by
  `apps/components/cluster-var-injector`). Custom `ClusterPolicy` rules key on
  that identity: a Namespace-label-ownership policy plus a
  containment policy that denies that identity writing outside namespaces
  labeled as its own tenant. A single shared identity was considered and
  rejected — the tenant AppProject's `destinations` block already allows
  targeting any registered cluster by name (not just the tenant's own), so a
  shared principal would make a tenant landing on another tenant's cluster
  indistinguishable from that cluster's legitimate owner. Per-tenant naming
  turns that same gap into a sync that simply fails (no such service account
  exists there) instead of a silent cross-tenant compromise.

Enabling impersonation needs one `argocd-cm` key
(`application.sync.impersonation.enabled`) that the argocd-service operator
doesn't manage — applied as a *minimal* Server-Side-Apply patch
(`argocd/config/argocd-cm-patch.yaml`) that owns only that key, rather than
templating the operator's own CR (which exposes no such field) or replacing
the whole ConfigMap (which would fight the operator's reconcile loop).

Namespace ownership itself is **label-driven, not an exclude-list**: a
`require-namespace-labels` policy makes the tenant's own sync identity stamp
`gitops.platform/project`/`environment` on every namespace it touches (with a
no-adoption rule blocking it from relabeling a namespace that wasn't already
its own); every other policy then scopes by that label's presence or absence.
The one genuine exclude-list left is three lines in the AppProject
(`kube-system` / `gatekeeper-system` / `vmware-system-vksm`) — the exact
namespaces the Gatekeeper webhook itself is hard-configured to never see, so
no policy could cover them regardless of labeling.

**The trade-off.** Adding a policy is Terraform, not a PR against the
`argocd/` tree — consistent with the rest of the platform-admin surface, but
one more place (alongside `tenants.yaml`, the AppProject template) that
requires an infra apply rather than a plain git sync. Impersonation is a beta
ArgoCD feature (v3.0.19, shipped here); its exact behavior when the target
service account is momentarily missing (hard-fail vs. silent fallback to the
un-impersonated identity) determines how much a brand-new cluster's bootstrap
window actually matters, and is a verify-live item (see
`docs/GETTING-STARTED.md`), not something this design can assert from git
alone. The cross-cluster destination gap itself is mitigated, not closed —
closing it needs cluster names to carry a tenant prefix, a directory-layout
change out of scope here.

See `docs/ARCHITECTURE.md` → "Cluster policy + namespace self-service" for
the diagram and the full policy table.

## 11. Why doesn't `service-exposure` police LoadBalancer Services?

`service-exposure` denies `NodePort` but **allows** `LoadBalancer` — it does not
gate LBs on an approval or a controller identity. Two reasons:

- **Provider heterogeneity.** Tenants expose via their own `Gateway`, and the
  platform supports multiple Gateway API providers (a cluster registers both the
  `avi-lb`/AKO and `istio` GatewayClasses, and customers may bring their own). The
  LB Service that a tenant Gateway produces is created by the provider's
  controller — `avi-system:ako-sa` for AKO, `istiod` for istio, an unknowable SA
  for a customer's. An identity exemption list is therefore coupled to one
  provider and can never cover customer-brought ones; a `LoadBalancer`-requires-
  annotation gate is worse still, because the annotation is tenant-set and so
  self-approvable.
- **The real boundary is the IP pool, not admission.** Clusters are
  single-tenant, so an LB only ever consumes that one tenant's own cluster
  capacity. LB sprawl is bounded by the cluster's Avi Service Engine Group and VPC
  IP pool (`seg_name`, `vpc_private_cidr`) — a quota the platform already owns —
  rather than by a Gatekeeper rule that would have to know every provider.

`NodePort` stays denied (it bypasses the LB/IPAM path entirely and pins host
ports), steering tenants to a Gateway-backed LoadBalancer.

## 12. Why do the `default` and `infra` AppProjects need `destinationServiceAccounts` too?

Enabling `application.sync.impersonation.enabled` (#10) doesn't only gate
tenant syncs — once it's on, ArgoCD requires a `destinationServiceAccounts`
match on **every** sync in **every** project, platform ones included. A
project with none defined doesn't silently fall back to the un-impersonated
controller identity; it hard-fails with "no matching service account found."
This broke `root-bootstrap` (project `default`, self-managing the `argocd/`
tree) and the platform ApplicationSets (project `infra`: `cluster-provisioning`,
`namespace-resources`) the moment the flag went live — confirmed by forcing a
fresh sync on each and watching them fail identically, not inferred.

The fix for both is the same identity — `argo-attach-sa`, each destination's
own pre-existing cluster-admin registration SA — restoring exactly the
pre-impersonation behavior, not granting anything new. But the **value shape
differs** by how each project's syncs fan out:

- `default` (`root-bootstrap`) only ever targets its own home supervisor
  namespace, so a namespace-qualified value would work — but so does the bare
  form, and using the same bare form as `infra` keeps both consistent.
- `infra`'s ApplicationSets fan out across **every tenant's own supervisor
  namespace** (`namespace-resources` for tenant-1 targets `dev-1-hvvz2`, not
  the platform's own `infra-84jfn`). A namespace-qualified value here
  (`infra-84jfn:argo-attach-sa`) fails with a *different* error: the real
  caller (e.g. `dev-1-hvvz2:argo-attach-sa`) has no RBAC to impersonate
  anything in a namespace that isn't its own.

The bare account name (`argo-attach-sa`, no namespace prefix) resolves relative
to each sync's own destination namespace — one entry covers every tenant's
supervisor namespace without enumerating them. Both entries also match
`server: ''` alongside `server: '*'`: a project's own self-referential
destination (ArgoCD managing its own namespace, as `root-bootstrap` does)
resolves to an empty destination-server value in the impersonation lookup, and
the `'*'` glob alone did not match it in practice.

`default` is patched via SSA (`argocd/config/argocd-appproject-default-patch.yaml`,
same pattern as `argocd-cm-patch.yaml` — it's ArgoCD's built-in project, not one
we render). `infra` is set directly in `terraform/infra/templates/appproject.yaml.tftpl`
(the `type == "infra"` branch), since Terraform already owns that file. The
tenant branch's `platform-gitops:tenant-sync-${name}` keeps its namespace
prefix — a tenant's Applications only ever target its own clusters, each with
a fixed, literal `platform-gitops` namespace, so the multi-destination problem
above doesn't apply there.

---

## 13. Why does `cert-manager`'s `PackageInstall` not ship its own `PackageRepository`?

**The problem.** The standard app stack used to render its own Carvel
`PackageRepository` (`apps/base/standard-repo`, image pinned per-env) so its
`PackageInstall`s (cert-manager) had a `Package` to resolve against.

**What live-cluster verification found.** Every VKS cluster already carries a
platform-owned `PackageRepository` (`vmware-system-tkg/standard-packages`,
present since cluster creation) whose `Package`s — cert-manager included, at
the exact version our env layer pinned — are visible cluster-wide via
kapp-controller's global packaging namespace, no per-namespace
`PackageRepository` required. Confirmed live: our own `tkg-system/standard-repo`
carried an ArgoCD tracking annotation and a `last-applied-configuration`
matching our `repo.yaml` byte-for-byte — it was GitOps's own object, not
something VKS provisioned, and it was re-fetching content the platform already
exposed for free.

**The choice.** Deleted `apps/base/standard-repo` and its reference from
`apps/components/stacks/standard`, and the per-env `imgpkgBundle` patch from
`apps/components/envs/{env}`. `PackageInstall`s (cert-manager, and any future
one) resolve straight from the platform's global namespace — the env layer
now only pins the `PackageInstall`'s version constraint, nothing else.

**The trade-off.** One fewer moving part, and one less thing to keep in sync
with the platform's own bundle cadence — at the cost of being bound to
whatever package versions the platform ships (no custom/private Carvel
packages without reintroducing a repository).

---

## 14. Why does the custom helm addon catalog (`AddonRepository`) live in a hand-applied manifest, not Terraform or GitOps?

**The problem.** External Secrets Operator (ESO), needed to consume the VCF
Secret Store Service, isn't in the built-in VKS addon catalog the way
istio/headlamp are — nothing in `vmware-system-vks-public` already knows how
to install it. VKS 3.7 added helm-based addons: registering a helm chart repo
as an installable addon source is a plain CR (`AddonRepository`, plus an
`AddonRepositoryInstall` to activate it), no Carvel packaging pipeline
required for a public chart repo.

**Two wrong turns before landing here.** The first attempt reasoned by
surface analogy to `ClusterPolicyTemplate` (decision #10): another
admin-sounding resource, so put it in Terraform via the same
`kubernetes.vcfa-org` provider. That's wrong — verified live, the
`addons.kubernetes.vmware.com` API isn't served in the org (vcfa) context at
all, so that provider can't even reach it, let alone create anything. The
second attempt moved it to GitOps instead, one `AddonRepository`/
`AddonRepositoryInstall` per tenant's own supervisor namespace (the same
destination `namespace-resources` already syncs `AddonInstall` into) — also
wrong, also verified live: both CRs can **only** be created in
`vmware-system-vks-public`, a genuine Supervisor-scope namespace, not any
arbitrary tenant supervisor namespace.

**The actual boundary.** `vmware-system-vks-public` sits at a privilege level
this repo's automation has never held a credential for. Every `kubernetes`
provider here comes from `vcfa_kubeconfig`, scoped either to the org (no
args) or to one tenant's supervisor namespace (`project_name` +
`supervisor_namespace_name`) — and the org-scoped context has only read
visibility into `vmware-system-vks-public`, not write. `ClusterPolicyTemplate`
being org-admin-scoped and reachable by `kubernetes.vcfa-org` said nothing
about where *this* resource lives — same "admin-sounding" shape, a
genuinely different, non-overlapping privilege boundary underneath.

**The choice.** Since no credential of that shape exists anywhere in this
repo's automation, and shouldn't be minted just for this, registration is a
hand-authored manifest (`supervisor-addons/{addon}.yaml`) applied manually
with `kubectl` by a human holding real Supervisor-admin access — never
Terraform, never ArgoCD, never CI. This is the same category of problem
`terraform/state-namespace/` already solved (a resource needing privilege no
automation here holds, so it's a one-time hand-applied CR, documented in
`docs/GETTING-STARTED.md`) — same answer, applied a second time. Once
registered, *consuming* the addon (`AddonInstall`, version pin, enablement
label) is ordinary GitOps — identical to any other add-on (CLAUDE.md "VKS
add-ons") — because that part carries no more privilege than installing
istio or headlamp already did; only the registration step sits outside both
Terraform and GitOps.

**The trade-off.** Adding a brand-new custom helm addon needs a manual,
out-of-band step (Part 1.2 of `docs/GETTING-STARTED.md`) before the usual
kustomize wiring, with no PR review and no audit trail beyond the committed
YAML and whatever the human running it remembers to do — one more kind of
step than istio/headlamp needed (they were pre-registered by VMware), and a
different kind of step than everything else in this repo, which is either
Terraform or GitOps. Worth it because the alternative is minting and storing
a Supervisor-admin credential somewhere in this repo's automation, which is a
bigger and more permanent risk than one rare manual `kubectl apply`.

**The bigger trade-off, found the hard way.** The privilege boundary above is
not the worst part. Registering the repo makes the platform auto-create a
`helm-repo` `AddonInstall` in `vmware-system-vks-public` with `clusters: []`
and `crossNamespaceSelection: Allowed` — which, per the CRD's own field docs,
means **every cluster on the Supervisor**, other tenants' included. Each one
tries to render a `HelmRepository` CR; any cluster lacking helm-controller
fails that ClusterAddon and error-loops the shared addon controller until it
gets one. Registering a custom helm repo is a **fleet-wide act, not a tenant
one**, and nothing in the API says so.

There is no way to scope it. All four verified live:
- The CRs are rejected outside `vmware-system-vks-public` — *"only allowed in
  public namespace `vmware-system-vks-public` or supervisor service
  namespace"*. A tenant-namespaced repo is not possible.
- `AddonRepositoryInstall.spec` has exactly one field, `addonRepositoryRef`.
  No cluster selector, no namespace selector.
- The generated `helm-repo` `AddonInstall` can be neither patched nor deleted,
  even by Supervisor-admin (`Forbidden` on both) — so a selector cannot be
  added after the fact, and the object outlives the `AddonRepository` that
  created it.
- The vendor's own 3.7 documentation describes no scoping mechanism.

The only mitigation is fleet-level: **every cluster must be on a 3.7+ cluster
class** (`builtin-generic-v3.7.0`), because that is what makes the platform
label the Cluster `addon.addons.kubernetes.vmware.com/helm-controller:
automatic` and install helm-controller, which supplies the `HelmRepository`
CRD and `vmware-system-helm` namespace. On a 3.6 class none of that exists.
Consequence for this repo: a custom helm add-on cannot be turned on until the
whole Supervisor fleet is on 3.7 — which is a shared-environment
coordination problem, not something a single tenant's git repo can solve.

Two API details worth recording, both undocumented and both discovered by
being rejected: the `AddonRepository` must carry an
`addons.kubernetes.vmware.com/package-offerings` annotation (JSON, mirroring
`spec.version` and `spec.addonFilters`) or the validating webhook refuses it;
and registration *does* mint an `AddonRelease` (`external-secrets.2.8.0`),
contrary to an earlier assumption here that the helm flow skips them — only
the naming convention differs from a vendor-packaged add-on.

## 15. Why are add-ons gated by a profile label instead of one label per add-on?

**The problem.** The original model gave every installable add-on its own
enablement label, and "on by default" meant an `op: add` patch in
`infrastructure/components/envs/{env}`. That makes the default add-on set a
property of the *environment layer* — so adding one default-on add-on costs
one patch per environment, and the same env layer that holds version pins also
decides membership. There is no way to say "these clusters get this set of
add-ons" without repeating the set, and no way to run two different add-on
sets inside one environment.

**The choice.** A bundle label — `addons.kubernetes.vmware.com/profile:
standard`, added once by `components/addon-bundles/{bundle}` and inherited
through `profiles/{env}` — that every add-on in the bundle selects on.
Membership moves into each add-on's own `AddonInstall`, so joining the default
set is one edit in one file regardless of how many environments exist, and
`components/envs/{env}` goes back to holding versions only.

**Why the override isn't a second selector.** `AddonInstall.spec.clusters` is
a list and its entries OR (stated in the CRD's own field docs). A profile
selector plus a per-add-on selector is therefore a union: a `disabled` label
could only ever fail to add a cluster, never remove one the profile already
matched. The override has to live inside the profile selector, where
`matchExpressions` AND together — `profile In [standard]` AND `{addon} NotIn
[disabled]`, with a second selector for `{addon} In [enabled]` so an
off-profile cluster can still opt in. `NotIn` matches objects lacking the key,
so a profile-only cluster installs. This is the vendor's own documented
opt-out idiom (the `cluster-autoscaler` example in `kubectl explain
addoninstall.spec.clusters`), not an invention.

**Two deliberate exceptions.** headlamp is dev-only, so it stays an `envs/dev`
label — an env-scoped add-on genuinely is an env-layer concern. Observability
is in the bundle but its `AddonInstall` is built-in and not ours to edit, so
the profile component sets that add-on's *native* `automated-monitoring` label
instead. General rule: profile label for add-ons we author, native label for
platform-installed ones. `ako-istio` stayed out of the bundle for a different
reason — istio being on says nothing about whether the cluster runs AKO/AVI,
and the pairing patch is wrong on a cluster without it.

**The trade-off.** At today's scale (one env, three owned add-ons) this is a
net line increase: two selectors of `matchExpressions` per add-on replace one
`matchLabels`, and there's a new component. The payoff is entirely forward —
it arrives with the second environment (no duplicated default-on patches) and
with the fourth add-on (membership edited in one file). The standing cost is
that the selector block is subtle enough to copy wrong; hence the recipe in
CLAUDE.md rather than leaving future authors to re-derive the OR/AND
semantics. A cluster that skips the profile component now also gets no
observability, where before the base Cluster carried that label —
`enable-observability` is the escape hatch.
