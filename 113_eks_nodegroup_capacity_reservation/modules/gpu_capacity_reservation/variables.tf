variable "instance_type" {
  type        = string
  default     = "g4dn.xlarge"
  description = "Instance type reserved, as the _monolithic template reserved it. The reservation is for one exact type in one exact zone - that specificity is the point of it, and also why the node group's launch template has to name the same type"

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a valid EC2 instance type, e.g. g4dn.xlarge."
  }
}
variable "availability_zone" {
  type        = string
  description = "Zone the capacity is reserved in. A reservation is zonal, so the node group can only place instances in the subnet that lives in this zone - naming a different one leaves the reservation unused and the nodes unschedulable"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9][a-z]$", var.availability_zone))
    error_message = "availability_zone must be a full zone name such as ap-northeast-2c."
  }
}
variable "instance_count" {
  type        = number
  default     = 1
  description = "Instances reserved, one as the _monolithic template reserved. This is the hard ceiling on the node group: a node group asking for more than this with capacity-reservations-only simply cannot launch the extra instances"

  validation {
    condition     = var.instance_count >= 1
    error_message = "instance_count must be at least 1."
  }
}
variable "instance_platform" {
  type        = string
  default     = "Linux/UNIX"
  description = "Platform the reservation is for, as the _monolithic template had it. It has to match the AMI the node group launches - a Linux/UNIX reservation does not cover a Windows or RHEL instance, and the mismatch appears as capacity that is never used"

  validation {
    condition = contains([
      "Linux/UNIX", "Linux with SQL Server Standard", "Linux with SQL Server Web", "Linux with SQL Server Enterprise",
      "SUSE Linux", "Red Hat Enterprise Linux", "RHEL with SQL Server Standard", "RHEL with SQL Server Enterprise",
      "RHEL with SQL Server Web", "RHEL with HA", "RHEL with HA and SQL Server Standard", "RHEL with HA and SQL Server Enterprise",
      "Windows", "Windows with SQL Server", "Windows with SQL Server Standard", "Windows with SQL Server Web",
      "Windows with SQL Server Enterprise",
    ], var.instance_platform)
    error_message = "instance_platform must be one of the platforms EC2 accepts for a capacity reservation."
  }
}
variable "tenancy" {
  type        = string
  default     = "default"
  description = "Whether the reserved capacity is on shared or dedicated hardware. Shared, which is EC2's default stated explicitly - dedicated is billed differently and needs the launch template to ask for it too"

  validation {
    condition     = contains(["default", "dedicated"], var.tenancy)
    error_message = "tenancy must be default or dedicated."
  }
}
variable "end_date" {
  type        = string
  default     = null
  description = <<-DESC
    When the reservation expires, in RFC 3339 form. Null makes it open-ended, which is what the _monolithic
    template created - and is the expensive choice, because a capacity reservation is billed whether or not
    anything is running in it.

    That is the thing most worth knowing about this project: destroying the node group does not stop the
    charge. Only removing the reservation does, and an open-ended one left behind after a demo keeps billing
    for a g4dn instance that is not running.
  DESC

  validation {
    condition     = var.end_date == null || can(formatdate("YYYY-MM-DD", var.end_date))
    error_message = "end_date must be an RFC 3339 timestamp such as 2026-12-31T23:59:59Z, or null for an open-ended reservation."
  }
}
variable "instance_match_criteria" {
  type        = string
  default     = "targeted"
  description = <<-DESC
    Which instances the reservation accepts. targeted, where EC2's default is open - and the difference
    matters here.

    open    - any instance of the right type in the right zone drifts into the reservation, including ones
              launched by something else entirely.
    targeted - only instances that name this reservation explicitly, which is what the node group's launch
              template does with capacity_reservation_target.

    The _monolithic template left this unset and therefore open, while its launch template used
    capacity-reservations-only with a specific target. That combination works, but it also means any other
    g4dn.xlarge in the zone could consume the one reserved slot first and leave the node group unable to
    launch.
  DESC

  validation {
    condition     = contains(["open", "targeted"], var.instance_match_criteria)
    error_message = "instance_match_criteria must be open or targeted."
  }
}
variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags on the reservation. Worth setting something: a reservation has no name of its own in the console list, so an untagged one is identifiable only by its id"

  validation {
    condition     = alltrue([for key in keys(var.tags) : length(key) > 0 && !startswith(lower(key), "aws:")])
    error_message = "tags keys must be non-empty and must not use the reserved \"aws:\" prefix."
  }
}
