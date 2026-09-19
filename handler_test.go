package main

import (
	"errors"
	"html/template"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeConfig(t *testing.T, content string) string {
	t.Helper()

	path := filepath.Join(t.TempDir(), "van.json")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}

	return path
}

func TestNewHandler(t *testing.T) {
	t.Setenv("CONFIG_PATH", writeConfig(t, `{"go.acim.net/van":"https://github.com/acim/van"}`))

	h, err := newHandler()
	if err != nil {
		t.Fatalf("newHandler: %v", err)
	}

	if got, want := h.mods["go.acim.net/van"], "https://github.com/acim/van"; got != want {
		t.Errorf("mods[go.acim.net/van] = %q, want %q", got, want)
	}

	if h.t200 == nil || h.t200h == nil || h.t404 == nil {
		t.Error("templates not parsed")
	}
}

func TestNewHandlerMissingConfig(t *testing.T) {
	t.Setenv("CONFIG_PATH", filepath.Join(t.TempDir(), "missing.json"))

	_, err := newHandler()
	if !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("newHandler error = %v, want fs.ErrNotExist", err)
	}
}

func TestNewHandlerInvalidConfig(t *testing.T) {
	t.Setenv("CONFIG_PATH", writeConfig(t, `not json`))

	if _, err := newHandler(); err == nil {
		t.Fatal("newHandler error = nil, want JSON decode error")
	}
}

func TestHandle(t *testing.T) {
	t.Setenv("CONFIG_PATH", writeConfig(t, `{"go.acim.net/van":"https://github.com/acim/van"}`))

	h, err := newHandler()
	if err != nil {
		t.Fatalf("newHandler: %v", err)
	}

	tests := []struct {
		name         string
		target       string
		wantStatus   int
		wantContains []string
		wantExcludes []string
	}{
		{
			name:       "probe root",
			target:     "/",
			wantStatus: http.StatusOK,
			wantExcludes: []string{
				"<html",
			},
		},
		{
			name:       "go-get known module",
			target:     "/van?go-get=1",
			wantStatus: http.StatusOK,
			wantContains: []string{
				`<meta name="go-import" content="go.acim.net/van git https://github.com/acim/van" />`,
			},
		},
		{
			name:       "human known module",
			target:     "/van",
			wantStatus: http.StatusOK,
			wantContains: []string{
				"<h2>Module go.acim.net/van</h2>",
				`<a href="https://github.com/acim/van">Source repository</a>`,
				"https://pkg.go.dev/go.acim.net/van",
			},
			wantExcludes: []string{"go-import"},
		},
		{
			name:       "unknown module",
			target:     "/nope",
			wantStatus: http.StatusNotFound,
			wantContains: []string{
				"Module go.acim.net/nope not found.",
			},
		},
		{
			name:       "unknown module with go-get",
			target:     "/nope?go-get=1",
			wantStatus: http.StatusNotFound,
			wantContains: []string{
				"Module go.acim.net/nope not found.",
			},
			wantExcludes: []string{"go-import"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "http://go.acim.net"+tt.target, nil)
			rec := httptest.NewRecorder()

			h.handle(rec, req)

			if rec.Code != tt.wantStatus {
				t.Errorf("status = %d, want %d", rec.Code, tt.wantStatus)
			}

			body := rec.Body.String()

			for _, s := range tt.wantContains {
				if !strings.Contains(body, s) {
					t.Errorf("body missing %q:\n%s", s, body)
				}
			}

			for _, s := range tt.wantExcludes {
				if strings.Contains(body, s) {
					t.Errorf("body unexpectedly contains %q:\n%s", s, body)
				}
			}

			if tt.target != "/" {
				if got := rec.Header().Get("Content-Type"); got != "text/html" {
					t.Errorf("Content-Type = %q, want text/html", got)
				}
			}
		})
	}
}

func TestModuleName(t *testing.T) {
	tests := []struct {
		name string
		url  string
		want string
	}{
		{name: "single segment", url: "http://go.acim.net/van", want: "go.acim.net/van"},
		{name: "nested path", url: "http://go.acim.net/van/sub", want: "go.acim.net/van/sub"},
		{name: "root", url: "http://go.acim.net/", want: "go.acim.net/"},
		{name: "query ignored", url: "http://go.acim.net/van?go-get=1", want: "go.acim.net/van"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, tt.url, nil)

			if got := moduleName(req); got != tt.want {
				t.Errorf("moduleName(%s) = %q, want %q", tt.url, got, tt.want)
			}
		})
	}
}

func TestExecTemplateError(t *testing.T) {
	tmpl := template.Must(template.New("bad").Parse("{{.Missing}}"))
	rec := httptest.NewRecorder()

	exec(rec, tmpl, &data{}, http.StatusOK)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusInternalServerError)
	}

	if rec.Body.Len() != 0 {
		t.Errorf("body = %q, want empty", rec.Body.String())
	}
}
