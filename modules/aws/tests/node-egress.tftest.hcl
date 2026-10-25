# node_egress_cidrs: the default keeps one open rule per node group; a list
# without 0.0.0.0/0 becomes the VPC plus each CIDR. Mock providers only.

variables {
  region                  = "us-east-1"
  admin_cidrs             = ["198.51.100.0/24"]
  root_password_hash      = "$6$DUMMYSALT$ROOTDUMMYHASHROOTDUMMYHASHROOTDUMMYHASHROOTDUMMYHASHROOTDUMMYHASH0"
  node_user_password_hash = "$6$DUMMYSALT$NODEDUMMYHASHNODEDUMMYHASHNODEDUMMYHASHNODEDUMMYHASHNODEDUMMYHASH0"
  ssh_authorized_keys     = ["ssh-ed25519 AAAADUMMY test"]
  cluster_name            = "egress-aws"
  rancher_hostname        = "rancher.example.com"
  zones                   = ["a"]
  control_plane_count     = 1
  image_id                = "ami-0dummyprebuilt00001"
  appco_username          = "DUMMY-APPCO-USER"
  appco_password          = "DUMMY-APPCO-PASSWORD"
  suse_registry_username  = "DUMMY-REGCODE"
  suse_registry_password  = "DUMMY-REGISTRY-PASSWORD"
  nvidia_api_key          = "DUMMY-NVIDIA-API-KEY"
  gpu_pools               = { gpu = { instance_type = "g6.xlarge", count = 1 } }
}

mock_provider "aws" {
  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  override_data {
    target = data.aws_ec2_instance_type_offerings.this
    values = {
      instance_types = ["m7i.xlarge", "g6.xlarge"]
    }
  }

  override_resource {
    target = aws_lb.api
    values = {
      dns_name = "internal-dummy-api-nlb-1234567890.elb.us-east-1.amazonaws.com"
      arn      = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/dummy-api/0000000000000001"
    }
  }

  override_resource {
    target = aws_lb.public
    values = {
      dns_name = "dummy-public-nlb-0987654321.elb.us-east-1.amazonaws.com"
      arn      = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/net/dummy-public/0000000000000002"
    }
  }

  # Static IP of the public NLB in the first zone, read only when a security or
  # observability component is enabled.
  override_data {
    target = data.aws_network_interface.public_nlb
    values = {
      association = [{ public_ip = "203.0.113.10" }]
    }
  }

  # aws_lb_listener validates load_balancer_arn/target_group_arn look like
  # real ARNs client-side, even against a mocked provider -- the mock
  # default for a computed "arn" attribute is not ARN-shaped, so every
  # target group needs one too.
  override_resource {
    target = aws_lb_target_group.api_kube_api
    values = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/dummy-api-6443/0000000000000003" }
  }

  override_resource {
    target = aws_lb_target_group.api_supervisor
    values = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/dummy-api-9345/0000000000000004" }
  }

  override_resource {
    target = aws_lb_target_group.http
    values = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/dummy-http/0000000000000005" }
  }

  override_resource {
    target = aws_lb_target_group.https
    values = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/dummy-https/0000000000000006" }
  }

  override_resource {
    target = aws_lb_target_group.admin_kube_api
    values = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/dummy-admin-6443/0000000000000007" }
  }

  override_resource {
    target = aws_s3_bucket.build
    values = {
      id = "dummy-build-bucket-000000"
    }
  }

  # These four are aws_iam_policy_document data sources: normally computed
  # locally by the provider (no API call), but under mock_provider they still
  # need an override -- the default mock value for a computed string
  # attribute is "", and aws_iam_role/aws_iam_role_policy's schema validates
  # assume_role_policy/policy as parseable JSON client-side even against a
  # mocked provider, so "" fails plan with "not a JSON object".
  override_data {
    target = data.aws_iam_policy_document.vmimport_trust
    values = {
      json = jsonencode({ Version = "2012-10-17", Statement = [] })
    }
  }

  override_data {
    target = data.aws_iam_policy_document.vmimport
    values = {
      json = jsonencode({ Version = "2012-10-17", Statement = [] })
    }
  }

  override_data {
    target = data.aws_iam_policy_document.jumphost_trust
    values = {
      json = jsonencode({ Version = "2012-10-17", Statement = [] })
    }
  }

  override_data {
    target = data.aws_iam_policy_document.jumphost
    values = {
      json = jsonencode({ Version = "2012-10-17", Statement = [] })
    }
  }
}

mock_provider "aws" {
  alias = "nodes"
}

