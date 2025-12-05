# Copyright (c) 2025 Hammerspace, Inc
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# -----------------------------------------------------------------------------
# main.tf
#
# This file creates and maintains all of the assets for MSK (Kafka) on AWS for
# Project Houston.
# -----------------------------------------------------------------------------

# Run 'terraform init', 'terraform plan', 'terraform apply' to use.

# Needed to fetch the current AWS account details

data "aws_caller_identity" "current" {}

# Load the customer site configs (if they exist)

locals {
  site_configs_dir = "${path.module}/site-configs"

  site_configs = {
    for file in fileset(local.site_configs_dir, "*.json") :
      trimsuffix(file, ".json") => jsondecode(file("${local.site_configs_dir}/${file}"))
  }

  central_amqps_endpoint = aws_mq_broker.rabbitmq.instances[0].endpoints[0]
  central_amqps_host     = replace(local.central_amqps_endpoint, "amqps://", "")
}
      
# Security Group for Amazon MQ RabbitMQ Broker

resource "aws_security_group" "rabbitmq_sg" {
  name        = "${var.project_name}-rabbitmq-sg"
  description = "Security group for Amazon MQ RabbitMQ broker"
  vpc_id      = var.vpc_id

  # Ingress: AMQP over TLS (5671). For now open to all; tighten to site IPs/VPN later.
  ingress {
    from_port   = 5671
    to_port     = 5671
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: allow all egress
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project_name}-rabbitmq-sg" })
}

# Optional Route 53 Private Hosted Zone

resource "aws_route53_zone" "private" {
  name = var.hosted_zone_name
  vpc {
    vpc_id = var.vpc_id
  }

  tags = merge(var.tags, { Name = "${var.project_name}-dns" })
}

# Amazon MQ RabbitMQ Broker (central site)

resource "aws_mq_broker" "rabbitmq" {
  broker_name        = "${var.project_name}-rabbitmq"
  engine_type        = "RabbitMQ"
  engine_version     = var.engine_version
  host_instance_type = var.instance_type

  # Multi-AZ RabbitMQ cluster across your two private subnets
  deployment_mode            = "CLUSTER_MULTI_AZ"

  publicly_accessible        = true
  auto_minor_version_upgrade = true
  apply_immediately          = true

  logs {
    general = true
  }

  # Initial admin user for RabbitMQ management + shovels
  user {
    username       = var.admin_username
    password       = var.admin_password
    console_access = true
  }

  tags = merge(var.tags, { Name = "${var.project_name}-rabbitmq" })
}

# Build the definitions files for each site

resource "null_resource" "configure_rabbitmq_sites" {
  for_each = local.site_configs

  # Make it crystal clear: don't run until the broker exists
  depends_on = [aws_mq_broker.rabbitmq]
  
  # So Terraform reruns when config changes
  triggers = {
    config_hash = sha1(jsonencode(each.value))
  }

  provisioner "local-exec" {
    command = <<EOT
${path.module}/scripts/configure_rabbitmq.sh \
  --base-url ${aws_mq_broker.rabbitmq.instances[0].console_url} \
  --user ${var.admin_username} \
  --password '${var.admin_password}' \
  --config-b64 '${base64encode(jsonencode(each.value))}'
EOT
  }
}

# Generate the local site_definitions files

