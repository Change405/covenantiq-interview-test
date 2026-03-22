.PHONY: kind-up kind-down build-images load-images deploy-localdev deploy-sandbox deploy-staging deploy-production smoke-localdev smoke-sandbox smoke-staging smoke-production

KIND_CLUSTER_NAME ?= local-takehome
KIND_CONFIG ?= infra/kind/kind.yaml
LOGGING_NAMESPACE ?= logging

HELM_RELEASE_A ?= service-a
HELM_RELEASE_B ?= service-b

HELM_VALUES_DIR ?= values

IMAGE_TAG ?= local

kind-up:
	kind create cluster --name "$(KIND_CLUSTER_NAME)" --config "$(KIND_CONFIG)"

kind-down:
	-kind delete cluster --name "$(KIND_CLUSTER_NAME)"

build-images:
	docker build -t "local/service-a:$(IMAGE_TAG)" ./services/service-a
	docker build -t "local/service-b:$(IMAGE_TAG)" ./services/service-b
	docker build -t "local/service-worker:$(IMAGE_TAG)" ./services/worker

load-images:
	kind load docker-image "local/service-a:$(IMAGE_TAG)" --name "$(KIND_CLUSTER_NAME)"
	kind load docker-image "local/service-b:$(IMAGE_TAG)" --name "$(KIND_CLUSTER_NAME)"
	kind load docker-image "local/service-worker:$(IMAGE_TAG)" --name "$(KIND_CLUSTER_NAME)"

deploy-%:
	./scripts/deploy.sh "$*"

smoke-%:
	./scripts/smoke_test.sh "$*"

deploy-localdev deploy-sandbox deploy-staging deploy-production: deploy-%
smoke-localdev smoke-sandbox smoke-staging smoke-production: smoke-%

