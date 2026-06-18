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
	"strconv"
	"strings"
	"time"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/reddit"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
)

type RedditHandler struct {
	cfg             config.RedditConfig
	stateSecret     string
	client          *reddit.Client
	integrationRepo *repo.IntegrationRepo
	postRepo        *repo.RedditPostRepo
	collectionRepo  *repo.CollectionRepo
	weeklyRepo      *repo.WeeklyPickRepo
}

func NewRedditHandler(
	cfg config.RedditConfig,
	stateSecret string,
	integrationRepo *repo.IntegrationRepo,
	postRepo *repo.RedditPostRepo,
	collectionRepo *repo.CollectionRepo,
	weeklyRepo *repo.WeeklyPickRepo,
) *RedditHandler {
	return &RedditHandler{
		cfg:             cfg,
		stateSecret:     stateSecret,
		client:          reddit.NewClient(cfg),
		integrationRepo: integrationRepo,
		postRepo:        postRepo,
		collectionRepo:  collectionRepo,
		weeklyRepo:      weeklyRepo,
	}
}

type redditStatusResponse struct {
	Configured       bool       `json:"configured"`
	Connected        bool       `json:"connected"`
	Provider         string     `json:"provider"`
	AccountID        string     `json:"account_id"`
	AccountName      string     `json:"account_name"`
	Scopes           []string   `json:"scopes"`
	ExpiresAt        *time.Time `json:"expires_at"`
	RedirectURL      string     `json:"redirect_url"`
	DefaultSubreddit string     `json:"default_subreddit"`
}

