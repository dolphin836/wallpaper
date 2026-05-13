package handler

import (
	"bytes"
	"encoding/json"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/png"
	"log/slog"
	"net/http"
	"strconv"

	_ "github.com/gen2brain/heic"
	"github.com/go-chi/chi/v5"
	"github.com/nfnt/resize"
	"golang.org/x/crypto/bcrypt"
	_ "golang.org/x/image/webp"

	"github.com/wallpaper/backend/internal/middleware"
	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/pkg/storage"
	"github.com/wallpaper/backend/internal/repo"
)

type UserHandler struct {
	userRepo        *repo.UserRepo
	wallpaperRepo   *repo.WallpaperRepo
	interactionRepo *repo.InteractionRepo
	coinRepo        *repo.CoinRepo
	storage         *storage.Storage
}

func NewUserHandler(ur *repo.UserRepo, wr *repo.WallpaperRepo, ir *repo.InteractionRepo, cr *repo.CoinRepo, s *storage.Storage) *UserHandler {
	return &UserHandler{
		userRepo:        ur,
		wallpaperRepo:   wr,
		interactionRepo: ir,
		coinRepo:        cr,
		storage:         s,
	}
}

func (h *UserHandler) GetMe(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	user, err := h.userRepo.GetByID(r.Context(), userID)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to get current user", "error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if user == nil {
		response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
		return
	}
	response.OK(w, user)
}

func (h *UserHandler) GetProfile(w http.ResponseWriter, r *http.Request) {
	param := chi.URLParam(r, "id")
	id, err := strconv.ParseInt(param, 10, 64)
	if err != nil {
		user, lookupErr := h.userRepo.GetByUsername(r.Context(), param)
		if lookupErr != nil || user == nil {
			response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
			return
		}
		response.OK(w, user)
		return
	}

	user, err := h.userRepo.GetByID(r.Context(), id)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to get user", "error", err, "user_id", id)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if user == nil {
		response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
		return
	}
	response.OK(w, user)
}

func stripOriginalURLs(items []model.Wallpaper, ownerID int64) {
	for i := range items {
		if items[i].UserID != ownerID {
			items[i].OriginalURL = ""
		}
	}
}

type wallpaperItem struct {
	model.Wallpaper
	IsLiked      bool `json:"is_liked"`
	IsFavorited  bool `json:"is_favorited"`
	IsDownloaded bool `json:"is_downloaded"`
}

func (h *UserHandler) enrichItems(r *http.Request, items []model.Wallpaper, userID int64) []wallpaperItem {
	result := make([]wallpaperItem, len(items))
	ids := make([]int64, len(items))
	for i := range items {
		ids[i] = items[i].ID
		result[i] = wallpaperItem{Wallpaper: items[i]}
	}

	if userID > 0 && len(ids) > 0 {
		if m, err := h.interactionRepo.BatchIsLiked(r.Context(), userID, ids); err != nil {
			slog.ErrorContext(r.Context(), "batch check likes failed", "error", err)
		} else {
			for i := range result {
				result[i].IsLiked = m[result[i].ID]
			}
		}
		if m, err := h.interactionRepo.BatchIsFavorited(r.Context(), userID, ids); err != nil {
			slog.ErrorContext(r.Context(), "batch check favorites failed", "error", err)
		} else {
			for i := range result {
				result[i].IsFavorited = m[result[i].ID]
			}
		}
		if m, err := h.interactionRepo.BatchHasDownloaded(r.Context(), userID, ids); err != nil {
			slog.ErrorContext(r.Context(), "batch check downloads failed", "error", err)
		} else {
			for i := range result {
				result[i].IsDownloaded = m[result[i].ID]
			}
		}
	}

	return result
}

func (h *UserHandler) GetWallpapers(w http.ResponseWriter, r *http.Request) {
	param := chi.URLParam(r, "id")
	id, err := strconv.ParseInt(param, 10, 64)
	if err != nil {
		user, lookupErr := h.userRepo.GetByUsername(r.Context(), param)
		if lookupErr != nil || user == nil {
			response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
			return
		}
		id = user.ID
	}

	cursor, limit := parseCursorLimit(r)
	fetchLimit := limit + 1

	currentUserID := middleware.GetUserID(r.Context())
	isOwner := currentUserID == id

	opts := repo.ListOptions{
		Cursor: cursor,
		Limit:  fetchLimit,
		UserID: id,
	}
	if isOwner {
		opts.IncludeAllActive = true
	} else {
		opts.Status = model.WallpaperStatusPublished
	}

	items, err := h.wallpaperRepo.List(r.Context(), opts)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to list user wallpapers",
			"error", err, "user_id", id)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	countOpts := opts
	countOpts.Cursor = 0
	countOpts.Limit = 0
	total, err := h.wallpaperRepo.Count(r.Context(), countOpts)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to count user wallpapers", "error", err, "user_id", id)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	hasMore := len(items) == fetchLimit
	if hasMore {
		items = items[:len(items)-1]
	}

	var nextCursor int64
	if hasMore && len(items) > 0 {
		nextCursor = items[len(items)-1].ID
	}

	stripOriginalURLs(items, currentUserID)

	response.OK(w, map[string]any{
		"items":       h.enrichItems(r, items, currentUserID),
		"next_cursor": nextCursor,
		"has_more":    hasMore,
		"total":       total,
	})
}

