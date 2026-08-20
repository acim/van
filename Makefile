.PHONY: lint test test-all test-cov update

lint:
	@golangci-lint run

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
