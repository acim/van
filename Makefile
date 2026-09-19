.PHONY: lint check test test-all test-cov update chart-check

chart-check:
	helm lint chart --strict
	helm lint chart --strict --values .github/deploy/van-values.yaml
	helm template van chart --namespace repo >/dev/null
	helm template van chart --namespace repo --values .github/deploy/van-values.yaml --set-string image.tag=sha-0123456 >/dev/null

lint:
	@golangci-lint run

# Mirrors the static gates of ectobit/reusable-workflows go-check.yaml in the
# same order; update both together. Run before every push, with the affected
# tests. Tests are separate because CI runs them in its own job.
check: lint
	govulncheck ./...
	go fix -diff ./...

test:
	@go test -race -short ./...

test-all:
	@go test -race ./...

test-cov:
	@go test -coverprofile=coverage.out ./...
	@go tool cover -func coverage.out

update:
	@go get -u
	@go mod tidy