func (h *UserHandler) GetFavorites(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	cursor, limit := parseCursorLimit(r)
	fetchLimit := limit + 1

	items, err := h.interactionRepo.ListFavorites(r.Context(), userID, cursor, fetchLimit)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to list favorites",
			"error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	total, err := h.interactionRepo.CountFavorites(r.Context(), userID)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to count favorites", "error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	hasMore := len(items) == fetchLimit
	if hasMore {
		items = items[:len(items)-1]
	}

	var nextCursor int64
	if hasMore && len(items) > 0 {
		nextCursor = items[len(items)-1].ID
	}

	stripOriginalURLs(items, userID)

	response.OK(w, map[string]any{
		"items":       h.enrichItems(r, items, userID),
		"next_cursor": nextCursor,
		"has_more":    hasMore,
		"total":       total,
	})
}

func (h *UserHandler) GetLikes(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	cursor, limit := parseCursorLimit(r)
	fetchLimit := limit + 1

	items, err := h.interactionRepo.ListLikes(r.Context(), userID, cursor, fetchLimit)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to list likes",
			"error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	total, err := h.interactionRepo.CountLikes(r.Context(), userID)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to count likes", "error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	hasMore := len(items) == fetchLimit
	if hasMore {
		items = items[:len(items)-1]
	}

	var nextCursor int64
	if hasMore && len(items) > 0 {
		nextCursor = items[len(items)-1].ID
	}

	stripOriginalURLs(items, userID)

	response.OK(w, map[string]any{
		"items":       h.enrichItems(r, items, userID),
		"next_cursor": nextCursor,
		"has_more":    hasMore,
		"total":       total,
	})
}

func (h *UserHandler) GetDownloads(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	cursor, limit := parseCursorLimit(r)
	fetchLimit := limit + 1

	// Same resolution / dynamic filter contract as /wallpapers — lets the
	// home feed and the My-Downloads list share UI affordances.
	filters := repo.DownloadFilters{
		DeviceWidth:    parseIntQuery(r, "device_width"),
		DeviceHeight:   parseIntQuery(r, "device_height"),
		DynamicOnly:    r.URL.Query().Get("dynamic_only") == "true",
		IncludeDynamic: r.URL.Query().Get("include_dynamic") == "true",
	}

	items, err := h.interactionRepo.ListDownloads(r.Context(), userID, cursor, fetchLimit, filters)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to list downloads",
			"error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	total, err := h.interactionRepo.CountDownloads(r.Context(), userID, filters)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to count downloads", "error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	hasMore := len(items) == fetchLimit
	if hasMore {
		items = items[:len(items)-1]
	}

	var nextCursor int64
	if hasMore && len(items) > 0 {
		nextCursor = items[len(items)-1].ID
	}

	stripOriginalURLs(items, userID)

	response.OK(w, map[string]any{
		"items":       h.enrichItems(r, items, userID),
		"next_cursor": nextCursor,
		"has_more":    hasMore,
		"total":       total,
	})
}

func (h *UserHandler) GetCoins(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	balance, err := h.coinRepo.GetBalance(r.Context(), userID)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to get coin balance", "error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]int64{"coins": balance})
}

func (h *UserHandler) GetCoinTransactions(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	cursor, limit := parseCursorLimit(r)
	fetchLimit := limit + 1

	items, err := h.coinRepo.ListTransactions(r.Context(), userID, cursor, fetchLimit)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to list coin transactions",
			"error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	total, err := h.coinRepo.CountTransactions(r.Context(), userID)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to count coin transactions", "error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	hasMore := len(items) == fetchLimit
	if hasMore {
		items = items[:len(items)-1]
	}

	var nextCursor int64
	if hasMore && len(items) > 0 {
		nextCursor = items[len(items)-1].ID
	}

	response.OK(w, map[string]any{
		"items":       items,
		"next_cursor": nextCursor,
		"has_more":    hasMore,
		"total":       total,
	})
}

