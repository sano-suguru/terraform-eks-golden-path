// Package middleware は HTTP ミドルウェア関数を提供する。
package middleware

import (
	"log/slog"
	"net/http"
	"time"
)

// responseWriter は http.ResponseWriter をラップしてステータスコードをキャプチャする。
type responseWriter struct {
	http.ResponseWriter
	status int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.status = code
	rw.ResponseWriter.WriteHeader(code)
}

// Logging は HTTP リクエストをログ出力するミドルウェアを返す。
func Logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		// ステータスをキャプチャするため ResponseWriter をラップ
		wrapped := &responseWriter{
			ResponseWriter: w,
			status:         http.StatusOK,
		}

		next.ServeHTTP(wrapped, r)

		latency := time.Since(start)

		// 必須フィールドを含む構造化ログ
		slog.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", wrapped.status,
			"latency_ms", latency.Milliseconds(),
			"remote_addr", r.RemoteAddr,
			"user_agent", r.UserAgent(),
		)
	})
}