resource "local_file" "site_definitions" {
  for_each = local.site_configs

  filename = "${path.module}/dist/${each.key}-definitions.json"

  content = jsonencode({
    vhosts = [
      { name = "/" }
    ]

    users = [
      {
        name              = "admin"
        password_hash     = var.site_password_hash
        hashing_algorithm = "rabbit_password_hashing_sha256"
        tags              = ["administrator"]
      }
    ]

    permissions = [
      {
        user      = "admin"
        vhost     = "/"
        configure = ".*"
        write     = ".*"
        read      = ".*"
      }
    ]

    # ------------------------------------------------------------
    # exchanges:
    #   remote side needs all four exchanges, but only commands
    #   gets queues/bindings here.
    # ------------------------------------------------------------
    exchanges = [
      for name, cfg in each.value : {
        name        = cfg.exchange
        vhost       = "/"
        type        = "topic"
        durable     = true
        auto_delete = false
        internal    = false
        arguments   = {}
      } if name != "vhost"
    ]

    # ------------------------------------------------------------
    # queues (remote):
    #   - NO telemetry/events/performance queues (they go to central).
    #   - ONLY commands queues (hammerspace.from-aws, catalog.from-aws, etc.)
    # ------------------------------------------------------------
    queues = flatten([
      for name, cfg in each.value : [
        for q in (name == "commands" && can(cfg.queues) ? cfg.queues : []) : {
          name        = q.name
          vhost       = "/"
          durable     = true
          auto_delete = false
          arguments   = {}
        }
      ]
    ])

    # ------------------------------------------------------------
    # bindings (remote):
    #   - same: only for commands queues.
    #   - routing key is per-queue (q.routing_key).
    # ------------------------------------------------------------
    bindings = flatten([
      for name, cfg in each.value : [
        for q in (name == "commands" && can(cfg.queues) ? cfg.queues : []) : {
          source           = cfg.exchange  # "commands"
          vhost            = "/"
          destination      = q.name
          destination_type = "queue"
          routing_key      = lookup(q, "routing_key", "#")
          arguments        = {}
        }
      ]
    ])

    # ------------------------------------------------------------
    # Shovels (remote rabbit):
    #
    #  - telemetry_to_aws, events_to_aws, performance_to_aws:
    #      src-exchange = telemetry/events/performance  (remote)
    #      src-exchange-key = "#" (or tighten later)
    #      dest-exchange = same exchange on central
    #      NO dest-exchange-key => original routing key preserved
    #
    #  - commands_from_aws:
    #      src-exchange = commands (central)
    #      src-exchange-key = "#"
    #      dest-exchange = commands (remote)
    #      NO dest-exchange-key => original routing key preserved
    #
    #  Commands queues & bindings at the remote site determine
    #  which queue gets which commands.* messages.
    # ------------------------------------------------------------
    parameters = [
      {
        vhost     = "/"
        component = "shovel"
        name      = "telemetry_to_aws"
        value = {
          "src-uri"          = "amqp://${urlencode(var.site_username)}:${urlencode(var.site_password)}@localhost:5672/%2F"
          "src-exchange"     = each.value.telemetry.exchange
          "src-exchange-key" = "#"

          "dest-uri"      = "amqps://${urlencode(var.admin_username)}:${urlencode(var.admin_password)}@${local.central_amqps_host}/${urlencode(each.value.vhost)}?verify=verify_none"
          "dest-exchange" = each.value.telemetry.exchange

          "ack-mode"        = "on-confirm"
          "reconnect-delay" = 5
        }
      },
      {
        vhost     = "/"
        component = "shovel"
        name      = "events_to_aws"
        value = {
          "src-uri"          = "amqp://${urlencode(var.site_username)}:${urlencode(var.site_password)}@localhost:5672/%2F"
          "src-exchange"     = each.value.events.exchange
          "src-exchange-key" = "#"

          "dest-uri"      = "amqps://${urlencode(var.admin_username)}:${urlencode(var.admin_password)}@${local.central_amqps_host}/${urlencode(each.value.vhost)}?verify=verify_none"
          "dest-exchange" = each.value.events.exchange

          "ack-mode"        = "on-confirm"
          "reconnect-delay" = 5
        }
      },
      {
        vhost     = "/"
        component = "shovel"
        name      = "performance_to_aws"
        value = {
          "src-uri"          = "amqp://${urlencode(var.site_username)}:${urlencode(var.site_password)}@localhost:5672/%2F"
          "src-exchange"     = each.value.performance.exchange
          "src-exchange-key" = "#"

          "dest-uri"      = "amqps://${urlencode(var.admin_username)}:${urlencode(var.admin_password)}@${local.central_amqps_host}/${urlencode(each.value.vhost)}?verify=verify_none"
          "dest-exchange" = each.value.performance.exchange

          "ack-mode"        = "on-confirm"
          "reconnect-delay" = 5
        }
      },
      {
        vhost     = "/"
        component = "shovel"
        name      = "commands_from_aws"
        value = {
          # Source is the central AWS broker, commands exchange in the site's vhost
          "src-uri"          = "amqps://${urlencode(var.admin_username)}:${urlencode(var.admin_password)}@${local.central_amqps_host}/${urlencode(each.value.vhost)}?verify=verify_none"
          "src-exchange"     = each.value.commands.exchange
          "src-exchange-key" = "#"

          # Destination is the local site broker, commands exchange on "/"
          "dest-uri"      = "amqp://${urlencode(var.site_username)}:${urlencode(var.site_password)}@localhost:5672/%2F"
          "dest-exchange" = each.value.commands.exchange

          "ack-mode"        = "on-confirm"
          "reconnect-delay" = 5
        }
      }
    ]
  })
}

# Make the output of the site definitions file look "pretty"

resource "null_resource" "pretty_print_definitions" {
  depends_on = [local_file.site_definitions]

  provisioner "local-exec" {
    working_dir = path.module
    command = <<EOT
for f in dist/*-definitions.json; do
  python3 -m json.tool "$${f}" > "$${f}.tmp" && mv "$${f}.tmp" "$${f}"
done
EOT
  }
}