func (h *RedditHandler) Status(w http.ResponseWriter, r *http.Request) {
	integration, err := h.integrationRepo.GetByProvider(r.Context(), model.IntegrationProviderReddit)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	resp := redditStatusResponse{
		Configured:       h.client.Configured(),
		Provider:         model.IntegrationProviderReddit,
		RedirectURL:      h.client.RedirectURL(),
		Scopes:           reddit.DefaultScopes,
		DefaultSubreddit: h.defaultSubreddit(),
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

func (h *RedditHandler) Connect(w http.ResponseWriter, r *http.Request) {
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

func (h *RedditHandler) Callback(w http.ResponseWriter, r *http.Request) {
	if !h.client.Configured() {
		h.writeCallbackHTML(w, false, "Reddit integration is not configured.")
		return
	}
	if errMsg := r.URL.Query().Get("error"); errMsg != "" {
		h.writeCallbackHTML(w, false, "Reddit authorization was cancelled: "+errMsg)
		return
	}
	code := strings.TrimSpace(r.URL.Query().Get("code"))
	state := strings.TrimSpace(r.URL.Query().Get("state"))
	if code == "" || !h.verifyState(state) {
		h.writeCallbackHTML(w, false, "Reddit authorization callback is invalid.")
		return
	}

	token, err := h.client.ExchangeCode(r.Context(), code)
	if err != nil {
		slog.Error("reddit oauth token exchange failed", slog.String("error", err.Error()))
		h.writeCallbackHTML(w, false, "Failed to exchange Reddit authorization code.")
		return
	}

	account, _ := h.client.GetMe(r.Context(), token.AccessToken)
	accountID := ""
	accountName := ""
	metadata := "{}"
	if account != nil {
		accountID = account.ID
		accountName = account.Name
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
		Provider:     model.IntegrationProviderReddit,
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
		integration.Scopes = strings.Join(reddit.DefaultScopes, ",")
	}
	if err := h.integrationRepo.Upsert(r.Context(), integration); err != nil {
		slog.Error("save reddit integration failed", slog.String("error", err.Error()))
		h.writeCallbackHTML(w, false, "Failed to save Reddit authorization.")
		return
	}

	h.writeCallbackHTML(w, true, "Reddit authorization is connected.")
}

type redditWeeklyPostRequest struct {
	Year      int16  `json:"year"`
	Week      int16  `json:"week"`
	Subreddit string `json:"subreddit"`
	Title     string `json:"title"`
	Text      string `json:"text"`
	Force     bool   `json:"force"`
}

type redditCollectionSummary struct {
	ID             int64  `json:"id"`
	Slug           string `json:"slug"`
	Title          string `json:"title"`
	Description    string `json:"description"`
	CoverURL       string `json:"cover_url"`
	WallpaperCount int    `json:"wallpaper_count"`
}

type redditPostWallpaper struct {
	ID         int64  `json:"id"`
	Slug       string `json:"slug"`
	Title      string `json:"title"`
	ThumbURL   string `json:"thumb_url"`
	PreviewURL string `json:"preview_url"`
	Width      int    `json:"width"`
	Height     int    `json:"height"`
}

type redditWeeklyPreviewResponse struct {
	Year          int16                    `json:"year"`
	Week          int16                    `json:"week"`
	Source        string                   `json:"source"`
	Subreddit     string                   `json:"subreddit"`
	Title         string                   `json:"title"`
	Text          string                   `json:"text"`
	Collection    *redditCollectionSummary `json:"collection,omitempty"`
	Wallpapers    []redditPostWallpaper    `json:"wallpapers"`
	AlreadyPosted bool                     `json:"already_posted"`
	ExistingPost  *redditWeeklyPostResult  `json:"existing_post,omitempty"`
}

type redditWeeklyPostResult struct {
	Year          int16  `json:"year"`
	Week          int16  `json:"week"`
	Subreddit     string `json:"subreddit"`
	PostID        string `json:"post_id"`
	PostURL       string `json:"post_url"`
	AlreadyPosted bool   `json:"already_posted"`
}

type redditWeeklyDraft struct {
	Year       int16
	Week       int16
	Source     string
	Subreddit  string
	Title      string
	Text       string
	Collection *model.Collection
	Wallpapers []model.Wallpaper
}

func (h *RedditHandler) WeeklyPreview(w http.ResponseWriter, r *http.Request) {
	year, week := parseYearWeek(r)
	draft, err := h.buildWeeklyDraft(r.Context(), year, week, r.URL.Query().Get("subreddit"), "", "")
	if err != nil {
		slog.ErrorContext(r.Context(), "reddit weekly preview failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if draft == nil {
		response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
		return
	}

	existing, err := h.postRepo.GetByWeek(r.Context(), draft.Year, draft.Week)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, h.previewResponse(draft, existing))
}

func (h *RedditHandler) PostWeekly(w http.ResponseWriter, r *http.Request) {
	if !h.client.Configured() {
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}
	var req redditWeeklyPostRequest
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&req)
	}
	draft, err := h.buildWeeklyDraft(r.Context(), req.Year, req.Week, req.Subreddit, req.Title, req.Text)
	if err != nil {
		slog.ErrorContext(r.Context(), "reddit weekly draft failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if draft == nil {
		response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
		return
	}
	if draft.Subreddit == "" {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	existing, err := h.postRepo.GetByWeek(r.Context(), draft.Year, draft.Week)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if existing != nil && existing.PostID != "" && !req.Force {
		response.OK(w, redditWeeklyPostResult{
			Year:          existing.Year,
			Week:          existing.Week,
			Subreddit:     existing.Subreddit,
			PostID:        existing.PostID,
			PostURL:       existing.PostURL,
			AlreadyPosted: true,
		})
		return
	}

	integration, err := h.integrationRepo.GetByProvider(r.Context(), model.IntegrationProviderReddit)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if integration == nil || integration.AccessToken == "" {
		response.JSON(w, http.StatusBadRequest, errcode.ErrBadRequest, map[string]string{"error": "Reddit account is not connected"})
		return
	}
	integration, err = h.refreshIfNeeded(r.Context(), integration)
	if err != nil {
		h.writeRedditAPIError(w, err)
		return
	}

	submit, err := h.client.Submit(r.Context(), integration.AccessToken, reddit.SubmitRequest{
		Subreddit:   draft.Subreddit,
		Kind:        "self",
		Title:       draft.Title,
		Text:        draft.Text,
		SendReplies: true,
	})
	if err != nil {
		h.writeRedditAPIError(w, err)
		return
	}

	postURL := redditPostURL(submit)
	post := &model.RedditWeeklyPost{
		Year:         draft.Year,
		Week:         draft.Week,
		CollectionID: draftCollectionID(draft),
		Subreddit:    draft.Subreddit,
		PostID:       submit.ID,
		PostURL:      postURL,
		Title:        draft.Title,
		Body:         draft.Text,
		Status:       "posted",
		Message:      "Posted from admin weekly Reddit promotion.",
	}
	if err := h.postRepo.Upsert(r.Context(), post); err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	response.OK(w, redditWeeklyPostResult{
		Year:      post.Year,
		Week:      post.Week,
		Subreddit: post.Subreddit,
		PostID:    post.PostID,
		PostURL:   post.PostURL,
	})
}

func (h *RedditHandler) buildWeeklyDraft(ctx context.Context, year, week int16, subreddit, title, text string) (*redditWeeklyDraft, error) {
	draft := &redditWeeklyDraft{
		Subreddit: normalizeSubreddit(firstNonEmpty(subreddit, h.defaultSubreddit())),
	}

	col, err := h.resolveThemeCollection(ctx, year, week)
	if err != nil {
		return nil, err
	}
	if col != nil {
		draft.Year = col.Year
		draft.Week = col.Week
		draft.Source = "collection"
		draft.Collection = col
		wallpapers, err := h.collectionRepo.ListWallpapers(ctx, col.ID, 0, 10, repo.WallpaperExclusionFilters{})
		if err != nil {
			return nil, err
		}
		draft.Wallpapers = wallpapers
	} else {
		if year == 0 || week == 0 {
			year, week, err = h.weeklyRepo.LatestWeek(ctx)
			if err != nil {
				if repo.IsNotFound(err) {
					return nil, nil
				}
				return nil, err
			}
		}
		picks, err := h.weeklyRepo.ListByWeek(ctx, year, week)
		if err != nil {
			return nil, err
		}
		if len(picks) == 0 {
			return nil, nil
		}
		draft.Year = year
		draft.Week = week
		draft.Source = "weekly_picks"
		draft.Wallpapers = make([]model.Wallpaper, len(picks))
		for i, pick := range picks {
			draft.Wallpapers[i] = pick.Wallpaper
		}
	}

	draft.Title = strings.TrimSpace(title)
	if draft.Title == "" {
		draft.Title = h.defaultPostTitle(draft)
	}
	draft.Title = truncateRunes(draft.Title, 300)

	draft.Text = strings.TrimSpace(text)
	if draft.Text == "" {
		draft.Text = h.defaultPostText(draft)
	}
	return draft, nil
}

func (h *RedditHandler) resolveThemeCollection(ctx context.Context, year, week int16) (*model.Collection, error) {
	if year > 0 && week > 0 {
		return h.collectionRepo.GetThemeCollectionByWeek(ctx, year, week)
	}
	return h.collectionRepo.LatestThemeCollection(ctx)
}

func (h *RedditHandler) defaultPostTitle(draft *redditWeeklyDraft) string {
	if draft.Collection != nil {
		name := cleanWeeklyCollectionTitle(draft.Collection.Title)
		if name != "" {
			return fmt.Sprintf("This week's wallpaper collection: %s", name)
		}
	}
	return fmt.Sprintf("Wallpaper Exchange weekly picks - %d week %02d", draft.Year, draft.Week)
}

func (h *RedditHandler) defaultPostText(draft *redditWeeklyDraft) string {
	var b strings.Builder
	if draft.Collection != nil {
		b.WriteString(fmt.Sprintf("I put together this week's Wallpaper Exchange collection: **%s**.\n\n", draft.Collection.Title))
		if desc := strings.TrimSpace(draft.Collection.Description); desc != "" {
			b.WriteString(desc)
			b.WriteString("\n\n")
		}
		b.WriteString("Browse the full collection:\n")
		b.WriteString(h.collectionURL(draft.Collection))
		b.WriteString("\n\n")
	} else {
		b.WriteString(fmt.Sprintf("Here are this week's Wallpaper Exchange picks for **%d-W%02d**.\n\n", draft.Year, draft.Week))
		b.WriteString("Browse the full weekly issue:\n")
		b.WriteString(h.weeklyURL(draft.Year, draft.Week))
		b.WriteString("\n\n")
	}

	if len(draft.Wallpapers) > 0 {
		b.WriteString("A few highlights:\n\n")
		limit := len(draft.Wallpapers)
		if limit > 6 {
			limit = 6
		}
		for i := 0; i < limit; i++ {
			w := draft.Wallpapers[i]
			b.WriteString(fmt.Sprintf("- %s - %s\n", wallpaperLabel(w), h.wallpaperURL(w)))
		}
		b.WriteString("\n")
	}

	b.WriteString("I would love feedback on the collection, the image quality, and what kinds of wallpaper themes people want next.")
	return b.String()
}

func (h *RedditHandler) previewResponse(draft *redditWeeklyDraft, existing *model.RedditWeeklyPost) redditWeeklyPreviewResponse {
	var col *redditCollectionSummary
	if draft.Collection != nil {
		col = &redditCollectionSummary{
			ID:             draft.Collection.ID,
			Slug:           draft.Collection.Slug,
			Title:          draft.Collection.Title,
			Description:    draft.Collection.Description,
			CoverURL:       draft.Collection.CoverURL,
			WallpaperCount: draft.Collection.WallpaperCount,
		}
	}
	wallpapers := make([]redditPostWallpaper, 0, len(draft.Wallpapers))
	for _, item := range draft.Wallpapers {
		wallpapers = append(wallpapers, redditPostWallpaper{
			ID:         item.ID,
			Slug:       item.Slug,
			Title:      item.Title,
			ThumbURL:   item.ThumbURL,
			PreviewURL: item.PreviewURL,
			Width:      item.Width,
			Height:     item.Height,
		})
	}
	var existingPost *redditWeeklyPostResult
	alreadyPosted := false
	if existing != nil && existing.PostID != "" {
		alreadyPosted = true
		existingPost = &redditWeeklyPostResult{
			Year:          existing.Year,
			Week:          existing.Week,
			Subreddit:     existing.Subreddit,
			PostID:        existing.PostID,
			PostURL:       existing.PostURL,
			AlreadyPosted: true,
		}
	}
	return redditWeeklyPreviewResponse{
		Year:          draft.Year,
		Week:          draft.Week,
		Source:        draft.Source,
		Subreddit:     draft.Subreddit,
		Title:         draft.Title,
		Text:          draft.Text,
		Collection:    col,
		Wallpapers:    wallpapers,
		AlreadyPosted: alreadyPosted,
		ExistingPost:  existingPost,
	}
}

func (h *RedditHandler) refreshIfNeeded(ctx context.Context, integration *model.ExternalIntegration) (*model.ExternalIntegration, error) {
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

func (h *RedditHandler) writeRedditAPIError(w http.ResponseWriter, err error) {
	status := http.StatusBadGateway
	ec := errcode.ErrInternal
	if apiErr, ok := reddit.IsAPIError(err); ok {
		status = apiErr.StatusCode
		if status == http.StatusForbidden {
			ec = errcode.ErrForbidden
		} else if status >= 400 && status < 500 {
			ec = errcode.ErrBadRequest
		}
	}
	slog.Warn("reddit request failed", slog.String("error", err.Error()))
	response.JSON(w, status, ec, map[string]string{"error": err.Error()})
}

func (h *RedditHandler) defaultSubreddit() string {
	return normalizeSubreddit(firstNonEmpty(h.cfg.DefaultSubreddit, "wallpapers"))
}

func (h *RedditHandler) collectionURL(col *model.Collection) string {
	return strings.TrimRight(h.cfg.SiteURL, "/") + "/collections/" + col.Slug
}

func (h *RedditHandler) weeklyURL(year, week int16) string {
	return fmt.Sprintf("%s/weekly-picks/%d/%d", strings.TrimRight(h.cfg.SiteURL, "/"), year, week)
}

func (h *RedditHandler) wallpaperURL(w model.Wallpaper) string {
	return strings.TrimRight(h.cfg.SiteURL, "/") + "/wallpaper/" + w.Slug
}

type redditStatePayload struct {
	Exp   int64  `json:"exp"`
	Nonce string `json:"nonce"`
}

func (h *RedditHandler) signState() (string, error) {
	nonceBytes := make([]byte, 16)
	if _, err := rand.Read(nonceBytes); err != nil {
		return "", err
	}
	payload := redditStatePayload{
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

func (h *RedditHandler) verifyState(state string) bool {
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
	var payload redditStatePayload
	if err := json.Unmarshal(data, &payload); err != nil {
		return false
	}
	return payload.Exp >= time.Now().Unix()
}

func (h *RedditHandler) sign(payload string) string {
	secret := h.stateSecret
	if secret == "" {
		secret = "wallpaper-reddit-state"
	}
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(payload))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func (h *RedditHandler) writeCallbackHTML(w http.ResponseWriter, ok bool, message string) {
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
  <title>Reddit {{.Status}}</title>
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
    <h1>Reddit {{.Status}}</h1>
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

func parseYearWeek(r *http.Request) (int16, int16) {
	var year, week int16
	if raw := r.URL.Query().Get("year"); raw != "" {
		if v, err := strconv.ParseInt(raw, 10, 16); err == nil {
			year = int16(v)
		}
	}
	if raw := r.URL.Query().Get("week"); raw != "" {
		if v, err := strconv.ParseInt(raw, 10, 16); err == nil {
			week = int16(v)
		}
	}
	return year, week
}

func normalizeSubreddit(subreddit string) string {
	subreddit = strings.TrimSpace(subreddit)
	subreddit = strings.TrimPrefix(subreddit, "/")
	subreddit = strings.TrimPrefix(subreddit, "r/")
	subreddit = strings.TrimPrefix(subreddit, "R/")
	return subreddit
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func cleanWeeklyCollectionTitle(title string) string {
	title = strings.TrimSpace(title)
	parts := strings.Split(title, "·")
	if len(parts) > 1 {
		return strings.TrimSpace(parts[len(parts)-1])
	}
	return title
}

func wallpaperLabel(w model.Wallpaper) string {
	title := strings.TrimSpace(w.Title)
	if title != "" {
		return title
	}
	if w.Width > 0 && w.Height > 0 {
		return fmt.Sprintf("%d x %d wallpaper", w.Width, w.Height)
	}
	return "Wallpaper"
}

func redditPostURL(resp *reddit.SubmitResponse) string {
	if resp == nil {
		return ""
	}
	if strings.HasPrefix(resp.URL, "http://") || strings.HasPrefix(resp.URL, "https://") {
		return resp.URL
	}
	if strings.HasPrefix(resp.Permalink, "http://") || strings.HasPrefix(resp.Permalink, "https://") {
		return resp.Permalink
	}
	if strings.HasPrefix(resp.Permalink, "/") {
		return "https://www.reddit.com" + resp.Permalink
	}
	if resp.ID != "" {
		return "https://www.reddit.com/comments/" + resp.ID
	}
	return ""
}

func draftCollectionID(draft *redditWeeklyDraft) int64 {
	if draft != nil && draft.Collection != nil {
		return draft.Collection.ID
	}
	return 0
}
