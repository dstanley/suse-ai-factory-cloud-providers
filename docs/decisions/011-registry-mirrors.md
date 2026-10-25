# 011 - Registry mirrors in the image

## Status
Proposed.

## Context
Air-gapped clusters pull container images from a private registry instead of
`registry.suse.com`, `nvcr.io`, `dp.apps.rancher.io` and the other upstream
hosts. RKE2 reads `/etc/rancher/rke2/registries.yaml` for containerd mirrors
and per-registry auth and TLS. The file must exist before `rke2-server` or
`rke2-agent` first starts, and it is the same on every node.

RKE2's helm-controller installs charts from a job pod whose `helm` binary
fetches the chart URL directly. The pod mounts nothing from the host, so
`registries.yaml` does not apply to chart downloads; only image pulls go
through the mirrors.

## Decision
`registry_mirrors` and `registry_configs` (common variables) render
`registries.yaml` with `yamlencode` as Elemental's
`kubernetes/config/registries.yaml`, so the file is baked into the image like
the other node-wide settings, and both inputs feed `build_hash`. Elemental's
first-boot `k8s_conf_deploy.sh` copies that file over
`/etc/rancher/rke2/registries.yaml`, and writes an empty `{}` when it is
absent, so a copy written through `butane.yaml` is lost before RKE2 starts.
CA certificates are written to `/etc/rancher/rke2/certs/`, one
file per distinct certificate (named by content hash), so several mirror ports
behind one CA share a file.

Options considered:
- Per-node Ignition: no rebuild when a mirror changes, but the content repeats
  in every node's `user_data` (16 KiB on aws) and existing nodes would keep the
  old file (`ignore_changes = [user_data]`).
- `extra_butane_files`: already in `elemental-config`, but not exposed by the
  provider modules, and callers would hand-write YAML with credentials.

Chart repositories are out of scope here; redirecting them needs a change to
the release manifest and a way to trust a private CA in the chart job.

## Consequences
Changing a mirror, credential or CA rebuilds the image and replaces every node.
The file and any credentials are in the image and in state
([005](005-state-secrets.md)). Elemental writes it mode 0644, so credentials in
it are readable by local users; prefer a mirror that needs no pull auth from
the nodes. On aws the mirror config counts against the
build host's 16 KiB `user_data`: about 1.2 KiB with auth and a CA, which fits
the default components but not a management cluster with every add-on.
