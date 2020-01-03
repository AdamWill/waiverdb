# Use podman-compose by default if available.
ifeq (, $(shell which podman-compose))
    COMPOSE := docker-compose
    PODMAN := docker
else
    COMPOSE := podman-compose
    PODMAN := podman
endif

BROWSER := xdg-open
SERVICE := dev
TEST_REQUIREMENTS := test-requirements.txt

PYTHON := python3
PIP := $(PYTHON) -m pip
PYTEST := $(PYTHON) -m pytest --color=yes
FLAKE8 := $(PYTHON) -m flake8
PYLINT := $(PYTHON) -m pylint

PYTEST_ARGS := tests functional-tests

all: help

help:
	@echo 'Usage:'
	@echo
	@echo '  make up - starts containers in docker-compose environment'
	@echo
	@echo '  make down - stops containers in docker-compose environment'
	@echo
	@echo '  make build - builds container images for docker-compose environment'
	@echo
	@echo '  make recreate - recreates containers for docker-compose environment'
	@echo
	@echo '  make exec [CMD=".."] - executes command in dev container'
	@echo
	@echo '  make sudo [CMD=".."] - executes command in dev container under root user'
	@echo
	@echo '  make pytest [ARGS=".."] - executes pytest with given arguments in dev container'
	@echo
	@echo '  make flake8 - executes flake8 in dev container'
	@echo
	@echo '  make pylint - executes pylint in dev container'
	@echo
	@echo '  make test - alias for "make pytest flake8 pylint"'
	@echo
	@echo '  make coverage [ARGS=".."] - generates and shows test code coverage'
	@echo
	@echo 'Variables:'
	@echo
	@echo '  COMPOSE=docker-compose|podman-compose'
	@echo '    - docker-compose or podman-compose command'
	@echo '      (default is "podman-compose" if available)'
	@echo
	@echo '  PODMAN=docker|podman'
	@echo '    - docker or podman command'
	@echo '      (default is "podman" if "podman-compose" is available)'
	@echo
	@echo '  SERVICE={dev|waiverdb-db}'
	@echo '    - service for which to run `make exec` and similar (default is "dev")'
	@echo '      Example: make exec SERVICE=waiverdb-db CMD=flake8'

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

build:
	$(COMPOSE) build

recreate:
	$(COMPOSE) up -d --force-recreate

exec:
	$(PODMAN) exec waiverdb_$(SERVICE)_1 bash -c '$(CMD)'

sudo:
	$(PODMAN) exec -u root waiverdb_$(SERVICE)_1 bash -c '$(CMD)'

test: test_requirements pytest flake8 pylint

test_requirements:
	$(MAKE) exec CMD="$(PIP) install --user -r $(TEST_REQUIREMENTS)"

pytest:
	$(MAKE) exec \
	    CMD="COVERAGE_FILE=/home/dev/.coverage-$(SERVICE) $(PYTEST) $(if $(ARGS),$(ARGS),$(PYTEST_ARGS))"

flake8:
	$(MAKE) exec CMD="$(PIP) install --user flake8 && $(FLAKE8) waiverdb"

pylint:
	$(MAKE) exec CMD="$(PIP) install --user pylint && $(PYLINT) waiverdb"

coverage:
	$(MAKE) exec CMD="$(PIP) install --user pytest-cov"
	$(MAKE) pytest ARGS="--cov-config .coveragerc --cov=waiverdb --cov-report html:/home/dev/htmlcov-$(SERVICE) $(ARGS)"
	$(BROWSER) docker/home/htmlcov-$(SERVICE)/index.html
