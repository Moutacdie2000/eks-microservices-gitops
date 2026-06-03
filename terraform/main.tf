data "aws_caller_identity" "current" {}

locals {
  cluster_name = "${var.project_name}-${var.environment}"

  # Tags exigés par les subnets pour l'intégration AWS Load Balancer Controller.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

################################################################################
# VPC — module officiel terraform-aws-modules/vpc
################################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${local.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs = var.availability_zones

  # /20 privés (≈ 4094 IP/subnet) pour les pods, /24 publics pour les NAT/ELB.
  private_subnets = [for k, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = var.environment != "prod" # 1 seul NAT hors prod pour réduire les coûts
  one_nat_gateway_per_az = var.environment == "prod"

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags  = local.public_subnet_tags
  private_subnet_tags  = local.private_subnet_tags
}

################################################################################
# EKS — module officiel terraform-aws-modules/eks
################################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access       = var.enable_cluster_public_endpoint
  cluster_endpoint_public_access_cidrs = var.public_access_cidrs
  cluster_endpoint_private_access      = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # IRSA : crée le provider OIDC permettant aux ServiceAccounts d'assumer des rôles IAM.
  enable_irsa = true

  # Donne au principal qui exécute Terraform les droits admin sur le cluster.
  enable_cluster_creator_admin_permissions = true
  authentication_mode                      = "API_AND_CONFIG_MAP"

  # Addons gérés par EKS. ebs-csi est associé à un rôle IRSA dédié.
  cluster_addons = {
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
        }
      })
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  eks_managed_node_group_defaults = {
    ami_type       = "AL2023_x86_64_STANDARD"
    instance_types = var.node_instance_types
    capacity_type  = var.capacity_type
  }

  eks_managed_node_groups = {
    default = {
      min_size     = var.node_group_min_size
      max_size     = var.node_group_max_size
      desired_size = var.node_group_desired_size

      labels = {
        role = "general"
      }

      # Tags requis par le Cluster Autoscaler pour la découverte automatique.
      tags = {
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
      }
    }
  }
}

################################################################################
# IRSA — rôles IAM associés à des ServiceAccounts Kubernetes
################################################################################

# Rôle pour le driver EBS CSI (snapshots/volumes persistants).
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name             = "${local.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# Rôle pour l'AWS Load Balancer Controller (gère les Ingress/ALB).
module "aws_lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name                              = "${local.cluster_name}-aws-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# Exemple de rôle applicatif IRSA : le service "payments" peut lire des secrets
# dans AWS Secrets Manager (préfixe restreint) — illustre le moindre privilège.
data "aws_iam_policy_document" "payments_secrets" {
  statement {
    sid    = "ReadPaymentsSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/${var.environment}/payments/*",
    ]
  }
}

module "payments_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name = "${local.cluster_name}-payments"

  role_policy_arns = {
    secrets = aws_iam_policy.payments_secrets.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["payments:payments"]
    }
  }
}

resource "aws_iam_policy" "payments_secrets" {
  name        = "${local.cluster_name}-payments-secrets"
  description = "Lecture restreinte des secrets du service payments (moindre privilège)."
  policy      = data.aws_iam_policy_document.payments_secrets.json
}

################################################################################
# ECR — un dépôt par microservice
################################################################################
module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 2.2"

  for_each = toset(var.ecr_repositories)

  repository_name = "${var.project_name}/${each.value}"

  repository_image_tag_mutability = var.ecr_image_tag_mutability
  repository_image_scan_on_push   = true
  repository_encryption_type      = "AES256"

  # Donne aux nœuds EKS le droit de tirer les images.
  repository_read_access_arns = [module.eks.eks_managed_node_groups["default"].iam_role_arn]

  # Politique de cycle de vie : ne conserver que les 10 dernières images taguées
  # et expirer les images non taguées après 7 jours.
  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Conserver les 10 dernières images taguées"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expirer les images non taguées après 7 jours"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
    ]
  })
}
