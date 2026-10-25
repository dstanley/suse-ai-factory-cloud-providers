# RKE2 containerd mirrors, baked into the image so a change rebuilds it.
# registries.yaml goes in Elemental's kubernetes/config/: on first boot its
# k8s_conf_deploy.sh copies that file over /etc/rancher/rke2/registries.yaml
# (an empty {} when absent), so a butane-written copy would be lost. Elemental
# writes it mode 0644; the CA files go through butane.yaml.

locals {
  # One file per distinct CA, named by content hash: mirrors sharing a CA share the file.
  registry_ca_paths = {
    for host, c in var.registry_configs : host => "/etc/rancher/rke2/certs/${substr(sha256(c.ca_pem), 0, 16)}.pem"
    if c.ca_pem != null
  }

  registry_ca_files = {
    for host, path in local.registry_ca_paths : path => var.registry_configs[host].ca_pem...
  }

  registries_yaml = yamlencode({
    mirrors = {
      for host, m in var.registry_mirrors : host => merge(
        { endpoint = m.endpoints },
        length(m.rewrite) > 0 ? { rewrite = m.rewrite } : {},
      )
    }
    configs = {
      for host, c in var.registry_configs : host => merge(
        c.username == null ? {} : { auth = { username = c.username, password = c.password } },
        c.ca_pem == null && !c.insecure_skip_verify ? {} : {
          tls = merge(
            c.ca_pem == null ? {} : { ca_file = local.registry_ca_paths[host] },
            c.insecure_skip_verify ? { insecure_skip_verify = true } : {},
          )
        },
      )
    }
  })

  # Mirror hosts are not secret: keeps the elemental_files keys non-sensitive.
  registry_config_files = length(var.registry_mirrors) + length(nonsensitive(keys(var.registry_configs))) == 0 ? {} : {
    "kubernetes/config/registries.yaml" = local.registries_yaml
  }

  registry_butane_files = [
    for path, pems in local.registry_ca_files : { path = path, mode = 420, contents = pems[0] }
  ]
}
