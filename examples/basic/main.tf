terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "ecr" {
  source = "../../"

  repository_name = "iacbazaar/example-app"

  # Lifecycle presets: drop untagged layers after a week, keep the last 30
  # release images, and never hold more than 100 images total.
  untagged_expiry_days = 7
  max_image_count      = 100
  tagged_image_retention = [
    {
      tag_prefixes = ["v"]
      keep_count   = 30
    },
  ]

  # Placeholder principal — replace with your CI/CD or consumer account role.
  pull_principal_arns = ["arn:aws:iam::123456789012:root"]

  # Ephemeral-environment override (default keeps non-empty repos safe).
  force_delete = true

  tags = {
    Environment = "example"
    ManagedBy   = "iac-bazaar"
  }
}

output "repository_url" {
  value = module.ecr.repository_url
}

output "lifecycle_policy_json" {
  value = module.ecr.lifecycle_policy_json
}
