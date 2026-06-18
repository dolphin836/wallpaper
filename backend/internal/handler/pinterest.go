package handler

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"html/template"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/pinterest"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
)

type PinterestHandler struct {
	cfg             config.PinterestConfig
	stateSecret     string
	client          *pinterest.Client
	integrationRepo *repo.IntegrationRepo
	postRepo        *repo.PinterestPostRepo
	wallpaperRepo   *repo.WallpaperRepo
	categoryRepo    *repo.CategoryRepo
}

func NewPinterestHandler(
	cfg config.PinterestConfig,
	stateSecret string,
	integrationRepo *repo.IntegrationRepo,
	postRepo *repo.PinterestPostRepo,
	wallpaperRepo *repo.WallpaperRepo,
	categoryRepo *repo.CategoryRepo,
) *PinterestHandler {
	return &PinterestHandler{
		cfg:             cfg,
		stateSecret:     stateSecret,
		client:          pinterest.NewClient(cfg),
		integrationRepo: integrationRepo,
		postRepo:        postRepo,
		wallpaperRepo:   wallpaperRepo,
		categoryRepo:    categoryRepo,
	}
}

type pinterestStatusResponse struct {
	Configured  bool       `json:"configured"`
	Connected   bool       `json:"connected"`
	Provider    string     `json:"provider"`
	AccountID   string     `json:"account_id"`
	AccountName string     `json:"account_name"`
	Scopes      []string   `json:"scopes"`
	ExpiresAt   *time.Time `json:"expires_at"`
	RedirectURL string     `json:"redirect_url"`
}

func (h *PinterestHandler) Status(w http.ResponseWriter, r *http.Request) {
	integration, err := h.integrationRepo.GetByProvider(r.Context(), model.IntegrationProviderPinterest)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	resp := pinterestStatusResponse{
		Configured:  h.client.Configured(),
		Provider:    model.IntegrationProviderPinterest,
		RedirectURL: h.client.RedirectURL(),
		Scopes:      pinterest.DefaultScopes,
	}
	if integration != nil && integration.AccessToken != "" {
		resp.Connected = true
		resp.AccountID = integration.AccountID
		resp.AccountName = integration.AccountName
		resp.ExpiresAt = integration.ExpiresAt
		if integration.Scopes != "" {
			resp.Scopes = splitScopes(integration.Scopes)
		}
	}
	response.OK(w, resp)
}

func (h *PinterestHandler) Connect(w http.ResponseWriter, r *http.Request) {
	if !h.client.Configured() {
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}

	state, err := h.signState()
	if err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	authURL := h.client.AuthCodeURL(state)
	if r.URL.Query().Get("format") == "json" || strings.Contains(r.Header.Get("Accept"), "application/json") {
		response.OK(w, map[string]string{"auth_url": authURL})
		return
	}
	http.Redirect(w, r, authURL, http.StatusFound)
}

func (h *PinterestHandler) Callback(w http.ResponseWriter, r *http.Request) {
	if !h.client.Configured() {
		h.writeCallbackHTML(w, false, "Pinterest integration is not configured.")
		return
	}
	if errMsg := r.URL.Query().Get("error"); errMsg != "" {
		h.writeCallbackHTML(w, false, "Pinterest authorization was cancelled: "+errMsg)
		return
	}
	code := strings.TrimSpace(r.URL.Query().Get("code"))
	state := strings.TrimSpace(r.URL.Query().Get("state"))
	if code == "" || !h.verifyState(state) {
		h.writeCallbackHTML(w, false, "Pinterest authorization callback is invalid.")
		return
	}

	token, err := h.client.ExchangeCode(r.Context(), code)
	if err != nil {
		slog.Error("pinterest oauth token exchange failed", slog.String("error", err.Error()))
		h.writeCallbackHTML(w, false, "Failed to exchange Pinterest authorization code.")
		return
	}

	account, _ := h.client.GetUserAccount(r.Context(), token.AccessToken)
	accountID := ""
	accountName := ""
	metadata := "{}"
	if account != nil {
		accountID = account.Username
		accountName = account.Username
		if data, err := json.Marshal(account); err == nil {
			metadata = string(data)
		}
	}

	var expiresAt *time.Time
	if token.ExpiresIn > 0 {
		t := time.Now().Add(time.Duration(token.ExpiresIn) * time.Second)
		expiresAt = &t
	}
	integration := &model.ExternalIntegration{
		Provider:     model.IntegrationProviderPinterest,
		AccountID:    accountID,
		AccountName:  accountName,
		AccessToken:  token.AccessToken,
		RefreshToken: token.RefreshToken,
		Scopes:       token.Scope,
		TokenType:    token.TokenType,
		ExpiresAt:    expiresAt,
		Metadata:     metadata,
	}
	if integration.Scopes == "" {
		integration.Scopes = strings.Join(pinterest.DefaultScopes, ",")
	}
	if err := h.integrationRepo.Upsert(r.Context(), integration); err != nil {
		slog.Error("save pinterest integration failed", slog.String("error", err.Error()))
		h.writeCallbackHTML(w, false, "Failed to save Pinterest authorization.")
		return
	}

	h.writeCallbackHTML(w, true, "Pinterest authorization is connected.")
}

