# Hardened ECR repository: immutable tags, scan-on-push, encrypted at rest,
# preset lifecycle rules (the JSON nobody wants to hand-write), least-privilege
# cross-account pull/push policy, and optional cross-region replication.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  create_repository_policy = var.repository_policy != null || length(var.pull_principal_arns) > 0 || length(var.push_principal_arns) > 0 || var.allow_lambda_pull

  # --------------------------------------------------------------------------
  # Lifecycle-policy presets, priority-ordered: tagged-retention rules first,
  # then untagged expiry, then the total-image cap (ECR requires the
  # tagStatus=any rule to carry the highest priority).
  # --------------------------------------------------------------------------
  tagged_rules = [
    for i, r in var.tagged_image_retention : {
      rulePriority = i + 1
      description  = coalesce(r.description, "Keep the last ${r.keep_count} images tagged ${join("/", r.tag_prefixes)}*")
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = r.tag_prefixes
        countType     = "imageCountMoreThan"
        countNumber   = r.keep_count
      }
      action = { type = "expire" }
    }
  ]

  untagged_rule = var.untagged_expiry_days > 0 ? [{
    rulePriority = length(local.tagged_rules) + 1
    description  = "Expire untagged images after ${var.untagged_expiry_days} days"
    selection = {
      tagStatus   = "untagged"
      countType   = "sinceImagePushed"
      countUnit   = "days"
      countNumber = var.untagged_expiry_days
    }
    action = { type = "expire" }
  }] : []

  cap_rule = var.max_image_count > 0 ? [{
    rulePriority = length(local.tagged_rules) + length(local.untagged_rule) + 1
    description  = "Cap total images at ${var.max_image_count}"
    selection = {
      tagStatus   = "any"
      countType   = "imageCountMoreThan"
      countNumber = var.max_image_count
    }
    action = { type = "expire" }
  }] : []

  preset_rules     = concat(local.tagged_rules, local.untagged_rule, local.cap_rule)
  lifecycle_policy = var.lifecycle_policy != null ? var.lifecycle_policy : (length(local.preset_rules) > 0 ? jsonencode({ rules = local.preset_rules }) : null)

  # Replication defaults to mirroring only this repository (null filter);
  # pass an explicit empty list to replicate the whole registry.
  replication_filters = var.replication_repository_filters == null ? [var.repository_name] : var.replication_repository_filters
}

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.kms_key_arn == null ? "AES256" : "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  count = local.lifecycle_policy == null ? 0 : 1

  repository = aws_ecr_repository.this.name
  policy     = local.lifecycle_policy
}

# ----------------------------------------------------------------------------
# Repository policy — least-privilege grants for cross-account pull/push and
# (optionally) the Lambda service for container-image functions.
# ----------------------------------------------------------------------------

data "aws_iam_policy_document" "repository" {
  count = local.create_repository_policy ? 1 : 0

  dynamic "statement" {
    for_each = length(var.pull_principal_arns) > 0 ? [1] : []
    content {
      sid    = "CrossAccountPull"
      effect = "Allow"
      actions = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
      ]

      principals {
        type        = "AWS"
        identifiers = var.pull_principal_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.push_principal_arns) > 0 ? [1] : []
    content {
      sid    = "CrossAccountPush"
      effect = "Allow"
      actions = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
      ]

      principals {
        type        = "AWS"
        identifiers = var.push_principal_arns
      }
    }
  }

  # Lambda pulls container images as the service principal, scoped to
  # functions in this account so other tenants cannot ride the grant.
  dynamic "statement" {
    for_each = var.allow_lambda_pull ? [1] : []
    content {
      sid    = "LambdaImagePull"
      effect = "Allow"
      actions = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
      ]

      principals {
        type        = "Service"
        identifiers = ["lambda.amazonaws.com"]
      }

      condition {
        test     = "StringLike"
        variable = "aws:sourceArn"
        values   = ["arn:${data.aws_partition.current.partition}:lambda:*:${data.aws_caller_identity.current.account_id}:function:*"]
      }
    }
  }
}

resource "aws_ecr_repository_policy" "this" {
  count = local.create_repository_policy ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = var.repository_policy != null ? var.repository_policy : data.aws_iam_policy_document.repository[0].json
}

# ----------------------------------------------------------------------------
# Cross-region replication. NOTE: this is a REGISTRY-level (account-wide)
# resource — AWS allows exactly one per account/region. Only enable it from a
# single module instance, or manage it centrally.
# ----------------------------------------------------------------------------

resource "aws_ecr_replication_configuration" "this" {
  count = length(var.replication_destinations) > 0 ? 1 : 0

  replication_configuration {
    rule {
      dynamic "destination" {
        for_each = var.replication_destinations
        content {
          region      = destination.value.region
          registry_id = coalesce(destination.value.registry_id, data.aws_caller_identity.current.account_id)
        }
      }

      dynamic "repository_filter" {
        for_each = local.replication_filters
        content {
          filter      = repository_filter.value
          filter_type = "PREFIX_MATCH"
        }
      }
    }
  }
}
