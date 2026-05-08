package storage

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"strings"

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
	return s.ensurePublicRead(ctx)
}

func (s *Storage) ensurePublicRead(ctx context.Context) error {
	policy := map[string]any{
		"Version": "2012-10-17",
		"Statement": []map[string]any{
			{
				"Effect":    "Allow",
				"Principal": map[string]string{"AWS": "*"},
				"Action":    []string{"s3:GetObject"},
				"Resource":  []string{fmt.Sprintf("arn:aws:s3:::%s/*", s.bucket)},
			},
		},
	}
	data, err := json.Marshal(policy)
	if err != nil {
		return fmt.Errorf("marshal bucket policy: %w", err)
	}
	if err := s.client.SetBucketPolicy(ctx, s.bucket, string(data)); err != nil {
		return fmt.Errorf("set bucket policy: %w", err)
	}
	return nil
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

func (s *Storage) Delete(ctx context.Context, objectName string) error {
	return s.client.RemoveObject(ctx, s.bucket, objectName, minio.RemoveObjectOptions{})
}

func (s *Storage) GetURL(objectName string) string {
	if s.publicURL != "" {
		return fmt.Sprintf("%s/%s/%s", s.publicURL, s.bucket, objectName)
	}
	return fmt.Sprintf("%s/%s/%s", s.client.EndpointURL(), s.bucket, objectName)
}

// ObjectKeyFromURL extracts the object key from a full URL produced by GetURL.
func (s *Storage) ObjectKeyFromURL(fullURL string) string {
	prefix := fmt.Sprintf("%s/%s/", s.publicURL, s.bucket)
	if after, ok := strings.CutPrefix(fullURL, prefix); ok {
		return after
	}
	prefix = fmt.Sprintf("%s/%s/", s.client.EndpointURL(), s.bucket)
	if after, ok := strings.CutPrefix(fullURL, prefix); ok {
		return after
	}
	return ""
}
