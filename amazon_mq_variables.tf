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
# variables.tf
#
# This file defines all the variables for the creation and maintenance of
# Amazon MQ in AWS for Project Houston
# -----------------------------------------------------------------------------

# variables.tf - Define variables for customization

variable "project_name" {
  description = "Name of the project (used for tags)"
  type	      = string
  default     = ""
}

variable "region" {
  description = "Region in which to create Amazon MQ services"
  type	      = string
  default     = null
}

variable "vpc_id" {
  description = "VPC to use for Amazon MQ service"
  type	      = string
  default     = null
}

variable "subnet_1_id" {
  description = "First subnet in which to create the Amazon MQ service"
  type	      = string
  default     = null
}

variable "subnet_2_id" {
  description = "Second subnet in which to create the Amazon MQ service"
  type	      = string
  default     = null
}

variable "tags" {
  description = "Name:Value pairs used to tag every resource"
  type	      = map(string)
  default     = {}
}

variable "hosted_zone_name" {
  description = "Route 53 Private Hosted Zone Name"
  type        = string
  default     = ""
}

# RabbitMQ (Amazon MQ) settings

variable "engine_version" {
  description = "RabbitMQ engine version for Amazon MQ"
  type        = string
  # Check AWS docs/console for latest supported; 3.13 as an example
  default     = "3.13"
}

variable "instance_type" {
  description = "Amazon MQ RabbitMQ broker instance type"
  type        = string
  # mq.m5 family is typical for RabbitMQ
  default     = "mq.m5.large"
}

variable "admin_username" {
  description = "Initial admin username for Amazon MQ RabbitMQ"
  type        = string
  sensitive   = true
}

variable "admin_password" {
  description = "Initial admin password for Amazon MQ RabbitMQ"
  type        = string
  sensitive   = true
}

variable "site_username" {
  description = "Admin username for the administration user on the *site* RabbitMQ containers"
  type        = string
  sensitive   = true
}

variable "site_password" {
  description = "Password for the admin user on the *site* RabbitMQ containers"
  type        = string
  sensitive   = true
}

variable "site_password_hash" {
  description = "Precomputed RabbitMQ password hash for the site admin user (for definitions.json)"
  type        = string
  sensitive   = true
}
