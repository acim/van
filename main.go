package main

import (
	"log"
	"net/http"
	"time"
)

const (
	idleTimeout       = 30 * time.Second
	readHeaderTimeout = 2 * time.Second
	readTimeout       = 3 * time.Second
	writeTimeout      = 5 * time.Second
)

func main() {
	handler, err := newHandler()
	if err != nil {
		log.Fatalf("create handler: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", handler.handle)

	srv := &http.Server{ //nolint:exhaustruct
		Addr:              ":8080",
		Handler:           mux,
		IdleTimeout:       idleTimeout,
		ReadHeaderTimeout: readHeaderTimeout,
		ReadTimeout:       readTimeout,
		WriteTimeout:      writeTimeout,
	}

	log.Fatal(srv.ListenAndServe())
}
