# Aurora Terraform Module – Project Houston

This Terraform module provisions an **Amazon Aurora** database cluster for Project Houston, including networking, encryption, performance tuning, and optional event notifications.

It is designed to be called from a root module that already creates:

* A VPC
* Private subnets for database instances
* Any application EC2 instances that will connect to Aurora

---

## Features

This module creates:

* **Security Group** for Aurora

  * Inbound PostgreSQL port (5432) from the VPC CIDR and optional additional CIDR blocks
* **DB Subnet Group**

  * Uses two subnets for high availability across AZs
* **Aurora DB Cluster**

  * Supports `aurora-postgresql` and `aurora-mysql`
  * Configurable engine version
  * Encrypted storage with optional KMS CMK
  * Backups and maintenance windows
  * Optional final snapshot on deletion
  * Optional Data API (HTTP endpoint)
* **Aurora Cluster Instances**

  * N instances (configurable count and instance class)
  * Optional Performance Insights with configurable retention and KMS key
* **Optional Event Notifications**

  * SNS topic
  * Email subscription
  * RDS event subscription filtered on the Aurora cluster

---

## Example Usage

```hcl
module "aurora" {
  source = "./modules/aurora"

  project_name = "projecthouston"
  region       = "us-west-2"

  vpc_id      = module.network.vpc_id
  subnet_1_id = module.network.private_subnet_ids[0]
  subnet_2_id = module.network.private_subnet_ids[1]

  # Optional: extra CIDR blocks that can reach Aurora
  allowed_source_cidr_blocks = [
    "10.10.0.0/16",  # corporate VPN
  ]

  engine         = "aurora-postgresql"
  engine_version = "15.3"
  instance_class = "db.r6g.large"
  instance_count = 2

  db_name         = "projecthouston"
  master_username = "houston_admin"
  master_password = var.aurora_master_password

  backup_retention_days        = 7
  preferred_backup_window      = "04:00-05:00"
  preferred_maintenance_window = "sun:06:00-sun:07:00"

  deletion_protection = true
  storage_encrypted   = true
  kms_key_id          = "" # use default AWS-managed KMS key

  skip_final_snapshot       = true
  final_snapshot_identifier = "" # ignored when skip_final_snapshot = true

  enable_performance_insights          = true
  performance_insights_retention_period = 7
  performance_insights_kms_key_id       = ""

  enable_http_endpoint = false

  # Optional: enable event notifications by providing an email
  event_email = "dba-team@example.com"

  tags = {
    Project     = "ProjectHouston"
    Environment = "dev"
    Owner       = "PlatformTeam"
  }
}
```

---

## Inputs

| Name                         | Type           | Default | Required | Description                                                                              |
| ---------------------------- | -------------- | ------- | -------- | ---------------------------------------------------------------------------------------- |
| `project_name`               | `string`       | n/a     | **Yes**  | Project name for tagging and resource naming.                                            |
| `region`                     | `string`       | n/a     | **Yes**  | AWS region for the Aurora cluster.                                                       |
| `vpc_id`                     | `string`       | n/a     | **Yes**  | VPC ID in which to place the Aurora resources.                                           |
| `subnet_1_id`                | `string`       | `null`  | **Yes**  | First subnet ID for the Aurora DB subnet group.                                          |
| `subnet_2_id`                | `string`       | `null`  | **Yes**  | Second subnet ID for the Aurora DB subnet group.                                         |
| `vpc_cidr_block`             | `string`       | `null`  | No       | Primary VPC CIDR. (Currently not used; VPC CIDR is looked up via data source.)           |
| `allowed_source_cidr_blocks` | `list(string)` | `[]`    | No       | Additional IPv4 CIDR blocks allowed to connect to Aurora (e.g., corporate VPN, bastion). |
| `tags`                       | `map(string)`  | `{}`    | No       | Common tags applied to all Aurora resources.                                             |

### Engine & Sizing

| Name              | Type     | Default               | Required | Description                                                   |
| ----------------- | -------- | --------------------- | -------- | ------------------------------------------------------------- |
| `engine`          | `string` | `"aurora-postgresql"` | No       | Aurora engine: `aurora-postgresql` or `aurora-mysql`.         |
| `engine_version`  | `string` | `"15.3"`              | No       | Aurora engine version. If empty, AWS chooses a default.       |
| `instance_class`  | `string` | `"db.r6g.large"`      | No       | Aurora instance class (e.g., `db.r6g.large`, `db.r7g.large`). |
| `instance_count`  | `number` | `2`                   | No       | Number of Aurora instances in the cluster (must be ≥ 1).      |
| `db_name`         | `string` | `"projecthouston"`    | No       | Initial database name in the Aurora cluster.                  |
| `master_username` | `string` | n/a                   | **Yes**  | Master username for Aurora.                                   |
| `master_password` | `string` | n/a                   | **Yes**  | Master password for Aurora (sensitive).                       |

### Durability, Backups, Maintenance

