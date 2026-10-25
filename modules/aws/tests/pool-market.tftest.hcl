# gpu_pools market and capacity_reservation_id: on-demand by default, spot, Capacity
# Block, and an On-Demand Capacity Reservation. Mock providers only.

variables {
  region                  = "us-east-1"
  admin_cidrs             = ["198.51.100.0/24"]
  root_password_hash      = "$6$DUMMYSALT$ROOTDUMMYHASHROOTDUMMYHASHROOTDUMMYHASHROOTDUMMYHASHROOTDUMMYHASH0"
  node_user_password_hash = "$6$DUMMYSALT$NODEDUMMYHASHNODEDUMMYHASHNODEDUMMYHASHNODEDUMMYHASHNODEDUMMYHASH0"
  ssh_authorized_keys     = ["ssh-ed25519 AAAADUMMY test"]
  cluster_name            = "market-aws"
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
run "on_demand_by_default" {
  command = plan

  assert {
    condition     = length(aws_instance.agent["market-aws-gpu-01"].instance_market_options) == 0 && length(aws_instance.agent["market-aws-gpu-01"].capacity_reservation_specification) == 0
    error_message = "Without market or capacity_reservation_id the node is plain on-demand."
  }
}

run "spot" {
  command = plan

  variables {
    gpu_pools = { gpu = { instance_type = "g6.xlarge", count = 1, market = "spot" } }
  }

  assert {
    condition     = aws_instance.agent["market-aws-gpu-01"].instance_market_options[0].market_type == "spot"
    error_message = "market = spot must request a spot instance."
  }

  assert {
    condition = (
      aws_instance.agent["market-aws-gpu-01"].instance_market_options[0].spot_options[0].spot_instance_type == "one-time" &&
      aws_instance.agent["market-aws-gpu-01"].instance_market_options[0].spot_options[0].instance_interruption_behavior == "terminate"
    )
    error_message = "Spot nodes are one-time and terminated on interruption, so the next apply replaces them."
  }
}

run "capacity_block" {
  command = plan

  variables {
    gpu_pools = { gpu = { instance_type = "g6.xlarge", count = 1, market = "capacity-block", capacity_reservation_id = "cr-0123456789abcdef0" } }
  }

  assert {
    condition     = aws_instance.agent["market-aws-gpu-01"].instance_market_options[0].market_type == "capacity-block"
    error_message = "market = capacity-block must set the capacity-block market type."
  }

  assert {
    condition     = aws_instance.agent["market-aws-gpu-01"].capacity_reservation_specification[0].capacity_reservation_target[0].capacity_reservation_id == "cr-0123456789abcdef0"
    error_message = "A Capacity Block is targeted by its reservation ID."
  }
}

run "on_demand_reservation" {
  command = plan

  variables {
    gpu_pools = { gpu = { instance_type = "g6.xlarge", count = 1, capacity_reservation_id = "cr-0fedcba9876543210" } }
  }

  assert {
    condition = (
      length(aws_instance.agent["market-aws-gpu-01"].instance_market_options) == 0 &&
      aws_instance.agent["market-aws-gpu-01"].capacity_reservation_specification[0].capacity_reservation_target[0].capacity_reservation_id == "cr-0fedcba9876543210"
    )
    error_message = "An On-Demand Capacity Reservation is targeted without a market type."
  }
}

run "control_plane_unaffected" {
  command = plan

  variables {
    gpu_pools = { gpu = { instance_type = "g6.xlarge", count = 1, market = "spot" } }
  }

  assert {
    condition     = length(aws_instance.control_plane["market-aws-cp-01"].instance_market_options) == 0
    error_message = "Control planes stay on-demand."
  }
}

# Persistent inference, interruptible training and a reserved block side by side.
run "mixed_pools" {
  command = plan

  variables {
    gpu_pools = {
      inference = { instance_type = "g6.xlarge", count = 2 }
      training  = { instance_type = "g6.xlarge", count = 2, market = "spot" }
      reserved  = { instance_type = "g6.xlarge", count = 1, market = "capacity-block", capacity_reservation_id = "cr-0123456789abcdef0" }
    }
    worker_pools = { cpu = { instance_type = "m7i.xlarge", count = 1, capacity_reservation_id = "cr-0fedcba9876543210" } }
  }

  assert {
    condition = alltrue([
      for n in ["market-aws-inference-01", "market-aws-inference-02"] :
      length(aws_instance.agent[n].instance_market_options) == 0 && length(aws_instance.agent[n].capacity_reservation_specification) == 0
    ])
    error_message = "Pools without market stay on-demand without a reservation."
  }

  assert {
    condition = alltrue([
      for n in ["market-aws-training-01", "market-aws-training-02"] :
      aws_instance.agent[n].instance_market_options[0].market_type == "spot" && length(aws_instance.agent[n].capacity_reservation_specification) == 0
    ])
    error_message = "Every instance of a spot pool is spot, without a reservation."
  }

  assert {
    condition = (
      aws_instance.agent["market-aws-reserved-01"].instance_market_options[0].market_type == "capacity-block" &&
      aws_instance.agent["market-aws-reserved-01"].capacity_reservation_specification[0].capacity_reservation_target[0].capacity_reservation_id == "cr-0123456789abcdef0"
    )
    error_message = "The capacity-block pool targets its own reservation."
  }

  assert {
    condition = (
      length(aws_instance.agent["market-aws-cpu-01"].instance_market_options) == 0 &&
      aws_instance.agent["market-aws-cpu-01"].capacity_reservation_specification[0].capacity_reservation_target[0].capacity_reservation_id == "cr-0fedcba9876543210"
    )
    error_message = "A worker pool's On-Demand Capacity Reservation does not leak into GPU pools or vice versa."
  }

  assert {
    condition = (
      length(aws_instance.control_plane["market-aws-cp-01"].instance_market_options) == 0 &&
      length(aws_instance.control_plane["market-aws-cp-01"].capacity_reservation_specification) == 0
    )
    error_message = "Pool purchase options never reach the control plane."
  }
}

run "malformed_reservation_id_rejected" {
  command = plan

  variables {
    gpu_pools = { gpu = { instance_type = "g6.xlarge", count = 1, market = "capacity-block", capacity_reservation_id = "cb-123" } }
  }

  expect_failures = [var.gpu_pools]
}

run "malformed_worker_reservation_id_rejected" {
  command = plan

  variables {
    worker_pools = { cpu = { instance_type = "m7i.xlarge", count = 1, capacity_reservation_id = "CR-0123456789ABCDEF0" } }
  }

  expect_failures = [var.worker_pools]
}

run "unknown_market_rejected" {
  command = plan

  variables {
    gpu_pools = { gpu = { instance_type = "g6.xlarge", count = 1, market = "reserved" } }
  }

  expect_failures = [var.gpu_pools]
}

run "capacity_block_needs_reservation" {
  command = plan

  variables {
    gpu_pools = { gpu = { instance_type = "g6.xlarge", count = 1, market = "capacity-block" } }
  }

  expect_failures = [var.gpu_pools]
}

run "spot_cannot_target_reservation" {
  command = plan

  variables {
    worker_pools = { cpu = { instance_type = "m7i.xlarge", count = 1, market = "spot", capacity_reservation_id = "cr-0123456789abcdef0" } }
  }

  expect_failures = [var.worker_pools]
}
