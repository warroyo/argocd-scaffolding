terraform {
  # This helper root must NOT use the kubernetes backend it generates config for
  # (chicken-egg). It has no managed resources, so its state is trivial and
  # regenerable — local is fine and keeps it runnable on any machine.
  backend "local" {}
}
