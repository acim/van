# syntax=docker/dockerfile:1.3
FROM golang:1.25.5-alpine AS builder

RUN --mount=type=cache,target=/var/cache/apk if [ "${TARGETPLATFORM}" = "linux/amd64" ]; \
    then apk add --no-cache git upx; fi

WORKDIR /app
COPY go.mod ./
RUN --mount=type=cache,target=/go/pkg/mod go mod tidy

COPY . .
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build CGO_ENABLED=0 go build -a -installsuffix cgo -ldflags='-s -w -extldflags "-static"' -o /app/van .
RUN if [ "${TARGETPLATFORM}" = "linux/amd64" ]; then upx /app/app; fi

FROM alpine:3.22.2

COPY --from=builder /app/van /usr/local/bin/

USER 65534:65534

ENTRYPOINT ["van"]
