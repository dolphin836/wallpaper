package storage

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/url"
	"strings"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/wallpaper/backend/internal/config"
)

type Storage struct {
	client    *minio.Client
	bucket    string
	publicURL string
}

func New(cfg config.MinIOConfig) (*Storage, error) {
	client, err := minio.New(cfg.Endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.AccessKey, cfg.SecretKey, ""),
		Secure: cfg.UseSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("minio client: %w", err)
	}
	return &Storage{client: client, bucket: cfg.Bucket, publicURL: cfg.PublicURL}, nil
}

func (s *Storage) EnsureBucket(ctx context.Context) error {
	exists, err := s.client.BucketExists(ctx, s.bucket)
	if err != nil {
		return fmt.Errorf("check bucket: %w", err)
	}
	if !exists {
		if err := s.client.MakeBucket(ctx, s.bucket, minio.MakeBucketOptions{}); err != nil {
			return fmt.Errorf("make bucket: %w", err)
		}
	}
	return s.ensurePublicAssetRead(ctx)
}

// ensurePublicAssetRead keeps only derived display assets anonymously
// readable. Originals and served videos stay private and are exposed through
// the short-lived media gateway in the API.
func (s *Storage) ensurePublicAssetRead(ctx context.Context) error {
	data, err := publicAssetReadPolicy(s.bucket)
	if err != nil {
		return err
	}
	if err := s.client.SetBucketPolicy(ctx, s.bucket, string(data)); err != nil {
		return fmt.Errorf("set bucket policy: %w", err)
	}
	return nil
}

func publicAssetReadPolicy(bucket string) ([]byte, error) {
	publicPrefixes := []string{"avatars", "frames", "posters", "previews", "thumbs"}
	resources := make([]string, 0, len(publicPrefixes))
	for _, prefix := range publicPrefixes {
		resources = append(resources, fmt.Sprintf("arn:aws:s3:::%s/%s/*", bucket, prefix))
	}
	policy := map[string]any{
		"Version": "2012-10-17",
		"Statement": []map[string]any{
			{
				"Effect":    "Allow",
				"Principal": map[string]string{"AWS": "*"},
				"Action":    []string{"s3:GetObject"},
				"Resource":  resources,
			},
		},
	}
	data, err := json.Marshal(policy)
	if err != nil {
		return nil, fmt.Errorf("marshal bucket policy: %w", err)
	}
	return data, nil
}

func (s *Storage) Upload(ctx context.Context, objectName string, reader io.Reader, size int64, contentType string) error {
	_, err := s.client.PutObject(ctx, s.bucket, objectName, reader, size, minio.PutObjectOptions{
		ContentType: contentType,
	})
	if err != nil {
		return fmt.Errorf("put object: %w", err)
	}
	return nil
}

func (s *Storage) GetObject(ctx context.Context, objectName string) (io.ReadCloser, error) {
	obj, err := s.client.GetObject(ctx, s.bucket, objectName, minio.GetObjectOptions{})
	if err != nil {
		return nil, fmt.Errorf("get object: %w", err)
	}
	return obj, nil
}

type ObjectInfo struct {
	Size         int64
	ContentType  string
	ETag         string
	LastModified time.Time
}

func (s *Storage) StatObject(ctx context.Context, objectName string) (ObjectInfo, error) {
	info, err := s.client.StatObject(ctx, s.bucket, objectName, minio.StatObjectOptions{})
	if err != nil {
		return ObjectInfo{}, fmt.Errorf("stat object: %w", err)
	}
	return ObjectInfo{
		Size:         info.Size,
		ContentType:  info.ContentType,
		ETag:         info.ETag,
		LastModified: info.LastModified,
	}, nil
}

func (s *Storage) GetObjectRange(ctx context.Context, objectName string, start, end int64) (io.ReadCloser, error) {
	opts := minio.GetObjectOptions{}
	if err := opts.SetRange(start, end); err != nil {
		return nil, fmt.Errorf("set object range: %w", err)
	}
	obj, err := s.client.GetObject(ctx, s.bucket, objectName, opts)
	if err != nil {
		return nil, fmt.Errorf("get object range: %w", err)
	}
	return obj, nil
}

