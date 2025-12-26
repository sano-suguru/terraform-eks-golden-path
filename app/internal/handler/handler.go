// Package handler は API の HTTP ハンドラーを提供する。
package handler

import (
	"encoding/json"
	"net/http"
	"sync"
	"sync/atomic"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	once            sync.Once
	requestsTotal   *prometheus.CounterVec
	requestDuration *prometheus.HistogramVec
)

func initMetrics() {
	once.Do(func() {
		requestsTotal = prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "http_requests_total",
				Help: "Total number of HTTP requests",
			},
			[]string{"method", "path", "status"},
		)
		requestDuration = prometheus.NewHistogramVec(
			prometheus.HistogramOpts{
				Name:    "http_request_duration_seconds",
				Help:    "HTTP request duration in seconds",
				Buckets: prometheus.DefBuckets,
			},
			[]string{"method", "path"},
		)
		prometheus.MustRegister(requestsTotal, requestDuration)
	})
}

// Handler はアプリケーションのハンドラーと状態を保持する。
type Handler struct {
	ready atomic.Bool
}

// New はメトリクスを初期化した新しい Handler を作成する。
func New() *Handler {
	initMetrics()
	return &Handler{}
}

// SetReady は準備状態を設定する。
func (h *Handler) SetReady(ready bool) {
	h.ready.Store(ready)
}

// Healthz は Liveness Probe リクエストを処理する。
// サーバーが生存していれば 200 OK を返す。
func (h *Handler) Healthz(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// Readyz は Readiness Probe リクエストを処理する。
// 初期化完了後のみ 200 OK を返す。
func (h *Handler) Readyz(w http.ResponseWriter, r *http.Request) {
	if !h.ready.Load() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{
			"status": "not ready",
			"reason": "initialization in progress",
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

// Metrics は Prometheus メトリクスハンドラーを返す。
func (h *Handler) Metrics() http.Handler {
	return promhttp.Handler()
}

// Root はルートパスを処理する。
func (h *Handler) Root(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"message": "Welcome to Golden Path API",
		"version": "1.0.0",
	})
}

// Hello は /hello エンドポイントを処理する。
func (h *Handler) Hello(w http.ResponseWriter, r *http.Request) {
	name := r.URL.Query().Get("name")
	if name == "" {
		name = "World"
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"message": "Hello, " + name + "!",
	})
}

// RecordRequest はリクエストメトリクスを記録する。
func (h *Handler) RecordRequest(method, path, status string, duration float64) {
	requestsTotal.WithLabelValues(method, path, status).Inc()
	requestDuration.WithLabelValues(method, path).Observe(duration)
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}
