# terraform-eks-golden-path Makefile
# すべての操作は Makefile 経由で統一

# --- Variables ---
PROJECT_NAME := terraform-eks-golden-path
ENV := dev
CLUSTER_NAME := $(PROJECT_NAME)-$(ENV)
IMAGE_REPO := ghcr.io/$(shell git config user.name | tr '[:upper:]' '[:lower:]')/$(PROJECT_NAME)
IMAGE_TAG := latest
HELM_RELEASE := golden-path-api
HELM_NAMESPACE := default

# --- Phony Targets ---
.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# =============================================================================
# Go Application
# =============================================================================
.PHONY: build test lint run
build: ## Build Go binary
	cd app && go build -o ../bin/api ./cmd/api

test: ## Run Go tests
	cd app && go test -v -race -cover ./...

lint: ## Run golangci-lint
	cd app && golangci-lint run ./...

run: ## Run application locally
	cd app && go run ./cmd/api

# =============================================================================
# Docker Image
# =============================================================================
.PHONY: image-build image-push image-load
image-build: ## Build Docker image
	docker build -t $(IMAGE_REPO):$(IMAGE_TAG) ./app

image-push: ## Push Docker image to GHCR
	docker push $(IMAGE_REPO):$(IMAGE_TAG)

image-load: image-build ## Load image to kind cluster
	kind load docker-image $(IMAGE_REPO):$(IMAGE_TAG) --name $(CLUSTER_NAME)

# =============================================================================
# kind (Local Kubernetes)
# =============================================================================
.PHONY: kind-up kind-down kind-deploy kind-undeploy kind-url kind-status kind-logs
kind-up: ## Create kind cluster with ingress-nginx
	kind create cluster --name $(CLUSTER_NAME) --config deploy/kind/kind-config.yaml
	@echo "Installing ingress-nginx..."
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
	@echo "Waiting for ingress-nginx to be ready..."
	kubectl wait --namespace ingress-nginx \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller \
		--timeout=120s

kind-down: ## Delete kind cluster
	kind delete cluster --name $(CLUSTER_NAME)

kind-deploy: image-load ## Deploy app to kind using Helm
	helm upgrade --install $(HELM_RELEASE) ./deploy/helm/golden-path-api \
		--namespace $(HELM_NAMESPACE) \
		-f ./deploy/helm/golden-path-api/values-kind.yaml \
		--set image.repository=$(IMAGE_REPO) \
		--set image.tag=$(IMAGE_TAG)

kind-undeploy: ## Undeploy app from kind
	helm uninstall $(HELM_RELEASE) --namespace $(HELM_NAMESPACE) || true

kind-url: ## Show app URL for kind
	@echo "http://localhost:80"

kind-status: ## Show kind cluster status
	@echo "=== Pods ==="
	kubectl get pods -n $(HELM_NAMESPACE)
	@echo "\n=== Services ==="
	kubectl get svc -n $(HELM_NAMESPACE)
	@echo "\n=== Ingress ==="
	kubectl get ingress -n $(HELM_NAMESPACE)

kind-logs: ## Show app logs
	kubectl logs -l app.kubernetes.io/name=golden-path-api -n $(HELM_NAMESPACE) -f

kind-grafana: ## Port-forward to Grafana
	@echo "Grafana: http://localhost:3000 (admin/prom-operator)"
	kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring

kind-prometheus: ## Port-forward to Prometheus
	@echo "Prometheus: http://localhost:9090"
	kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring

# =============================================================================
# Observability Stack (kind)
# =============================================================================
.PHONY: obs-up obs-down
obs-up: ## Install kube-prometheus-stack
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
	helm repo update
	kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
		--namespace monitoring \
		-f deploy/kind/prometheus-values.yaml \
		--wait

obs-down: ## Uninstall kube-prometheus-stack
	helm uninstall kube-prometheus-stack -n monitoring || true

# =============================================================================
# EKS (Cloud)
# =============================================================================
.PHONY: eks-plan eks-apply eks-destroy eks-kubeconfig eks-deploy eks-undeploy eks-url eks-status eks-install-lbc
eks-plan: ## Terraform plan for EKS
	cd infra/terraform/envs/dev && terraform plan

eks-apply: ## Terraform apply for EKS
	cd infra/terraform/envs/dev && terraform apply

eks-destroy: ## Terraform destroy for EKS
	cd infra/terraform/envs/dev && terraform destroy

eks-kubeconfig: ## Update kubeconfig for EKS
	aws eks update-kubeconfig --name $(CLUSTER_NAME) --region ap-northeast-1

eks-install-lbc: ## Install AWS Load Balancer Controller
	helm repo add eks https://aws.github.io/eks-charts || true
	helm repo update
	helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
		-n kube-system \
		--set clusterName=$(CLUSTER_NAME) \
		--set serviceAccount.create=false \
		--set serviceAccount.name=aws-load-balancer-controller

eks-deploy: ## Deploy app to EKS using Helm
	helm upgrade --install $(HELM_RELEASE) ./deploy/helm/golden-path-api \
		--namespace $(HELM_NAMESPACE) \
		-f ./deploy/helm/golden-path-api/values-eks.yaml \
		--set image.repository=$(IMAGE_REPO) \
		--set image.tag=$(IMAGE_TAG)

eks-undeploy: ## Undeploy app from EKS
	helm uninstall $(HELM_RELEASE) --namespace $(HELM_NAMESPACE) || true

eks-url: ## Show ALB DNS for EKS
	@kubectl get ingress $(HELM_RELEASE)-golden-path-api -n $(HELM_NAMESPACE) -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
	@echo ""

eks-status: ## Show EKS cluster status
	@echo "=== Nodes ==="
	kubectl get nodes
	@echo "\n=== Pods ==="
	kubectl get pods -n $(HELM_NAMESPACE)
	@echo "\n=== Ingress ==="
	kubectl get ingress -n $(HELM_NAMESPACE)

# =============================================================================
# Terraform
# =============================================================================
.PHONY: tf-init tf-fmt tf-validate
tf-init: ## Initialize Terraform
	cd infra/terraform/envs/dev && terraform init

tf-fmt: ## Format Terraform files
	terraform fmt -recursive infra/terraform/

tf-validate: ## Validate Terraform files
	cd infra/terraform/envs/dev && terraform validate

# =============================================================================
# CI Helpers
# =============================================================================
.PHONY: ci
ci: lint test image-build ## Run all CI checks locally
	@echo "All CI checks passed!"
