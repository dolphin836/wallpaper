package worker

import (
	"fmt"
	"log/slog"

	"github.com/segmentio/kafka-go"
)

// readerErrorLogger surfaces kafka-go's internal reader errors through
// slog. Without it a reader that fails to join its consumer group — e.g.
// connecting to a just-recreated broker whose group coordinator isn't
// ready yet — stalls silently forever: that exact failure shipped on
// 2026-06-10 and held five video wallpapers in processing for 37 hours
// with zero log lines.
func readerErrorLogger(group string) kafka.LoggerFunc {
	return func(format string, args ...interface{}) {
		slog.Error("kafka reader error", "group", group, "detail", fmt.Sprintf(format, args...))
	}
}
