terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type        = string
  default     = null
  description = "Target AWS region. Defaults to the provider chain (AWS_REGION)."
}

data "aws_region" "current" {}

variable "organization_root_id" {
  type        = string
  description = "Organization Root ID if it exists"
}

variable "audit_account" {
  type        = string
  description = "Audit Account ID"
}

variable "log_archive_account" {
  type        = string
  description = "Log Archive Account ID"
}

variable "landing_zone_version" {
  type        = string
  default     = 4.0
  description = "Landing Zone Version"
}

locals {
  cond_organization_root_id_not_empty = (!(var.organization_root_id == ""))
  cond_organization_root_id_empty     = (var.organization_root_id == "")
}

resource "aws_organizations_organization" "organization" {
  count       = local.cond_organization_root_id_empty ? 1 : 0
  feature_set = "ALL"
}

resource "aws_organizations_organizational_unit" "johan_ou" {
  name      = "Johan"
  parent_id = (local.cond_organization_root_id_not_empty ? var.organization_root_id : aws_organizations_organization.organization[0].roots[0].id)
}

resource "aws_controltower_landing_zone" "control_tower_landing_zone" {
  manifest_json = jsonencode({
    accessManagement = {
      enabled = true
    }
    securityRoles = {
      accountId = var.audit_account
      enabled   = true
    }
    backup = {
      enabled = false
    }
    governedRegions = [data.aws_region.current.region]
    config = {
      accountId = var.audit_account
      configurations = {
        loggingBucket = {
          retentionDays = 365
        }
        accessLoggingBucket = {
          retentionDays = 3650
        }
      }
      enabled = true
    }
    centralizedLogging = {
      accountId = var.log_archive_account
      configurations = {
        loggingBucket = {
          retentionDays = 365
        }
        accessLoggingBucket = {
          retentionDays = 3650
        }
      }
      enabled = true
    }
  })
  remediation_types = ["INHERITANCE_DRIFT"]
  version           = var.landing_zone_version
  tags = {
    x = "y"
  }
}

output "control_tower_landing_zone_arn" {
  value       = aws_controltower_landing_zone.control_tower_landing_zone.arn
  description = "ControlTower LandingZone ARN"
}

output "control_tower_landing_zone_identifier" {
  value       = aws_controltower_landing_zone.control_tower_landing_zone.id
  description = "ControlTower LandingZone ID"
}