func (h *UserHandler) UpdateProfile(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	var req struct {
		Nickname string `json:"nickname"`
		Bio      string `json:"bio"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}
	if len(req.Nickname) > 64 || len(req.Bio) > 500 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if err := h.userRepo.UpdateProfile(r.Context(), userID, req.Nickname, req.Bio); err != nil {
		slog.ErrorContext(r.Context(), "failed to update profile", "error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	user, _ := h.userRepo.GetByID(r.Context(), userID)
	response.OK(w, user)
}

const avatarSize = 256

func (h *UserHandler) UploadAvatar(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	r.Body = http.MaxBytesReader(w, r.Body, 5<<20)
	if err := r.ParseMultipartForm(5 << 20); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}
	file, _, err := r.FormFile("avatar")
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	defer file.Close()

	src, _, err := image.Decode(file)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to decode avatar image", "error", err, "user_id", userID)
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	cropped := cropCenter(src)
	resized := resize.Resize(avatarSize, avatarSize, cropped, resize.Lanczos3)

	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, resized, &jpeg.Options{Quality: 85}); err != nil {
		slog.ErrorContext(r.Context(), "failed to encode avatar", "error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	oldUser, _ := h.userRepo.GetByID(r.Context(), userID)
	if oldUser != nil && oldUser.AvatarURL != "" {
		if oldKey := h.storage.ObjectKeyFromURL(oldUser.AvatarURL); oldKey != "" {
			if delErr := h.storage.Delete(r.Context(), oldKey); delErr != nil {
				slog.WarnContext(r.Context(), "failed to delete old avatar", "error", delErr, "key", oldKey)
			}
		}
	}

	objectKey := fmt.Sprintf("avatars/%d.jpg", userID)
	if err := h.storage.Upload(r.Context(), objectKey, &buf, int64(buf.Len()), "image/jpeg"); err != nil {
		slog.ErrorContext(r.Context(), "failed to upload avatar", "error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrUploadFailed)
		return
	}

	avatarURL := h.storage.GetURL(objectKey)
	if err := h.userRepo.UpdateAvatar(r.Context(), userID, avatarURL); err != nil {
		slog.ErrorContext(r.Context(), "failed to save avatar url", "error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	response.OK(w, map[string]string{"avatar_url": avatarURL})
}

func cropCenter(src image.Image) image.Image {
	bounds := src.Bounds()
	w, h := bounds.Dx(), bounds.Dy()
	if w == h {
		return src
	}
	var rect image.Rectangle
	if w > h {
		x0 := (w - h) / 2
		rect = image.Rect(x0, 0, x0+h, h)
	} else {
		y0 := (h - w) / 2
		rect = image.Rect(0, y0, w, y0+w)
	}
	type subImager interface {
		SubImage(r image.Rectangle) image.Image
	}
	if si, ok := src.(subImager); ok {
		return si.SubImage(rect)
	}
	dst := image.NewRGBA(image.Rect(0, 0, rect.Dx(), rect.Dy()))
	for y := rect.Min.Y; y < rect.Max.Y; y++ {
		for x := rect.Min.X; x < rect.Max.X; x++ {
			dst.Set(x-rect.Min.X, y-rect.Min.Y, src.At(x, y))
		}
	}
	return dst
}

func (h *UserHandler) ChangePassword(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	var req struct {
		OldPassword string `json:"old_password"`
		NewPassword string `json:"new_password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}
	if len(req.NewPassword) < 8 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	user, err := h.userRepo.GetByIDWithHash(r.Context(), userID)
	if err != nil || user == nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.OldPassword)); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrWrongPassword)
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	if err := h.userRepo.UpdatePassword(r.Context(), userID, string(hash)); err != nil {
		slog.ErrorContext(r.Context(), "failed to update password", "error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	response.OK(w, nil)
}

func (h *UserHandler) ListUsers(w http.ResponseWriter, r *http.Request) {
	sort := r.URL.Query().Get("sort")
	page := 1
	if raw := r.URL.Query().Get("page"); raw != "" {
		if v, err := strconv.Atoi(raw); err == nil && v > 0 {
			page = v
		}
	}
	limit := 24
	if raw := r.URL.Query().Get("limit"); raw != "" {
		if v, err := strconv.Atoi(raw); err == nil && v > 0 && v <= 50 {
			limit = v
		}
	}
	offset := (page - 1) * limit

	items, total, err := h.userRepo.ListUsers(r.Context(), sort, offset, limit)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to list users", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	response.OK(w, map[string]any{
		"items": items,
		"total": total,
		"page":  page,
		"limit": limit,
	})
}

// parseIntQuery returns the named query param as an int, or 0 if missing/unparseable.
// Used for optional numeric filters (device_width, device_height, ...).
func parseIntQuery(r *http.Request, name string) int {
	raw := r.URL.Query().Get(name)
	if raw == "" {
		return 0
	}
	v, err := strconv.Atoi(raw)
	if err != nil {
		return 0
	}
	return v
}

func parseCursorLimit(r *http.Request) (int64, int) {
	var cursor int64
	if raw := r.URL.Query().Get("cursor"); raw != "" {
		v, err := strconv.ParseInt(raw, 10, 64)
		if err == nil {
			cursor = v
		}
	}

	limit := 20
	if raw := r.URL.Query().Get("limit"); raw != "" {
		if v, err := strconv.Atoi(raw); err == nil && v > 0 {
			limit = v
		}
	}
	if limit > 50 {
		limit = 50
	}

	return cursor, limit
}
