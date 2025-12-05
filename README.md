# terraform-aws-amazon-mq
This is a Terraform module and cannot stand on its own. It is meant to be included into a project as a module or to be uploaded to the Terraform Public Repository.

This module allows you to deploy a Amazon MQ (RabbitMQ) cluster

All of the guard-rails for error free deployments are in the main Terraform project that would import this module. Except for one... Each module must verify that the requested EC2 instance is available in their availability zone. If this is not done, then Terraform could hang waiting for that resource to be available. 

## Table of Contents
- [Configuration](#configuration)
  - [Global Variables](#global-variables)
- [Component Variables](#component-variables)
  - [Hammerspace Variables](#hammerspace-variables)
- [Outputs](#outputs)

## Configuration

Configuration must be done in the main project by managing `terraform.tfvars`. Additionally, in the root of the main project, you must take the variables from this module and include them into root `variables.tf`. We recommend that you preface those variables with the module name, such that a variable in a module that looks like `ami =` is created as `ecgroups-ami =` in the root.

Then, in the root main.tf, you reference this module in the source. This is a sample for your root main.tf.

```module "amazon_mq" {
  source = "git::https://github.com/your-username/terraform-aws-amazon-mq.git?ref=v1.0.0"

  # ... provide the required variables for the module
  rabbitmq_engine_version = "3.13"
  rabbitmq_instance_type  = "mq.m5.large"
  # ... etc.
}
```

## Module Variables

### Amazon MQ Variables

These variables configure the Amazon MQ deployment and are prefixed with `rabbitmq__` in `terraform.tfvars`.

* **`amazonmq_engine_version`**: The version number of Amazon MQ service (Default: "3.13")".
* `amazonmq_instance_type`: Instance type for the Amazon MQ service (Default: "mq.m5.large").
* `amazonmq_admin_username`: Login name for the Amazon MQ service console.
* `amazonmq_admin_password`: Login password for the Amazon MQ service console.
* `amazonmq_site_admin_username`: Login name for any customer site service console
* `amazonmq_site_admin_password`: Login password for any customer site service console
* `amazonmq_site_admin_password_hash`: Hash of the site admin password. Used for queue communications.

## Outputs

After a successful `apply`, this module will provide the following outputs. Sensitive values will be redacted and can be viewed with `terraform output <output_name>`.

* `amazonmq_broker_id`: (sensitive): ID of the Amazon MQ RabbitMQ Broker
* `amazonmq_broker_arn`: (sensitive): ARN of the Amazon MQ RabbitMQ Broker
* `amazonmq_security_group_id`: (sensitive): Security Group ID attached to the Amazon MQ Broker
* `amazonmq_amqps_endpoint`: Primary AMQPS endpoint for the Amazon MQ Broker
* `amazonmq_console_url`: Amazon MQ Management Console URL
* `amazonmq_hosted_zone_id`: Route 53 private hosted zone ID create for Amazon MQ

The output will look something like this:

```
amazonemq_broker_id = <sensitive>
amazonmq_amqps_endpoint = "amqps://b-ece8a874-0fad-43a9-8f1e-cd14ac60939b.mq.us-east-1.on.aws:5671"
amazonmq_broker_arn = <sensitive>
amazonmq_console_url = "https://b-ece8a874-0fad-43a9-8f1e-cd14ac60939b.mq.us-east-1.on.aws"
amazonmq_hosted_zone_id = "Z04378071RO6F29EWR5NS"
amazonmq_security_group_id = <sensitive>
```
