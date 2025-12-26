// Package main は Golden Path API のエントリーポイント。
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/sanosuguru/terraform-eks-golden-path/app/internal/handler"
	"github.com/sanosuguru/terraform-eks-golden-path/app/internal/middleware"
)

func main() {
	// 構造化ログの設定（JSON形式）
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	// ハンドラーの作成
	h := handler.New()

	// ルーティング設定
	mux := http.NewServeMux()

	// ヘルスエンドポイント（ミドルウェアなし）
	mux.HandleFunc("GET /healthz", h.Healthz)
	mux.HandleFunc("GET /readyz", h.Readyz)

	// メトリクスエンドポイント（ノイズ回避のためログミドルウェアなし）
	mux.Handle("GET /metrics", h.Metrics())

	// アプリケーションエンドポイント（ログミドルウェア付き）
	mux.Handle("GET /", middleware.Logging(http.HandlerFunc(h.Root)))
	mux.Handle("GET /hello", middleware.Logging(http.HandlerFunc(h.Hello)))

	// サーバー作成
	port := getEnv("PORT", "8080")
	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	// サーバーを goroutine で起動
	go func() {
		slog.Info("starting server", "port", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	// Readiness Probe デモ用の初期化遅延をシミュレート
	go func() {
		time.Sleep(2 * time.Second)
		h.SetReady(true)
		slog.Info("application is ready")
	}()

	// グレースフルシャットダウン
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	slog.Info("shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		slog.Error("server shutdown error", "error", err)
	}

	slog.Info("server stopped")
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
