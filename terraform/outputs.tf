output "cluster_name" {
  description = "Nom du cluster EKS."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint HTTPS de l'API server du cluster EKS."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Version Kubernetes du plan de contrôle."
  value       = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "Certificat CA du cluster (base64) pour la configuration kubeconfig."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "ARN du provider OIDC du cluster, utilisé pour les rôles IRSA."
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "Identifiant du VPC."
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Identifiants des subnets privés (où s'exécutent les nœuds et les pods)."
  value       = module.vpc.private_subnets
}

output "ecr_repository_urls" {
  description = "URL des dépôts ECR, indexées par nom de service."
  value       = { for name, repo in module.ecr : name => repo.repository_url }
}

output "aws_lb_controller_role_arn" {
  description = "ARN du rôle IRSA de l'AWS Load Balancer Controller (à référencer dans son chart Helm)."
  value       = module.aws_lb_controller_irsa.iam_role_arn
}

output "payments_role_arn" {
  description = "ARN du rôle IRSA du service payments (à annoter sur son ServiceAccount)."
  value       = module.payments_irsa.iam_role_arn
}

output "configure_kubectl" {
  description = "Commande prête à l'emploi pour configurer kubectl sur ce cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
