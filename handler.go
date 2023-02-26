package main

import (
	"bytes"
	"embed"
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

//go:embed templates/*
var templates embed.FS

type handler struct {
	mods  map[string]string
	t200  *template.Template
	t200h *template.Template
	t404  *template.Template
}

func newHandler() (*handler, error) {
	cfgPath := os.Getenv("CONFIG_PATH")
	if cfgPath == "" {
		cfgPath = "/usr/local/etc/van.json"
	}

	data, err := os.ReadFile(cfgPath)
	if err != nil {
		return nil, fmt.Errorf("read config file %s: %w", cfgPath, err)
	}

	var mods map[string]string

	if err := json.Unmarshal(data, &mods); err != nil {
		return nil, fmt.Errorf("json decode: %w", err)
	}

	return &handler{
		mods:  mods,
		t200:  template.Must(template.ParseFS(templates, "templates/200.html")),
		t200h: template.Must(template.ParseFS(templates, "templates/200_human.html")),
		t404:  template.Must(template.ParseFS(templates, "templates/404.html")),
	}, nil
}

func (h *handler) handle(res http.ResponseWriter, req *http.Request) {
	// Handle liveness and readiness probes.
	if req.URL.Path == "/" {
		return
	}

	res.Header().Set("Content-Type", "text/html")

	moduleName := moduleName(req)

	if _, ok := h.mods[moduleName]; !ok {
		exec(res, h.t404, &data{ //nolint:exhaustruct
			ModuleName: moduleName,
		}, http.StatusNotFound)

		return
	}

	goGet := req.URL.Query().Get("go-get") == "1"
	targetRepository := h.mods[moduleName]

	if goGet {
		exec(res, h.t200, &data{
			ModuleName:       moduleName,
			TargetRepository: targetRepository,
		}, http.StatusOK)

		return
	}

	exec(res, h.t200h, &data{
		ModuleName:       moduleName,
		TargetRepository: targetRepository,
	}, http.StatusOK)
}

func exec(res http.ResponseWriter, t *template.Template, data any, statusCode int) {
	var body bytes.Buffer

	if err := t.Execute(&body, data); err != nil {
		log.Printf("execute template: %v", err)
		res.WriteHeader(http.StatusInternalServerError)

		return
	}

	res.WriteHeader(statusCode)
	io.Copy(res, &body) //nolint:errcheck
}

func moduleName(req *http.Request) string {
	return fmt.Sprintf("%s/%s", req.Host, strings.TrimPrefix(req.URL.Path, "/"))
}

type data struct {
	ModuleName       string
	TargetRepository string
}