type pinterestTestPinRequest struct {
	WallpaperID int64 `json:"wallpaper_id"`
	Force       bool  `json:"force"`
}

type pinterestPinResponse struct {
	WallpaperID   int64  `json:"wallpaper_id"`
	BoardID       string `json:"board_id"`
	BoardName     string `json:"board_name"`
	PinID         string `json:"pin_id"`
	PinURL        string `json:"pin_url"`
	AlreadyPosted bool   `json:"already_posted"`
}

func (h *PinterestHandler) TestPin(w http.ResponseWriter, r *http.Request) {
	if !h.client.Configured() {
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}
	var req pinterestTestPinRequest
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&req)
	}

	wallpaper, err := h.pickWallpaper(r.Context(), req.WallpaperID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if wallpaper == nil {
		response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
		return
	}

	if !req.Force {
		existing, err := h.postRepo.GetByWallpaperID(r.Context(), wallpaper.ID)
		if err != nil {
			response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
			return
		}
		if existing != nil && existing.PinID != "" {
			response.OK(w, pinterestPinResponse{
				WallpaperID:   existing.WallpaperID,
				BoardID:       existing.BoardID,
				BoardName:     existing.BoardName,
				PinID:         existing.PinID,
				PinURL:        existing.PinURL,
				AlreadyPosted: true,
			})
			return
		}
	}

	post, err := h.pinWallpaper(r.Context(), wallpaper)
	if err != nil {
		status := http.StatusBadGateway
		ec := errcode.ErrInternal
		if apiErr, ok := pinterest.IsAPIError(err); ok {
			status = apiErr.StatusCode
			if status == http.StatusForbidden {
				ec = errcode.ErrForbidden
			} else if status >= 400 && status < 500 {
				ec = errcode.ErrBadRequest
			}
		}
		slog.Warn("pinterest pin failed", slog.String("error", err.Error()))
		response.JSON(w, status, ec, map[string]string{"error": err.Error()})
		return
	}
	response.OK(w, pinterestPinResponse{
		WallpaperID: post.WallpaperID,
		BoardID:     post.BoardID,
		BoardName:   post.BoardName,
		PinID:       post.PinID,
		PinURL:      post.PinURL,
	})
}

