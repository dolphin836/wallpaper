// Command variantgc reclaims cold on-demand wallpaper variants. Lazy variants
// are materialized on first download (service.resolveOrGenerateVariant); this
// sweep deletes the MinIO object + DB row for any that haven't been served in
// the TTL window, so the derived/ cache stays bounded. Safe to run repeatedly
// (cron) — anything deleted regenerates on the next download.
//
// Usage:
//
//	variantgc            # delete variants cold for >30 days
//	variantgc --days 14  # custom TTL
//	variantgc --dry-run  # report what would be deleted, change nothing
package main

import (
	"context"
	"flag"
	"log"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/pkg/storage"
	"github.com/wallpaper/backend/internal/repo"
)

func main() {
	days := flag.Int("days", 30, "delete variants not downloaded in this many days")
	dryRun := flag.Bool("dry-run", false, "report only; delete nothing")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		log.Fatal("load config: ", err)
	}
	db, err := gorm.Open(postgres.Open(cfg.DB.DSN()), &gorm.Config{})
	if err != nil {
		log.Fatal("connect db: ", err)
	}
	store, err := storage.New(cfg.MinIO)
	if err != nil {
		log.Fatal("minio: ", err)
	}
	deviceRepo := repo.NewDeviceRepo(db)

	ctx := context.Background()
	cutoff := time.Now().UTC().AddDate(0, 0, -*days)
	log.Printf("reclaiming variants cold since before %s (dry-run=%v)", cutoff.Format(time.RFC3339), *dryRun)

	var deleted, failed int
	for {
		batch, err := deviceRepo.ListColdVariants(ctx, cutoff, 500)
		if err != nil {
			log.Fatal("list cold variants: ", err)
		}
		if len(batch) == 0 {
			break
		}
		for _, v := range batch {
			if *dryRun {
				log.Printf("  [dry-run] would delete variant %d (wallpaper %d, device %d) %s", v.ID, v.WallpaperID, v.DeviceID, v.URL)
				deleted++
				continue
			}
			key := store.ObjectKeyFromURL(v.URL)
			if key != "" {
				if err := store.Delete(ctx, key); err != nil {
					log.Printf("  [FAIL] delete object %s: %v", key, err)
					failed++
					continue
				}
			}
			if err := deviceRepo.DeleteVariantByID(ctx, v.ID); err != nil {
				log.Printf("  [FAIL] delete row %d: %v", v.ID, err)
				failed++
				continue
			}
			deleted++
		}
		// In dry-run the rows aren't deleted, so the same batch would repeat —
		// stop after the first page rather than loop forever.
		if *dryRun {
			break
		}
	}
	log.Printf("done. deleted=%d failed=%d", deleted, failed)
}
