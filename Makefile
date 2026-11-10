.DEFAULT_GOAL := help
SHELL := /bin/bash
TF_DIR := infra/terraform/environments/dev
export PYTHONPATH := src
export FLASK_APP := inventory_hub.wsgi

.PHONY: help
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---------- Local development ----------

.PHONY: install
install: ## Create venv deps (run inside an activated virtualenv)
	pip install -r requirements-dev.txt
	pre-commit install

.PHONY: run
run: ## Run the app locally on SQLite with auto-reload
	mkdir -p instance
	flask db upgrade && flask seed && flask run --debug --port 8000

.PHONY: up
up: ## Run app + PostgreSQL with docker compose
	docker compose up --build

.PHONY: down
down: ## Stop docker compose and remove volumes
	docker compose down -v

.PHONY: lint
lint: ## Ruff lint + format check
	ruff check src tests
	ruff format --check src tests

.PHONY: fmt
fmt: ## Auto-format Python and Terraform
	ruff format src tests
	ruff check --fix src tests
	terraform fmt -recursive infra/terraform

.PHONY: test
test: ## Run the test suite with coverage
	pytest --cov --cov-report=term-missing

.PHONY: migration
migration: ## Create a new migration: make migration m="add supplier table"
	flask db migrate -m "$(m)"

# ---------- Infrastructure ----------

.PHONY: tf-bootstrap
tf-bootstrap: ## One-time: create the Terraform state bucket
	./scripts/bootstrap-state.sh

.PHONY: tf-init
tf-init: ## terraform init (dev)
	terraform -chdir=$(TF_DIR) init -backend-config=backend.hcl

.PHONY: tf-plan
tf-plan: ## terraform plan (dev)
	terraform -chdir=$(TF_DIR) plan

.PHONY: tf-apply
tf-apply: ## terraform apply (dev)
	terraform -chdir=$(TF_DIR) apply

.PHONY: kubeconfig
kubeconfig: ## Point kubectl at the dev cluster
	$$(terraform -chdir=$(TF_DIR) output -raw configure_kubectl)

.PHONY: deploy
deploy: ## Build, push and deploy from your workstation
	./scripts/deploy-manual.sh

.PHONY: destroy
destroy: ## Tear everything down (Kubernetes first, then Terraform)
	./scripts/destroy.sh
