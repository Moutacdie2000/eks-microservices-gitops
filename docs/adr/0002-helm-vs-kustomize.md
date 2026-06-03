# ADR 0002 — Helm plutôt que Kustomize pour empaqueter les microservices

- **Statut** : Accepté
- **Date** : 2026-06-03
- **Décideurs** : Équipe plateforme / DevOps

## Contexte

Les quatre microservices partagent une structure de déploiement quasi identique
(Deployment, Service, HPA, Ingress, NetworkPolicy, probes, contexte de sécurité).
Seules quelques valeurs changent d'un service à l'autre : image, port, ressources,
exposition Ingress, IRSA. Nous devons choisir l'outil de templating/packaging
des manifestes Kubernetes, en gardant à l'esprit l'intégration avec ArgoCD.

## Décision

Nous utilisons **Helm** avec un **chart générique unique** (`service-chart`)
paramétré par `values`, réutilisé par chaque microservice. Un chart « umbrella »
(`microservices-umbrella`) permet en option un déploiement agrégé. ArgoCD rend
les charts nativement (support Helm intégré).

## Options envisagées

### Option A — Kustomize (base + overlays)

- **Avantages** : natif `kubectl` ; pas de moteur de templating (patch YAML pur) ;
  approche déclarative appréciée pour la simplicité.
- **Inconvénients** :
  - **factorisation limitée** : difficile d'exposer une vraie API de
    configuration (valeurs nommées, conditions, boucles) sans dupliquer des
    overlays par service ;
  - pas de **versionnement/packaging** ni de notion de release ;
  - la logique conditionnelle (activer un Ingress seulement pour le frontend)
    devient verbeuse en overlays.

### Option B — Helm (chart générique paramétré) — **retenue**

- **Avantages** :
  - **un seul chart** factorise tout le boilerplate ; chaque service ne fournit
    que ses `values` (image, port, ressources, ingress, IRSA) → fort principe DRY ;
  - **conditions et boucles** (`{{- if .Values.ingress.enabled }}`, `range`)
    pour activer/désactiver proprement des ressources par service ;
  - **packaging et versionnement** (`Chart.yaml`, dépendances, releases) ;
  - **support de premier ordre dans ArgoCD** (`spec.source.helm.values`) ;
  - écosystème mature (sous-charts, umbrella, tests `helm lint`/`helm template`).
- **Inconvénients** :
  - templating Go parfois verbeux et sujet à des erreurs d'indentation YAML ;
  - une couche d'abstraction supplémentaire à maîtriser.

### Option C — Helm + Kustomize (post-rendering)

- Combinaison possible (rendre avec Helm puis patcher avec Kustomize). Écartée
  ici : complexité non justifiée pour quatre services homogènes.

## Conséquences

- Le boilerplate vit dans `charts/service-chart/templates/` ; l'ajout d'un
  service se réduit à de nouvelles `values` (dans l'Application ArgoCD ou le
  chart umbrella).
- Les déploiements sont validables hors cluster via `helm lint` et
  `helm template`, intégrables en CI.
- ArgoCD consomme directement le chart : pas d'étape de rendu intermédiaire.
- En contrepartie, l'équipe doit veiller à la rigueur de l'indentation des
  templates (helpers `nindent`, `toYaml`).
