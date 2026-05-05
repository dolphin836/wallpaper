package middleware

import (
	"log/slog"
	"net/http"
	"time"
)

type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

func Logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

		next.ServeHTTP(rw, r)

		slog.InfoContext(r.Context(), "http request",
			"method", r.Method,
			"uri", r.RequestURI,
			"status", rw.statusCode,
			"cost_ms", time.Since(start).Milliseconds(),
			"ip", r.RemoteAddr,
		)
	})
}