func (s *Storage) Delete(ctx context.Context, objectName string) error {
	return s.client.RemoveObject(ctx, s.bucket, objectName, minio.RemoveObjectOptions{})
}

func (s *Storage) GetURL(objectName string) string {
	if s.publicURL != "" {
		return fmt.Sprintf("%s/%s/%s", s.publicURL, s.bucket, objectName)
	}
	return fmt.Sprintf("%s/%s/%s", s.client.EndpointURL(), s.bucket, objectName)
}

// BucketUsage breaks bucket storage down by the prefix the upload pipeline
// stamps onto each object: originals/, thumbs/, previews/, variants/, frames/.
// Anything that doesn't match (legacy keys, manual uploads) lands in Other.
type BucketUsage struct {
	OriginalsBytes int64 `json:"originals_bytes"`
	OriginalsCount int64 `json:"originals_count"`
	ThumbsBytes    int64 `json:"thumbs_bytes"`
	ThumbsCount    int64 `json:"thumbs_count"`
	PreviewsBytes  int64 `json:"previews_bytes"`
	PreviewsCount  int64 `json:"previews_count"`
	VariantsBytes  int64 `json:"variants_bytes"`
	VariantsCount  int64 `json:"variants_count"`
	FramesBytes    int64 `json:"frames_bytes"`
	FramesCount    int64 `json:"frames_count"`
	OtherBytes     int64 `json:"other_bytes"`
	OtherCount     int64 `json:"other_count"`
	TotalBytes     int64 `json:"total_bytes"`
	TotalCount     int64 `json:"total_count"`
}

// Stats walks every object in the bucket and tallies bytes per prefix. Slow
// for large buckets — callers must cache. Runs from inside the docker network
// against the internal MinIO endpoint, so a 12k-object bucket takes ~2s.
func (s *Storage) Stats(ctx context.Context) (*BucketUsage, error) {
	u := &BucketUsage{}
	objects := s.client.ListObjects(ctx, s.bucket, minio.ListObjectsOptions{Recursive: true})
	for obj := range objects {
		if obj.Err != nil {
			return nil, fmt.Errorf("list objects: %w", obj.Err)
		}
		size := obj.Size
		u.TotalBytes += size
		u.TotalCount++
		switch {
		case strings.HasPrefix(obj.Key, "originals/"):
			u.OriginalsBytes += size
			u.OriginalsCount++
		case strings.HasPrefix(obj.Key, "thumbs/"):
			u.ThumbsBytes += size
			u.ThumbsCount++
		case strings.HasPrefix(obj.Key, "previews/"):
			u.PreviewsBytes += size
			u.PreviewsCount++
		case strings.HasPrefix(obj.Key, "variants/"):
			u.VariantsBytes += size
			u.VariantsCount++
		case strings.HasPrefix(obj.Key, "frames/"):
			u.FramesBytes += size
			u.FramesCount++
		default:
			u.OtherBytes += size
			u.OtherCount++
		}
	}
	return u, nil
}

// ObjectKeyFromURL extracts the object key from a full URL produced by GetURL.
func (s *Storage) ObjectKeyFromURL(fullURL string) string {
	prefix := fmt.Sprintf("%s/%s/", s.publicURL, s.bucket)
	if after, ok := strings.CutPrefix(fullURL, prefix); ok {
		return after
	}
	if s.client != nil {
		prefix = fmt.Sprintf("%s/%s/", s.client.EndpointURL(), s.bucket)
		if after, ok := strings.CutPrefix(fullURL, prefix); ok {
			return after
		}
	}
	// Stored URLs can outlive a MINIO_PUBLIC_URL change. Fall back to the
	// stable /{bucket}/{object-key} path shape so historical rows remain
	// streamable after the public originals policy is removed.
	if parsed, err := url.Parse(fullURL); err == nil {
		marker := "/" + s.bucket + "/"
		if _, after, ok := strings.Cut(parsed.Path, marker); ok {
			if key, err := url.PathUnescape(after); err == nil {
				return key
			}
			return after
		}
	}
	return ""
}
