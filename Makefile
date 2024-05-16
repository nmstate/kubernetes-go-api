.ONESHELL: # Applies to every targets in the file!
.SHELLFLAGS += -e

SHELL := /bin/bash
OUTPUT_DIR=${CURDIR}/.output

NMSTATE_VERSION ?= 2.2.31
NMSTATE_REPO ?= https://github.com/nmstate/nmstate
NMSTATE_SOURCE_TARBALL_URL ?= https://github.com/nmstate/nmstate/archive/refs/tags/v${NMSTATE_VERSION}.tar.gz
export NMSTATE_SOURCE_INSTALL_DIR ?= ${OUTPUT_DIR}/nmstate-${NMSTATE_VERSION}
export NMSTATE_E2E_DUMP ?= ${OUTPUT_DIR}/nmstate-${NMSTATE_VERSION}-e2e-dump

GOLANGCI_LINT_VERSION ?= v1.52.2
CONTROLLER_GEN_VERSION ?= v0.14.0 

GO_HEADER=${CURDIR}/hack/boilerplate.go.txt
GO_GENERATE_OUTPUT=v2/
GO_JUNIT_REPORT=$(shell go env GOPATH)/bin/go-junit-report -set-exit-code

${GO_JUNIT_REPORT}:
	go install github.com/jstemmer/go-junit-report/v2@latest

${NMSTATE_E2E_DUMP}:
	hack/download-nmstate-e2e-assets.sh v${NMSTATE_VERSION} ${NMSTATE_SOURCE_INSTALL_DIR} ${NMSTATE_E2E_DUMP}

${NMSTATE_SOURCE_INSTALL_DIR}: 
	mkdir -p ${NMSTATE_SOURCE_INSTALL_DIR}
	git clone ${NMSTATE_REPO} -b v${NMSTATE_VERSION} ${NMSTATE_SOURCE_INSTALL_DIR}

.PHONY: test-api
test-api: generate ${NMSTATE_E2E_DUMP} ${GO_JUNIT_REPORT}
	cd test/api
	go test 2>&1 | $(GO_JUNIT_REPORT) -set-exit-code -iocopy -out $(OUTPUT_DIR)/junit.api.xml

test-crd: generate ${NMSTATE_E2E_DUMP} ${GO_JUNIT_REPORT}
	cd test/crd
	GOFLAGS=-mod=mod go run sigs.k8s.io/controller-tools/cmd/controller-gen@${CONTROLLER_GEN_VERSION} object:headerFile="${GO_HEADER}" paths="."
	GOFLAGS=-mod=mod go run sigs.k8s.io/controller-tools/cmd/controller-gen@${CONTROLLER_GEN_VERSION} crd paths="." output:crd:artifacts:config=.
	go test 2>&1 | $(GO_JUNIT_REPORT) -set-exit-code -iocopy -out $(OUTPUT_DIR)/junit.crd.xml

test: test-api test-crd

.PHONY: generate
generate: ${NMSTATE_SOURCE_INSTALL_DIR} 
	cargo run -- --input-dir=${NMSTATE_SOURCE_INSTALL_DIR}/rust/src/lib --output-file=${CURDIR}/v2/zz_generated.types.go --header-file=${GO_HEADER}
	GOFLAGS=-mod=mod go run sigs.k8s.io/controller-tools/cmd/controller-gen@${CONTROLLER_GEN_VERSION} object:headerFile="${GO_HEADER}" paths="${CURDIR}/v2"

.PHONY: lint
lint: generate
	cd ${GO_GENERATE_OUTPUT}
	go run github.com/golangci/golangci-lint/cmd/golangci-lint@${GOLANGCI_LINT_VERSION} run
