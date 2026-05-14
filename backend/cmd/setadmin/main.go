// Command setadmin toggles a user's is_admin flag from the shell. Use it to
// bootstrap the first administrator without writing raw SQL:
//
//	go run ./cmd/setadmin -username eric -on
//	go run ./cmd/setadmin -email me@x.com -off
//
// In production this runs inside the api container:
//
//	docker compose -p wallpaper exec api /bin/setadmin -username eric -on
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"os"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/model"
)

func main() {
	username := flag.String("username", "", "user's username")
	email := flag.String("email", "", "user's email (alternative to -username)")
	on := flag.Bool("on", false, "grant admin")
	off := flag.Bool("off", false, "revoke admin")
	flag.Parse()

	if *username == "" && *email == "" {
		fmt.Fprintln(os.Stderr, "usage: setadmin -username <name>|-email <addr> -on|-off")
		os.Exit(2)
	}
	if *on == *off {
		fmt.Fprintln(os.Stderr, "specify exactly one of -on or -off")
		os.Exit(2)
	}

	cfg, err := config.Load()
	if err != nil {
		slog.Error("load config failed", "error", err)
		os.Exit(1)
	}
	db, err := gorm.Open(postgres.Open(cfg.DB.DSN()), &gorm.Config{})
	if err != nil {
		slog.Error("connect db failed", "error", err)
		os.Exit(1)
	}

	ctx := context.Background()
	q := db.WithContext(ctx).Model(&model.User{}).Where("id > 0")
	if *username != "" {
		q = q.Where("username = ?", *username)
	} else {
		q = q.Where("email = ?", *email)
	}

	var user model.User
	if err := q.Select("id, username, email, is_admin").First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			fmt.Fprintln(os.Stderr, "user not found")
			os.Exit(1)
		}
		slog.Error("query user failed", "error", err)
		os.Exit(1)
	}

	want := *on
	if user.IsAdmin == want {
		fmt.Printf("noop: user %s (id=%d) is_admin already %v\n", user.Username, user.ID, want)
		return
	}
	if err := db.WithContext(ctx).Model(&model.User{}).Where("id = ?", user.ID).
		Update("is_admin", want).Error; err != nil {
		slog.Error("update failed", "error", err)
		os.Exit(1)
	}
	fmt.Printf("ok: user %s (id=%d) is_admin = %v\n", user.Username, user.ID, want)
}