func (h *PinterestHandler) pinWallpaper(ctx context.Context, wallpaper *model.Wallpaper) (*model.PinterestPinPost, error) {
	integration, err := h.integrationRepo.GetByProvider(ctx, model.IntegrationProviderPinterest)
	if err != nil {
		return nil, err
	}
	if integration == nil || integration.AccessToken == "" {
		return nil, fmt.Errorf("Pinterest account is not connected")
	}
	integration, err = h.refreshIfNeeded(ctx, integration)
	if err != nil {
		return nil, err
	}

	boardName := h.boardName(ctx, wallpaper.CategoryID)
	board, err := h.ensureBoard(ctx, integration.AccessToken, boardName)
	if err != nil {
		return nil, err
	}

	imageURL := h.wallpaperImageURL(wallpaper)
	if imageURL == "" {
		return nil, fmt.Errorf("wallpaper has no public preview image")
	}

	pin, err := h.client.CreatePin(ctx, integration.AccessToken, pinterest.CreatePinRequest{
		BoardID:     board.ID,
		Title:       pinterestTitle(wallpaper),
		Description: pinterestDescription(wallpaper),
		Link:        strings.TrimRight(h.cfg.SiteURL, "/") + "/wallpaper/" + wallpaper.Slug,
		AltText:     pinterestAltText(wallpaper),
		MediaSource: pinterest.ImageMediaSource{
			SourceType: "image_url",
			URL:        imageURL,
		},
	})
	if err != nil {
		return nil, err
	}
	pinURL := pin.URL
	if pinURL == "" && pin.ID != "" {
		pinURL = "https://www.pinterest.com/pin/" + pin.ID + "/"
	}

	post := &model.PinterestPinPost{
		WallpaperID: wallpaper.ID,
		BoardID:     board.ID,
		BoardName:   board.Name,
		PinID:       pin.ID,
		PinURL:      pinURL,
		Status:      "posted",
		Message:     "Pinned from admin integration test.",
	}
	if err := h.postRepo.Upsert(ctx, post); err != nil {
		return nil, err
	}
	return post, nil
}

func (h *PinterestHandler) refreshIfNeeded(ctx context.Context, integration *model.ExternalIntegration) (*model.ExternalIntegration, error) {
	if integration.ExpiresAt == nil || time.Until(*integration.ExpiresAt) > 5*time.Minute || integration.RefreshToken == "" {
		return integration, nil
	}
	token, err := h.client.RefreshToken(ctx, integration.RefreshToken)
	if err != nil {
		return nil, err
	}
	integration.AccessToken = token.AccessToken
	if token.RefreshToken != "" {
		integration.RefreshToken = token.RefreshToken
	}
	if token.Scope != "" {
		integration.Scopes = token.Scope
	}
	if token.TokenType != "" {
		integration.TokenType = token.TokenType
	}
	if token.ExpiresIn > 0 {
		t := time.Now().Add(time.Duration(token.ExpiresIn) * time.Second)
		integration.ExpiresAt = &t
	}
	if err := h.integrationRepo.Upsert(ctx, integration); err != nil {
		return nil, err
	}
	return integration, nil
}

func (h *PinterestHandler) ensureBoard(ctx context.Context, accessToken, name string) (*pinterest.Board, error) {
	boards, err := h.client.ListBoards(ctx, accessToken)
	if err != nil {
		return nil, err
	}
	for _, board := range boards {
		if strings.EqualFold(strings.TrimSpace(board.Name), strings.TrimSpace(name)) {
			b := board
			return &b, nil
		}
	}
	return h.client.CreateBoard(ctx, accessToken, pinterest.CreateBoardRequest{
		Name:        name,
		Description: "Curated wallpapers from Wallpaper Exchange.",
		Privacy:     "PUBLIC",
	})
}

func (h *PinterestHandler) pickWallpaper(ctx context.Context, id int64) (*model.Wallpaper, error) {
	if id > 0 {
		return h.wallpaperRepo.GetByID(ctx, id)
	}
	items, err := h.wallpaperRepo.List(ctx, repo.ListOptions{Limit: 1, Sort: "newest"})
	if err != nil || len(items) == 0 {
		return nil, err
	}
	return h.wallpaperRepo.GetByID(ctx, items[0].ID)
}

func (h *PinterestHandler) boardName(ctx context.Context, categoryID int64) string {
	if categoryID <= 0 {
		return "Wallpaper Exchange"
	}
	category, err := h.categoryRepo.GetByID(ctx, categoryID)
	if err != nil || category == nil || strings.TrimSpace(category.Name) == "" {
		return "Wallpaper Exchange"
	}
	return "Wallpaper Exchange - " + category.Name
}

func (h *PinterestHandler) wallpaperImageURL(wallpaper *model.Wallpaper) string {
	for _, candidate := range []string{wallpaper.PreviewURL, wallpaper.ThumbURL, wallpaper.OriginalURL} {
		candidate = strings.TrimSpace(candidate)
		if candidate == "" {
			continue
		}
		if strings.HasPrefix(candidate, "http://") || strings.HasPrefix(candidate, "https://") {
			return candidate
		}
		if strings.HasPrefix(candidate, "/") {
			return strings.TrimRight(h.cfg.SiteURL, "/") + candidate
		}
	}
	return ""
}

