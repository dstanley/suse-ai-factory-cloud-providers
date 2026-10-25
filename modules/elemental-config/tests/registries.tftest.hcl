mock_provider "http" {}

override_data {
  target = data.http.aif_release_manifest
  values = {
    status_code   = 200
    response_body = file("tests/fixtures/release_manifest.yaml")
  }
}

variables {
  cluster_name        = "test"
  api_vip             = "203.0.113.10"
  api_host            = "rke2-203.0.113.10.sslip.io"
  vpc_cidr            = "10.20.0.0/16"
  rke2_token          = "TOKEN"
  user_data_max_bytes = 786432
  kernel_cmdline      = "console=ttyS0 ignition.platform.id=test"
  nodes = [
    { hostname = "test-cp-01", type = "server", init = true },
    { hostname = "test-cp-02", type = "server" },
    { hostname = "test-cp-03", type = "server", node_ip = "10.20.0.7" },
    { hostname = "test-gpu-01", type = "agent" },
  ]
  root_password_hash         = "$6$SALT$ROOT"
  node_user_password_hash    = "$6$SALT$NODE"
  ssh_authorized_keys        = ["ssh-ed25519 AAAADUMMY test"]
  appco_username             = "appco-user"
  appco_password             = "appco-pass"
  suse_registry_username     = "REGCODE"
  suse_registry_password     = "regpass"
  nvidia_api_key             = "nvkey"
  rancher_hostname           = "rancher.example.test"
  rancher_bootstrap_password = "bootstrap"
}

run "baseline" {
  command = plan
}

run "no_registries_file_by_default" {
  command = plan

  assert {
    condition     = length([for f in yamldecode(output.elemental_files["butane.yaml"]).storage.files : f if startswith(f.path, "/etc/rancher/rke2/")]) == 0
    error_message = "Without registry_mirrors or registry_configs, butane.yaml must not write anything under /etc/rancher/rke2."
  }

  assert {
    condition     = !contains(output.elemental_file_names, "kubernetes/config/registries.yaml")
    error_message = "Without registry_mirrors or registry_configs, no registries.yaml may be rendered."
  }

  assert {
    condition     = output.build_hash == run.baseline.build_hash
    error_message = "Empty registry inputs must leave build_hash unchanged."
  }
}

run "mirrors_and_configs_render" {
  command = plan

  variables {
    registry_mirrors = {
      "*"               = { endpoints = ["https://mirror.internal:5000"] }
      "registry.k8s.io" = { endpoints = ["https://mirror.internal:5000"], rewrite = { "^(.*)$" = "k8s/$1" } }
    }
    registry_configs = {
      "mirror.internal:5000" = { username = "puller", password = "p@ss: \"x\"", ca_pem = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n" }
    }
  }

  assert {
    condition     = yamldecode(output.elemental_files["kubernetes/config/registries.yaml"]).mirrors["*"].endpoint == ["https://mirror.internal:5000"]
    error_message = "registries.yaml must map \"*\" to the mirror endpoint."
  }

  assert {
    condition     = yamldecode(output.elemental_files["kubernetes/config/registries.yaml"]).mirrors["registry.k8s.io"].rewrite["^(.*)$"] == "k8s/$1"
    error_message = "registries.yaml must carry rewrite rules."
  }

  assert {
    condition = yamldecode(output.elemental_files["kubernetes/config/registries.yaml"]).configs["mirror.internal:5000"] == {
      auth = { username = "puller", password = "p@ss: \"x\"" }
      tls  = { ca_file = "/etc/rancher/rke2/certs/8010bfcee1842b2a.pem" }
    }
    error_message = "registries.yaml must carry auth (special characters intact) and the CA path."
  }

  assert {
    condition     = length([for f in yamldecode(output.elemental_files["butane.yaml"]).storage.files : f if f.path == "/etc/rancher/rke2/registries.yaml"]) == 0
    error_message = "registries.yaml must go through Elemental's kubernetes/config/: its first-boot script overwrites a butane-written copy."
  }

  assert {
    condition = startswith(one([
      for f in yamldecode(output.elemental_files["butane.yaml"]).storage.files : f.contents.inline if f.path == "/etc/rancher/rke2/certs/8010bfcee1842b2a.pem"
    ]), "-----BEGIN CERTIFICATE-----")
    error_message = "The CA PEM must be written to the path registries.yaml references."
  }

  assert {
    condition     = output.build_hash != run.baseline.build_hash
    error_message = "Registry inputs are baked into the image and must change build_hash."
  }
}

run "shared_ca_written_once" {
  command = plan

  variables {
    registry_mirrors = {
      "docker.io" = { endpoints = ["https://10.20.8.250:5001"] }
      "nvcr.io"   = { endpoints = ["https://10.20.8.250:5002"] }
    }
    registry_configs = {
      "10.20.8.250:5001" = { ca_pem = "-----BEGIN CERTIFICATE-----\nSHARED\n-----END CERTIFICATE-----\n" }
      "10.20.8.250:5002" = { ca_pem = "-----BEGIN CERTIFICATE-----\nSHARED\n-----END CERTIFICATE-----\n" }
    }
  }

  assert {
    condition     = length([for f in yamldecode(output.elemental_files["butane.yaml"]).storage.files : f if startswith(f.path, "/etc/rancher/rke2/certs/")]) == 1
    error_message = "Mirrors sharing one CA must share one CA file."
  }

  assert {
    condition = length(distinct([
      for host, c in yamldecode(output.elemental_files["kubernetes/config/registries.yaml"]).configs : c.tls.ca_file
    ])) == 1
    error_message = "Both configs must reference the same ca_file."
  }
}

run "insecure_without_ca" {
  command = plan

  variables {
    registry_mirrors = { "docker.io" = { endpoints = ["http://10.20.0.50:5000"] } }
    registry_configs = { "10.20.0.50:5000" = { insecure_skip_verify = true } }
  }

  assert {
    condition     = yamldecode(output.elemental_files["kubernetes/config/registries.yaml"]).configs["10.20.0.50:5000"] == { tls = { insecure_skip_verify = true } }
    error_message = "insecure_skip_verify alone must render a tls block without ca_file or auth."
  }
}

run "endpoint_needs_scheme" {
  command = plan

  variables {
    registry_mirrors = { "docker.io" = { endpoints = ["mirror.internal:5000"] } }
  }

  expect_failures = [var.registry_mirrors]
}

run "mirror_key_is_a_host" {
  command = plan

  variables {
    registry_mirrors = { "https://docker.io" = { endpoints = ["https://mirror.internal"] } }
  }

  expect_failures = [var.registry_mirrors]
}

run "auth_pair_must_be_complete" {
  command = plan

  variables {
    registry_configs = { "mirror.internal" = { username = "puller" } }
  }

  expect_failures = [var.registry_configs]
}

# Comment stripping drops lines starting with "#" in config-dir files, which
# would cut a multi-line credential rendered as a YAML block scalar.
run "credentials_must_be_single_line" {
  command = plan

  variables {
    registry_configs = { "mirror.internal" = { username = "puller", password = "p#\n#x" } }
  }

  expect_failures = [var.registry_configs]
}
