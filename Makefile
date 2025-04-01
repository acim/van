.PHONY: lint test test-all test-cov

lint:
	@golangci-lint run --fix

test:
	@go test -race -short ./...

test-all:
	@go test -race ./...

test-cov:
	@go test -coverprofile=coverage.out ./...
	@go tool cover -func coverage.out