| Name                           | Type     | Default                 | Required | Description                                                                                                        |
| ------------------------------ | -------- | ----------------------- | -------- | ------------------------------------------------------------------------------------------------------------------ |
| `backup_retention_days`        | `number` | `7`                     | No       | Automated backup retention period (in days).                                                                       |
| `preferred_backup_window`      | `string` | `"04:00-05:00"`         | No       | Preferred backup window (UTC), e.g., `04:00-05:00`.                                                                |
| `preferred_maintenance_window` | `string` | `"sun:06:00-sun:07:00"` | No       | Preferred maintenance window (UTC), e.g., `sun:06:00-sun:07:00`.                                                   |
| `deletion_protection`          | `bool`   | `true`                  | No       | Enables deletion protection on the Aurora cluster.                                                                 |
| `storage_encrypted`            | `bool`   | `true`                  | No       | Enables storage encryption for the Aurora cluster.                                                                 |
| `kms_key_id`                   | `string` | `""`                    | No       | KMS key ID/ARN for storage encryption. If empty and `storage_encrypted = true`, the AWS default KMS key is used.   |
| `skip_final_snapshot`          | `bool`   | `true`                  | No       | Whether to skip creating a final snapshot when destroying the Aurora cluster.                                      |
| `final_snapshot_identifier`    | `string` | `""`                    | No       | Identifier for the final snapshot when destroying the cluster. Must be non-empty if `skip_final_snapshot = false`. |

> **Validation**: When `skip_final_snapshot` is `false`, `final_snapshot_identifier` must be a non-empty string.

### Performance Insights

| Name                                    | Type     | Default | Required | Description                                                               |
| --------------------------------------- | -------- | ------- | -------- | ------------------------------------------------------------------------- |
| `enable_performance_insights`           | `bool`   | `true`  | No       | Enables Performance Insights for Aurora instances.                        |
| `performance_insights_retention_period` | `number` | `7`     | No       | Performance Insights retention period in days (e.g., `7`, `731`, `1095`). |
| `performance_insights_kms_key_id`       | `string` | `""`    | No       | KMS key ID/ARN for Performance Insights (optional).                       |

### HTTP Data API

| Name                   | Type   | Default | Required | Description                                                                                      |
| ---------------------- | ------ | ------- | -------- | ------------------------------------------------------------------------------------------------ |
| `enable_http_endpoint` | `bool` | `false` | No       | Enables the Aurora Data API (HTTP endpoint) for the cluster. Useful for serverless/batch access. |

### Event Notifications

| Name          | Type     | Default | Required | Description                                                                             |
| ------------- | -------- | ------- | -------- | --------------------------------------------------------------------------------------- |
| `event_email` | `string` | `""`    | No       | Email address to receive Aurora/RDS events. If blank, no event subscription is created. |

---

## Outputs

| Name                       | Sensitive | Description                                                             |
| -------------------------- | --------- | ----------------------------------------------------------------------- |
| `aurora_cluster_id`        | Yes       | ID of the Aurora cluster.                                               |
| `aurora_cluster_arn`       | Yes       | ARN of the Aurora cluster.                                              |
| `aurora_cluster_endpoint`  | No        | **Writer endpoint** for the Aurora cluster (use for reads and writes).  |
| `aurora_reader_endpoint`   | No        | **Reader endpoint** for the Aurora cluster (use for read-only traffic). |
| `aurora_security_group_id` | No        | Security group ID for Aurora.                                           |
| `aurora_subnet_group_name` | Yes       | DB subnet group name used by Aurora.                                    |

---

## Networking & Access

* The module creates a security group that:

  * Allows inbound TCP/5432 from:

    * The VPC CIDR (determined via `data.aws_vpc.this.cidr_block`)
    * Any CIDR blocks listed in `allowed_source_cidr_blocks`
  * Allows outbound traffic to `0.0.0.0/0` (typical for RDS connectivity to AWS services).

* You should attach this security group ID to:

  * Application EC2 instances (or their security groups) that need to connect to Aurora.
  * Any bastion hosts used for admin/debug access.

---

## Event Notifications Behavior

If `event_email` is **non-empty**:

1. An SNS topic named `${project_name}-aurora-events` is created.
2. An email subscription to that SNS topic is created for `event_email`.
3. An `aws_db_event_subscription` is created and associated with the Aurora **cluster**, configured with event categories like:

   * `availability`
   * `backup`
   * `configuration change`
   * `failure`
   * `maintenance`

The exact event categories can be adjusted in `aurora_main.tf` depending on your operational needs.

If `event_email` is empty, **no SNS topic or event subscription** resources are created.

---

## Notes & Recommendations

* **Writer vs Reader endpoint**

  * `aurora_cluster_endpoint` always points to the **primary** instance; use it for writes and strongly consistent reads.
  * `aurora_reader_endpoint` load-balances across **read replicas**; use it for read-only traffic where slightly stale data is acceptable.

* **Final snapshots**

  * For production environments, consider setting `skip_final_snapshot = false` and providing a unique `final_snapshot_identifier` to avoid losing data on destroy.

* **Encryption**

  * Default is encrypted storage with the AWS-managed KMS key.
  * For stricter security/posture requirements, provide your own CMK via `kms_key_id`.

* **Tagging**

  * Use the `tags` input to ensure all Aurora resources are tagged for cost allocation, ownership, and environment tracking.

---
