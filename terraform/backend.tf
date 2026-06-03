# Backend S3 pour l'état Terraform distant + verrouillage DynamoDB.
#
# Pré-requis (à provisionner une seule fois, hors de ce module) :
#   - un bucket S3 versionné et chiffré
#   - une table DynamoDB avec une clé de partition "LockID" (type String)
#
# Les valeurs ci-dessous sont volontairement génériques : surchargez-les
# via `terraform init -backend-config=...` ou un fichier backend.hcl,
# afin de ne pas committer de noms de ressources réels.
terraform {
  backend "s3" {
    bucket         = "CHANGE_ME-terraform-state"
    key            = "eks-microservices-gitops/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "CHANGE_ME-terraform-locks"
    encrypt        = true
  }
}