mock_provider "random" {
  override_resource {
    target = random_password.token
    values = {
      result = "DUMMYTOKENDUMMYTOKENDUMMYTOKEN12"
    }
  }

  override_resource {
    target = module.elemental_config.random_password.rancher_bootstrap
    values = {
      result = "DUMMY-RANCHER-BOOTSTRAP-PW"
    }
  }
}

override_resource {
  target = time_static.created
  values = { rfc3339 = "2026-09-30T12:34:56Z" }
}

run "default_is_open" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.control_plane_all) == 1 && aws_vpc_security_group_egress_rule.control_plane_all[0].cidr_ipv4 == "0.0.0.0/0"
    error_message = "By default the control plane keeps one unrestricted egress rule."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.agent_all) == 1 && length(aws_vpc_security_group_egress_rule.agent_restricted) == 0
    error_message = "By default agents keep one unrestricted egress rule and no restricted ones."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.control_plane_restricted) == 0
    error_message = "By default no restricted control-plane rules exist."
  }
}

run "empty_confines_to_vpc" {
  command = plan

  variables {
    node_egress_cidrs = []
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.control_plane_all) == 0 && length(aws_vpc_security_group_egress_rule.agent_all) == 0
    error_message = "[] must drop the unrestricted egress rules."
  }

  assert {
    condition     = keys(aws_vpc_security_group_egress_rule.control_plane_restricted) == ["10.20.0.0/20"] && keys(aws_vpc_security_group_egress_rule.agent_restricted) == ["10.20.0.0/20"]
    error_message = "[] must leave egress to the VPC CIDR only, on both node groups."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.jumphost_all.cidr_ipv4 == "0.0.0.0/0"
    error_message = "The jumphost must keep unrestricted egress to build the image."
  }
}

run "listed_cidrs_added" {
  command = plan

  variables {
    node_egress_cidrs = ["203.0.113.0/24", "198.51.100.7/32"]
  }

  assert {
    condition     = toset(keys(aws_vpc_security_group_egress_rule.control_plane_restricted)) == toset(["10.20.0.0/20", "203.0.113.0/24", "198.51.100.7/32"])
    error_message = "Listed CIDRs are added to the VPC CIDR."
  }

  assert {
    condition     = toset(keys(aws_vpc_security_group_egress_rule.agent_restricted)) == toset(keys(aws_vpc_security_group_egress_rule.control_plane_restricted))
    error_message = "Agents get the same restricted egress CIDRs as the control plane."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.control_plane_all) == 0 && length(aws_vpc_security_group_egress_rule.agent_all) == 0
    error_message = "Without 0.0.0.0/0 no unrestricted egress rule may remain."
  }
}

run "explicit_open_cidr_is_unrestricted" {
  command = plan

  variables {
    node_egress_cidrs = ["10.0.0.0/8", "0.0.0.0/0"]
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.control_plane_all) == 1 && length(aws_vpc_security_group_egress_rule.agent_all) == 1
    error_message = "0.0.0.0/0 anywhere in the list means unrestricted egress on both node groups."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.control_plane_restricted) == 0 && length(aws_vpc_security_group_egress_rule.agent_restricted) == 0
    error_message = "With 0.0.0.0/0 the other listed CIDRs are redundant and get no rules."
  }
}

run "locked_has_no_ipv6_path" {
  command = plan

  variables {
    node_egress_cidrs = []
  }

  assert {
    condition     = aws_vpc.this.assign_generated_ipv6_cidr_block != true && aws_vpc.this.ipv6_ipam_pool_id == null
    error_message = "The VPC must not get IPv6: the egress rules are IPv4-only."
  }

  assert {
    condition = alltrue(concat(
      [for r in aws_vpc_security_group_egress_rule.control_plane_restricted : r.cidr_ipv6 == null],
      [for r in aws_vpc_security_group_egress_rule.agent_restricted : r.cidr_ipv6 == null],
    ))
    error_message = "Locked node egress rules must not allow IPv6 destinations."
  }
}

run "no_agent_rules_without_pools" {
  command = plan

  variables {
    node_egress_cidrs = []
    gpu_pools         = {}
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.agent_restricted) == 0
    error_message = "Without worker or GPU pools there is no agent group to attach rules to."
  }
}

run "invalid_cidr_rejected" {
  command = plan

  variables {
    node_egress_cidrs = ["10.0.0.0"]
  }

  expect_failures = [var.node_egress_cidrs]
}

run "host_bits_rejected" {
  command = plan

  variables {
    node_egress_cidrs = ["10.20.0.5/24"]
  }

  expect_failures = [var.node_egress_cidrs]
}
