variable "aws_region" {
  description = "Région AWS où provisionner le cluster EKS et les ressources associées."
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Nom du projet, utilisé comme préfixe pour nommer et taguer les ressources."
  type        = string
  default     = "shop-platform"
}

variable "environment" {
  description = "Nom de l'environnement (dev, staging, prod). Sert de suffixe au nom du cluster."
  type        = string
  default     = "dev"
}

variable "cluster_version" {
  description = "Version Kubernetes du plan de contrôle EKS."
  type        = string
  default     = "1.30"
}

variable "vpc_cidr" {
  description = "Bloc CIDR principal du VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Liste des zones de disponibilité utilisées (3 recommandées pour la haute disponibilité)."
  type        = list(string)
  default     = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]
}

variable "node_instance_types" {
  description = "Types d'instances EC2 pour le managed node group."
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_group_min_size" {
  description = "Nombre minimal de nœuds dans le managed node group."
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Nombre maximal de nœuds (laisse de la marge pour le Cluster Autoscaler et le HPA)."
  type        = number
  default     = 5
}

variable "node_group_desired_size" {
  description = "Nombre souhaité de nœuds au démarrage."
  type        = number
  default     = 3
}

variable "capacity_type" {
  description = "Type de capacité du node group : ON_DEMAND ou SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type doit valoir ON_DEMAND ou SPOT."
  }
}

variable "ecr_repositories" {
  description = "Liste des dépôts ECR à créer (un par microservice)."
  type        = list(string)
  default     = ["api-gateway", "orders", "payments", "frontend"]
}

variable "ecr_image_tag_mutability" {
  description = "Mutabilité des tags ECR. IMMUTABLE est recommandé pour la traçabilité GitOps."
  type        = string
  default     = "IMMUTABLE"
}

variable "enable_cluster_public_endpoint" {
  description = "Active l'endpoint public de l'API server EKS (utile pour la démo ; à restreindre en prod)."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "Liste des CIDR autorisés à atteindre l'endpoint public de l'API server."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
