package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthz(t *testing.T) {
	h := New()

	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	h.Healthz(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("expected status %d, got %d", http.StatusOK, rec.Code)
	}

	var resp map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if resp["status"] != "ok" {
		t.Errorf("expected status 'ok', got '%s'", resp["status"])
	}
}

func TestReadyz_NotReady(t *testing.T) {
	h := New()

	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	rec := httptest.NewRecorder()

	h.Readyz(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Errorf("expected status %d, got %d", http.StatusServiceUnavailable, rec.Code)
	}
}

func TestReadyz_Ready(t *testing.T) {
	h := New()
	h.SetReady(true)

	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	rec := httptest.NewRecorder()

	h.Readyz(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("expected status %d, got %d", http.StatusOK, rec.Code)
	}
}

func TestRoot(t *testing.T) {
	h := New()

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()

	h.Root(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("expected status %d, got %d", http.StatusOK, rec.Code)
	}
}

func TestHello(t *testing.T) {
	h := New()

	tests := []struct {
		name     string
		query    string
		expected string
	}{
		{"default", "", "Hello, World!"},
		{"with name", "?name=Gopher", "Hello, Gopher!"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/hello"+tt.query, nil)
			rec := httptest.NewRecorder()

			h.Hello(rec, req)

			if rec.Code != http.StatusOK {
				t.Errorf("expected status %d, got %d", http.StatusOK, rec.Code)
			}

			var resp map[string]string
			if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
				t.Fatalf("failed to decode response: %v", err)
			}

			if resp["message"] != tt.expected {
				t.Errorf("expected message '%s', got '%s'", tt.expected, resp["message"])
			}
		})
	}
}
