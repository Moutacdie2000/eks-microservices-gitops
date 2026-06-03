# ADR 0001, GitOps via ArgoCD plutôt qu'un déploiement impératif

- **Statut** : Accepté
- **Date** : 2026-06-03
- **Décideurs** : Équipe plateforme / DevOps

## Contexte

Nous déployons quatre microservices sur Amazon EKS et devons choisir le modèle
de livraison continue (CD). Deux grandes approches s'opposent :

1. **Déploiement impératif (push)** : le pipeline CI (GitHub Actions) exécute
   directement `kubectl apply` ou `helm upgrade` contre le cluster.
2. **Déploiement déclaratif (pull / GitOps)** : un opérateur dans le cluster
   (ArgoCD) réconcilie en continu l'état réel avec l'état désiré décrit dans Git.

Les enjeux sont la sécurité des accès au cluster, l'auditabilité, la prévention
de la dérive de configuration et la simplicité des rollbacks.

## Décision

Nous adoptons **GitOps avec ArgoCD** (modèle pull) comme unique mécanisme de
déploiement. Git est la source de vérité ; la CI n'a **aucun** accès direct au
cluster Kubernetes.

## Options envisagées

### Option A, `kubectl`/`helm` depuis la CI (push)

- **Avantages** : simple à mettre en place ; pas d'outil supplémentaire à opérer ;
  déploiement immédiat et linéaire dans les logs du pipeline.
- **Inconvénients** :
  - le pipeline doit détenir des **credentials cluster** (cible d'attaque,
    surface d'exposition élevée) ;
  - **dérive de configuration** non détectée (un `kubectl edit` manuel persiste) ;
  - pas de réconciliation continue ni de garantie d'état ;
  - rollback = relancer un ancien pipeline, sans vue claire de l'état désiré.

### Option B, GitOps avec ArgoCD (pull), **retenue**

- **Avantages** :
  - **aucun credential cluster dans la CI** : ArgoCD tire depuis Git de
    l'intérieur du cluster (modèle pull, surface d'attaque réduite) ;
  - **auditabilité totale** : tout changement d'état = un commit Git tracé ;
  - **anti-dérive** (`selfHeal`) : l'état réel converge en permanence vers Git ;
  - **rollback trivial** : `git revert` puis resynchronisation ;
  - **pattern app-of-apps** : ajout d'un service = un fichier YAML committé ;
  - UI/CLI pour visualiser l'état de synchro et de santé des applications.
- **Inconvénients** :
  - un composant supplémentaire à installer et opérer (ArgoCD) ;
  - léger délai de propagation (polling/webhook) vs un apply immédiat ;
  - courbe d'apprentissage (Applications, Projects, sync policies).

### Option C, Flux CD

- Alternative GitOps crédible et équivalente sur le fond. Écartée ici au profit
  d'ArgoCD pour son **UI** pédagogique (utile en démo de portfolio) et la
  lisibilité du pattern app-of-apps.

## Conséquences

- La CI se limite à : build, test, scan, push d'image, puis **commit du bump de
  tag** dans `argocd/applications/*.yaml`. Voir `.github/workflows/ci.yml`.
- ArgoCD est configuré en `automated` + `prune` + `selfHeal`.
- Les accès humains au cluster sont réduits ; les changements passent par des PR.
- Un incident de déploiement se diagnostique via l'historique Git + l'UI ArgoCD.
