#!/usr/bin/env bash
#
# Renseigne en une commande les valeurs spécifiques au compte / à l'utilisateur
# dans les manifestes ArgoCD, les values Helm et le backend Terraform.
# Remplace les marqueurs <ACCOUNT_ID> et CHANGE_ME laissés volontairement.
#
# Usage :
#   ./scripts/configure.sh <ACCOUNT_ID> <GH_OWNER> [AWS_REGION] [STATE_PREFIX]
#
# Exemple :
#   ./scripts/configure.sh 123456789012 jordan-nm eu-west-3 shop-platform
#
set -euo pipefail

ACCOUNT_ID="${1:-}"
GH_OWNER="${2:-}"
AWS_REGION="${3:-eu-west-3}"
STATE_PREFIX="${4:-shop-platform}"

if [ -z "$ACCOUNT_ID" ] || [ -z "$GH_OWNER" ]; then
  echo "Usage : $0 <ACCOUNT_ID> <GH_OWNER> [AWS_REGION] [STATE_PREFIX]" >&2
  echo "Exemple : $0 123456789012 jordan-nm eu-west-3 shop-platform" >&2
  exit 1
fi

if ! printf '%s' "$ACCOUNT_ID" | grep -qE '^[0-9]{12}$'; then
  echo "Erreur : ACCOUNT_ID doit comporter 12 chiffres (reçu : '$ACCOUNT_ID')." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# sed -i portable (GNU vs BSD/macOS)
if sed --version >/dev/null 2>&1; then
  sedi() { sed -i "$@"; }
else
  sedi() { sed -i '' "$@"; }
fi

echo "→ Compte AWS    : $ACCOUNT_ID"
echo "→ Owner GitHub  : $GH_OWNER"
echo "→ Région        : $AWS_REGION"
echo "→ Préfixe state : $STATE_PREFIX"
echo

# 1) <ACCOUNT_ID> dans les manifestes ArgoCD + values Helm
while IFS= read -r f; do
  [ -z "$f" ] && continue
  sedi "s/<ACCOUNT_ID>/$ACCOUNT_ID/g" "$f"
  echo "  ✓ ACCOUNT_ID → ${f#"$ROOT"/}"
done < <(grep -rl '<ACCOUNT_ID>' "$ROOT/argocd" "$ROOT/charts" 2>/dev/null || true)

# 2) Propriétaire du dépôt Git dans les Applications ArgoCD
while IFS= read -r f; do
  [ -z "$f" ] && continue
  sedi "s#github.com/CHANGE_ME/#github.com/$GH_OWNER/#g" "$f"
  echo "  ✓ repoURL → ${f#"$ROOT"/}"
done < <(grep -rl 'github.com/CHANGE_ME/' "$ROOT/argocd" 2>/dev/null || true)

# 3) Backend Terraform (bucket d'état + table de verrous DynamoDB)
if [ -f "$ROOT/terraform/backend.tf" ]; then
  sedi "s/CHANGE_ME-terraform-state/$STATE_PREFIX-terraform-state/g" "$ROOT/terraform/backend.tf"
  sedi "s/CHANGE_ME-terraform-locks/$STATE_PREFIX-terraform-locks/g" "$ROOT/terraform/backend.tf"
  echo "  ✓ backend Terraform → terraform/backend.tf"
fi

# 4) Région (optionnel) — uniquement si différente de la valeur par défaut
if [ "$AWS_REGION" != "eu-west-3" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    sedi "s/eu-west-3/$AWS_REGION/g" "$f"
    echo "  ✓ région → ${f#"$ROOT"/}"
  done < <(grep -rl 'eu-west-3' "$ROOT/argocd" "$ROOT/charts" 2>/dev/null || true)
fi

echo
REMAIN="$(grep -rln 'CHANGE_ME\|<ACCOUNT_ID>' "$ROOT/argocd" "$ROOT/charts" "$ROOT/terraform" 2>/dev/null || true)"
if [ -n "$REMAIN" ]; then
  echo "⚠ Marqueurs encore présents :"
  printf '%s\n' "$REMAIN"
else
  echo "✅ Aucun marqueur restant. Étapes suivantes :"
  echo "   make tf-apply && make kubeconfig && make argocd-install && make argocd-bootstrap"
fi
