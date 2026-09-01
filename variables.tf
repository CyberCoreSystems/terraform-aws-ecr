variable "repository_name" {
  description = "Repository name. May include namespaces (e.g. \"team/app\"). Lowercase letters, digits and single ._/- separators."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._/-][a-z0-9]+)*$", var.repository_name)) && length(var.repository_name) >= 2 && length(var.repository_name) <= 256
    error_message = "repository_name must be 2-256 characters of lowercase letters and digits, separated by single '.', '_', '/' or '-' characters."
  }
}

variable "image_tag_mutability" {
  description = "Tag mutability. IMMUTABLE (default) prevents tags from being overwritten — strongly recommended for supply-chain integrity."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be IMMUTABLE or MUTABLE."
  }
}

variable "scan_on_push" {
  description = "Run a basic vulnerability scan on every pushed image."
  type        = bool
  default     = true
}

variable "force_delete" {
  description = "Allow Terraform to destroy the repository even when it still contains images. Keep false in production; set true in ephemeral/test environments."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS key ARN for at-rest encryption. null uses AES256 (images are always encrypted either way)."
  type        = string
  default     = null
}

variable "untagged_expiry_days" {
  description = "Expire untagged images (superseded layers, failed pushes) after this many days. 0 disables the rule."
  type        = number
  default     = 14

  validation {
    condition     = var.untagged_expiry_days >= 0 && var.untagged_expiry_days <= 3650
    error_message = "untagged_expiry_days must be between 0 and 3650."
  }
}

variable "tagged_image_retention" {
  description = "Keep-last-N presets for tagged images, one rule per entry (e.g. keep the last 30 images whose tags start with \"v\")."
  type = list(object({
    description  = optional(string)
    tag_prefixes = list(string)
    keep_count   = number
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.tagged_image_retention : r.keep_count >= 1 && length(r.tag_prefixes) > 0])
    error_message = "Every tagged_image_retention entry needs keep_count >= 1 and at least one tag prefix."
  }
}

variable "max_image_count" {
  description = "Hard cap on total images in the repository (applied after the other rules). 0 disables the rule."
  type        = number
  default     = 0

  validation {
    condition     = var.max_image_count >= 0
    error_message = "max_image_count must be >= 0."
  }
}

variable "lifecycle_policy" {
  description = "Full lifecycle-policy JSON. Overrides all preset rules (untagged_expiry_days, tagged_image_retention, max_image_count) when set."
  type        = string
  default     = null
}

variable "pull_principal_arns" {
  description = "IAM principal ARNs (other accounts, roles) granted read-only pull access."
  type        = list(string)
  default     = []
}

variable "push_principal_arns" {
  description = "IAM principal ARNs granted push (and pull) access — e.g. a CI/CD role in a build account."
  type        = list(string)
  default     = []
}

variable "allow_lambda_pull" {
  description = "Allow the Lambda service to pull images for container-image functions in this account."
  type        = bool
  default     = false
}

variable "repository_policy" {
  description = "Full repository-policy JSON. Overrides pull/push/Lambda preset statements when set."
  type        = string
  default     = null
}

variable "replication_destinations" {
  description = "Cross-region replication destinations. registry_id defaults to the current account. NOTE: replication configuration is account-wide — enable it from one place only."
  type = list(object({
    region      = string
    registry_id = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for d in var.replication_destinations : can(regex("^[a-z]{2}(-[a-z0-9]+)+$", d.region))])
    error_message = "Every replication destination region must look like an AWS region (e.g. eu-west-1)."
  }
}

variable "replication_repository_filters" {
  description = "Repository-name prefix filters for replication. null (default) replicates only this repository; an explicit empty list replicates the whole registry."
  type        = list(string)
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
