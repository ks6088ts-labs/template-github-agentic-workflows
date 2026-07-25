# Environment variables
# Load variables from a local .env file if it exists (see .env.template).
# The .env file is ignored by git. Variables are exported so they are
# available to recipe shells (e.g. $$COPILOT_GITHUB_TOKEN).
ifneq (,$(wildcard .env))
include .env
export
endif

# Git
GIT_REVISION ?= $(shell git rev-parse --short HEAD)
GIT_TAG ?= $(shell git describe --tags --abbrev=0 --always | sed -e s/v//g)

# GitHub Agentic Workflows
# https://docs.github.com/en/copilot/how-tos/github-agentic-workflows/quickstart
GH_AUTH_SCOPES ?= repo,workflow

.PHONY: help
help:
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
.DEFAULT_GOAL := help

.PHONY: info
info: ## show information
	@echo "GIT_REVISION: $(GIT_REVISION)"
	@echo "GIT_TAG: $(GIT_TAG)"

.PHONY: install-deps-dev
install-deps-dev: ## install dependencies for development (GitHub CLI, gh-aw extension)
	@which gh > /dev/null 2>&1 || { echo "gh (GitHub CLI) is not installed. Please install it by following the instructions at https://github.com/cli/cli#installation"; exit 1; }
	@gh extension list | grep -q gh-aw || gh extension install github/gh-aw

.PHONY: auth-login
auth-login: ## authenticate GitHub CLI (gh auth login)
	gh auth login --scopes $(GH_AUTH_SCOPES)

.PHONY: set-secret-github-copilot-token
set-secret-github-copilot-token: ## set COPILOT_GITHUB_TOKEN repository secret from the environment variable
	@if [ -z "$$COPILOT_GITHUB_TOKEN" ]; then echo "COPILOT_GITHUB_TOKEN is not set"; exit 1; fi
	@gh secret set COPILOT_GITHUB_TOKEN --body "$$COPILOT_GITHUB_TOKEN"

.PHONY: compile
compile: ## compile agentic workflows into .github/workflows/*.lock.yml
	gh aw compile

.PHONY: validate
validate: ## validate agentic workflows without generating lock files (non-destructive)
	@if ls .github/workflows/*.md >/dev/null 2>&1; then \
		gh aw validate; \
	else \
		echo "no agentic workflow markdown files; skipping validation"; \
	fi

.PHONY: lint
lint: ## lint compiled .lock.yml workflows with actionlint
	@if ls .github/workflows/*.lock.yml >/dev/null 2>&1; then \
		gh aw lint; \
	else \
		echo "no .lock.yml files; skipping lint"; \
	fi

.PHONY: ci-test
ci-test: install-deps-dev info validate lint ## run CI checks (install deps, validate and lint workflows)

.PHONY: run
run: ## run an agentic workflow (usage: make run WORKFLOW=daily-repo-status)
	gh aw run $(WORKFLOW)
