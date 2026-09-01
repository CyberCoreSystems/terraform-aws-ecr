output "repository_name" {
  description = "Repository name."
  value       = aws_ecr_repository.this.name
}

output "repository_arn" {
  description = "Repository ARN."
  value       = aws_ecr_repository.this.arn
}

output "repository_url" {
  description = "Repository URL (account.dkr.ecr.region.amazonaws.com/name) — use this in image references and docker push."
  value       = aws_ecr_repository.this.repository_url
}

output "registry_id" {
  description = "Account ID of the registry holding the repository."
  value       = aws_ecr_repository.this.registry_id
}

output "lifecycle_policy_json" {
  description = "The lifecycle-policy JSON applied to the repository (null when no rules are configured)."
  value       = local.lifecycle_policy
}

output "repository_policy_json" {
  description = "The repository-policy JSON applied to the repository (null when no access grants are configured)."
  value       = try(aws_ecr_repository_policy.this[0].policy, null)
}
