# terraform-aws-amazon-mq

This is a Terraform module and cannot stand on its own. It is meant to be included into a project as a module (or published to the Terraform Registry).

This module deploys an **Amazon MQ (RabbitMQ)** broker for a central site and supports:

* A multi-AZ RabbitMQ cluster in your VPC
* An associated security group
* An optional Route 53 private hosted zone
* Per-site RabbitMQ configuration driven by JSON files in `site-configs/` (exchanges, queues, bindings, and shovels)

Most **guard-rails** (VPC/subnet selection, instance type checks, etc.) are expected to live in the *root* Terraform project that imports this module. This module still validates that required inputs are present and uses `configure_rabbitmq.sh` / `configure_rabbitmq.py` to apply per-site configuration to the broker.

---

## Table of Contents

* [Configuration](#configuration)
* [Using this module](#using-this-module)
* [Module Variables](#module-variables)

  * [Core & Network Variables](#core--network-variables)
  * [RabbitMQ Credentials](#rabbitmq-credentials)
  * [DNS / Hosted Zone](#dns--hosted-zone)
* [Site Configs (per-site JSON)](#site-configs-per-site-json)

  * [Schema](#schema)
  * [Example site config](#example-site-config)
* [Outputs](#outputs)

---

## Configuration

Configuration is typically done in the **root project** using `terraform.tfvars` (or equivalent). In the root:

1. **Re-declare** this module’s variables in your root `variables.tf` (optionally with a prefix like `amazonmq_` if you want to differentiate them there).
2. **Wire** those root variables into this module in `main.tf`.

> Example naming convention:
>
> * Root variable: `variable "amazonmq_engine_version" { ... }`
> * Module call: `engine_version = var.amazonmq_engine_version`

---

## Using this module

Example usage in your root `main.tf`:

```hcl
module "amazon_mq" {
  source = "git::https://github.com/hammerspace-solutions/terraform-aws-amazon-mq.git?ref=v1.0.0"

  project_name = "houston"
  region       = "us-east-1"

  # Network (existing VPC)
  vpc_id      = var.amazonmq_vpc_id
  subnet_1_id = var.amazonmq_private_subnet_1_id
  subnet_2_id = var.amazonmq_private_subnet_2_id

  # RabbitMQ broker configuration
  engine_version = var.amazonmq_engine_version   # e.g. "3.13"
  instance_type  = var.amazonmq_instance_type    # e.g. "mq.m5.large"

  # Central broker admin credentials
  admin_username = var.amazonmq_admin_username
  admin_password = var.amazonmq_admin_password

  # Site broker admin credentials (used in shovels & site definitions)
  site_username       = var.amazonmq_site_admin_username
  site_password       = var.amazonmq_site_admin_password
  site_password_hash  = var.amazonmq_site_admin_password_hash

  # Optional Route 53 private hosted zone
  hosted_zone_name = var.amazonmq_hosted_zone_name # e.g. "rabbit.internal.example.com"

  tags = var.common_tags
}
```

The root project is responsible for:

* Ensuring `vpc_id` and `subnet_*_id` refer to valid subnets in the selected region
* Passing in secure credentials (e.g. via TF Cloud variables, SSM Parameter Store, etc.)
* Optionally providing `hosted_zone_name` if you want a private DNS name for the broker

---

## Module Variables

### Core & Network Variables

These are the **module’s** variable names (from `variables.tf` in this repo):

* `project_name` (string)
  Human-readable project name. Used in tags and resource names.

* `region` (string)
  AWS region in which to create the Amazon MQ broker.

* `vpc_id` (string)
  Existing VPC ID where the broker and security group will be created.

* `subnet_1_id` (string)
  First subnet ID (private) used by the Amazon MQ multi-AZ deployment.

* `subnet_2_id` (string)
  Second subnet ID (private) used by the Amazon MQ multi-AZ deployment.

* `tags` (map(string))
  Common tags applied to all resources.

### RabbitMQ Credentials

* `engine_version` (string, default `"3.13"`)
  RabbitMQ engine version for Amazon MQ.

* `instance_type` (string, default `"mq.m5.large"`)
  Amazon MQ RabbitMQ broker instance type.

* `admin_username` (string, sensitive)
  Initial **central broker** admin username (for the Amazon MQ console & shovels).

* `admin_password` (string, sensitive)
  Initial **central broker** admin password.

* `site_username` (string, sensitive)
  Admin username on the **site RabbitMQ containers** (remote sites).

* `site_password` (string, sensitive)
  Password for the site admin user.

* `site_password_hash` (string, sensitive)
  Precomputed RabbitMQ password hash for the site admin user
  (used inside the generated `*-definitions.json` for site brokers).

### DNS / Hosted Zone

* `hosted_zone_name` (string, default `""`)
  If non-empty, a **Route 53 private hosted zone** is created and associated with the given `vpc_id`.
  The broker name and other records can be created under this zone.

---

## Site Configs (per-site JSON)

This module can read **per-site JSON config files** from:

```text
site-configs/*.json
```

and use them to:

* Configure **exchanges / queues / bindings** on the **site** brokers
* Generate per-site `*-definitions.json` files in `dist/`
* Create **shovels** between each remote **site broker** and the **central Amazon MQ broker**

These JSON files are *not* Terraform variables; they are read from disk by:

* Terraform’s `local_file.site_definitions` (to generate RabbitMQ definitions JSON)
* `scripts/configure_rabbitmq.sh` / `scripts/configure_rabbitmq.py`
  (to push config into the central broker via its HTTP API)

### Schema

Each site config describes:

* A **vhost** name on the **central** broker
* For each category (`telemetry`, `events`, `performance`, `commands`):

  * One exchange
  * One or more queues bound to that exchange

Schema (shown here as JSON with comments for documentation):

```jsonc
{
  // Top-level vhost name on the CENTRAL broker
  "vhost": "<central-vhost-name>",

  // Category blocks (telemetry, events, performance, commands)
  //
  // Each block has:
  //   "exchange": "<exchange-name>",
  //   "queues": [
  //     {
  //       "name": "<queue-name>",
  //       "routing_key": "<routing-key-pattern>"
  //     },
  //     ...
  //   ]
  //
  // The Python configurator will:
  //   - ensure the vhost exists
  //   - create the exchange (type=topic, durable)
  //   - create each queue (durable)
  //   - create bindings exchange -> queue with the given routing_key

  "telemetry": {
    "exchange": "telemetry",
    "queues": [
      {
        "name": "hammerspace.to-aws",
        "routing_key": "hammerspace.#"
      },
      {
        "name": "catalog.to-aws",
        "routing_key": "catalog.#"
      }
    ]
  },

  "events": {
    "exchange": "events",
    "queues": [
      {
        "name": "events.to-aws",
        "routing_key": "#"
      }
    ]
  },

  "performance": {
    "exchange": "performance",
    "queues": [
      {
        "name": "performance.to-aws",
        "routing_key": "#"
      }
    ]
  },

  "commands": {
    "exchange": "commands",
    "queues": [
      {
        "name": "hammerspace.from-aws",
        "routing_key": "hammerspace.#"
      },
      {
        "name": "catalog.from-aws",
        "routing_key": "catalog.#"
      }
    ]
  }
}
```

> **Important:**
> The real `*.json` files used by Terraform/Python must be **pure JSON** — no comments.
> You can keep a commented version as `site.json.example` and strip comments when creating the real files.

### How the scripts use this

* `scripts/configure_rabbitmq.sh`

  * Creates a Python virtualenv (`.venv` under the module)
  * Installs `requests` (from `requirements.txt`)
  * Invokes `configure_rabbitmq.py` with:

    * `--base-url` pointing to the central broker console URL
    * `--user` / `--password` from `admin_username` / `admin_password`
    * `--config-b64` with the site config as base64-encoded JSON

* `scripts/configure_rabbitmq.py`

  * Decodes the config
  * Ensures the vhost exists
  * For each block (`telemetry`, `events`, `performance`, `commands`):

    * Creates the exchange (type `topic`, durable)
    * Creates each queue under that exchange
    * Creates the bindings using the specified `routing_key`

---

## Outputs

After a successful `apply`, this module provides the following outputs
(see `outputs.tf`). Sensitive values are redacted in Terraform CLI
and can be viewed with:

```bash
terraform output <output_name>
```

* `amazonmq_broker_id` (sensitive)
  ID of the Amazon MQ RabbitMQ broker.

* `amazonmq_broker_arn` (sensitive)
  ARN of the Amazon MQ RabbitMQ broker.

* `amazonmq_security_group_id` (sensitive)
  Security group ID attached to the RabbitMQ broker.

* `amazonmq_amqps_endpoint`
  Primary **AMQPS** endpoint for the RabbitMQ broker
  (this is what your shovels will generally use).

* `amazonmq_console_url`
  Web management console URL for the broker.

* `hosted_zone_id`
  ID of the Route 53 private hosted zone created for this broker
  (only set if `hosted_zone_name` was non-empty).

Example output:

```text
amazonmq_broker_id          = <sensitive>
amazonmq_amqps_endpoint     = "amqps://b-ece8a874-0fad-43a9-8f1e-cd14ac60939b.mq.us-east-1.on.aws:5671"
amazonmq_broker_arn         = <sensitive>
amazonmq_console_url        = "https://b-ece8a874-0fad-43a9-8f1e-cd14ac60939b.mq.us-east-1.on.aws"
hosted_zone_id              = "Z04378071RO6F29EWR5NS"
amazonmq_security_group_id  = <sensitive>
```
