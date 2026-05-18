package storage

import (
	"fmt"

	"golang.org/x/sys/unix"
)

// DiskUsage describes the host filesystem the API container is running on
// (its rootfs is the host's rootfs for our overlay2-backed setup). The
// admin dashboard surfaces this so an operator can spot a near-full disk
// before the database starts refusing writes.
type DiskUsage struct {
	TotalBytes int64 `json:"total_bytes"`
	FreeBytes  int64 `json:"free_bytes"`
	UsedBytes  int64 `json:"used_bytes"`
}

// Disk returns the usage of the filesystem containing path. Pass "/" for
// the rootfs. Uses Bavail (free for unprivileged users) rather than Bfree
// because the few percent reserved for root would otherwise inflate the
// "free" number relative to what an admin would see from `df -h`.
func Disk(path string) (*DiskUsage, error) {
	var stat unix.Statfs_t
	if err := unix.Statfs(path, &stat); err != nil {
		return nil, fmt.Errorf("statfs %s: %w", path, err)
	}
	bsize := int64(stat.Bsize)
	total := int64(stat.Blocks) * bsize
	free := int64(stat.Bavail) * bsize
	return &DiskUsage{
		TotalBytes: total,
		FreeBytes:  free,
		UsedBytes:  total - free,
	}, nil
}
