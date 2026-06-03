# Makefile — orchestration du cycle de vie du projet EKS / GitOps.
#
# Variables surchargeables : make tf-apply AWS_REGION=eu-west-1 CLUSTER_NAME=...

AWS_REGION   ?= eu-west-3
CLUSTER_NAME ?= shop-platform-dev
ARGOCD_NS    ?= argocd
TF_DIR       := terraform
BASE_URL     ?= http://localhost:8080
ACCOUNT_ID   ?=
GH_OWNER     ?=

.DEFAULT_GOAL := help

.PHONY: help
help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Configuration (à lancer une fois, avant le déploiement)
# ---------------------------------------------------------------------------
.PHONY: configure
configure: ## Renseigne ACCOUNT_ID/GH_OWNER dans les manifestes (ACCOUNT_ID=.. GH_OWNER=..)
	./scripts/configure.sh "$(ACCOUNT_ID)" "$(GH_OWNER)" "$(AWS_REGION)"

# ---------------------------------------------------------------------------
# Infrastructure (Terraform)
# ---------------------------------------------------------------------------
.PHONY: tf-init
tf-init: ## Initialise Terraform (backend + modules)
	cd $(TF_DIR) && terraform init

.PHONY: tf-plan
tf-plan: ## Affiche le plan Terraform
	cd $(TF_DIR) && terraform plan

.PHONY: tf-apply
tf-apply: ## Provisionne le VPC, EKS, IRSA et ECR
	cd $(TF_DIR) && terraform apply

.PHONY: kubeconfig
kubeconfig: ## Configure kubectl pour le cluster EKS
	aws eks update-kubeconfig --region $(AWS_REGION) --name $(CLUSTER_NAME)
	kubectl get nodes

# ---------------------------------------------------------------------------
# GitOps (ArgoCD)
# ---------------------------------------------------------------------------
.PHONY: argocd-install
argocd-install: ## Installe ArgoCD dans le cluster (namespace argocd)
	kubectl create namespace $(ARGOCD_NS) --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n $(ARGOCD_NS) \
		-f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	kubectl -n $(ARGOCD_NS) rollout status deploy/argocd-server --timeout=300s

.PHONY: argocd-password
argocd-password: ## Affiche le mot de passe admin initial d'ArgoCD
	kubectl -n $(ARGOCD_NS) get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d; echo

.PHONY: argocd-bootstrap
argocd-bootstrap: ## Applique l'AppProject + l'app-of-apps (démarre le GitOps)
	kubectl apply -f argocd/projects.yaml
	kubectl apply -f argocd/app-of-apps.yaml
	@echo "app-of-apps appliquée : ArgoCD va synchroniser les microservices."

.PHONY: argocd-ui
argocd-ui: ## Ouvre l'UI ArgoCD via port-forward (https://localhost:8081)
	kubectl -n $(ARGOCD_NS) port-forward svc/argocd-server 8081:443

# ---------------------------------------------------------------------------
# Tests & charge
# ---------------------------------------------------------------------------
.PHONY: load-test
load-test: ## Lance le test de charge k6 (démontre le HPA)
	BASE_URL=$(BASE_URL) k6 run k6/load-test.js

.PHONY: watch-hpa
watch-hpa: ## Observe les HPA en temps réel pendant le test de charge
	kubectl get hpa -A -w

# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------
.PHONY: destroy
destroy: ## Détruit toute l'infrastructure AWS (irréversible !)
	@echo "ATTENTION : suppression d'EKS, du VPC, des NAT et des dépôts ECR."
	cd $(TF_DIR) && terraform destroy