func pinterestTitle(wallpaper *model.Wallpaper) string {
	title := strings.TrimSpace(wallpaper.Title)
	if title != "" {
		return truncateRunes(title, 100)
	}
	if wallpaper.Width > 0 && wallpaper.Height > 0 {
		return fmt.Sprintf("%d x %d Wallpaper", wallpaper.Width, wallpaper.Height)
	}
	return "Wallpaper Exchange"
}

func pinterestDescription(wallpaper *model.Wallpaper) string {
	parts := []string{}
	if desc := strings.TrimSpace(wallpaper.Description); desc != "" {
		parts = append(parts, desc)
	}
	if wallpaper.Width > 0 && wallpaper.Height > 0 {
		parts = append(parts, fmt.Sprintf("Download this %d x %d wallpaper on Wallpaper Exchange.", wallpaper.Width, wallpaper.Height))
	} else {
		parts = append(parts, "Download this wallpaper on Wallpaper Exchange.")
	}
	return truncateRunes(strings.Join(parts, " "), 490)
}

func pinterestAltText(wallpaper *model.Wallpaper) string {
	return truncateRunes(pinterestTitle(wallpaper), 500)
}

func truncateRunes(s string, max int) string {
	r := []rune(strings.TrimSpace(s))
	if len(r) <= max {
		return string(r)
	}
	return string(r[:max-1]) + "…"
}

func splitScopes(scopes string) []string {
	fields := strings.FieldsFunc(scopes, func(r rune) bool {
		return r == ',' || r == ' '
	})
	out := make([]string, 0, len(fields))
	for _, field := range fields {
		field = strings.TrimSpace(field)
		if field != "" {
			out = append(out, field)
		}
	}
	return out
}

type pinterestStatePayload struct {
	Exp   int64  `json:"exp"`
	Nonce string `json:"nonce"`
}

func (h *PinterestHandler) signState() (string, error) {
	nonceBytes := make([]byte, 16)
	if _, err := rand.Read(nonceBytes); err != nil {
		return "", err
	}
	payload := pinterestStatePayload{
		Exp:   time.Now().Add(10 * time.Minute).Unix(),
		Nonce: hex.EncodeToString(nonceBytes),
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	encoded := base64.RawURLEncoding.EncodeToString(data)
	return encoded + "." + h.sign(encoded), nil
}

func (h *PinterestHandler) verifyState(state string) bool {
	parts := strings.Split(state, ".")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return false
	}
	expected := h.sign(parts[0])
	if !hmac.Equal([]byte(expected), []byte(parts[1])) {
		return false
	}
	data, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return false
	}
	var payload pinterestStatePayload
	if err := json.Unmarshal(data, &payload); err != nil {
		return false
	}
	return payload.Exp >= time.Now().Unix()
}

func (h *PinterestHandler) sign(payload string) string {
	secret := h.stateSecret
	if secret == "" {
		secret = "wallpaper-pinterest-state"
	}
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(payload))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func (h *PinterestHandler) writeCallbackHTML(w http.ResponseWriter, ok bool, message string) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	status := "连接失败"
	if ok {
		status = "连接成功"
	}
	tpl := template.Must(template.New("callback").Parse(`<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Pinterest {{.Status}}</title>
  <style>
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f8f4ee; color: #2d2925; }
    main { width: min(460px, calc(100vw - 40px)); padding: 32px; border-radius: 18px; background: rgba(255,255,255,.72); border: 1px solid rgba(45,41,37,.12); box-shadow: 0 24px 70px rgba(45,41,37,.15); text-align: center; }
    h1 { margin: 0 0 12px; font-size: 24px; }
    p { margin: 0 0 24px; color: #756b61; line-height: 1.6; }
    a { color: #e46f3a; font-weight: 700; text-decoration: none; }
  </style>
</head>
<body>
  <main>
    <h1>Pinterest {{.Status}}</h1>
    <p>{{.Message}}</p>
    <a href="/admin/integrations">返回推广集成</a>
  </main>
  <script>setTimeout(function(){ window.location.href = "/admin/integrations"; }, 1400);</script>
</body>
</html>`))
	_ = tpl.Execute(w, map[string]string{
		"Status":  status,
		"Message": message,
	})
}
