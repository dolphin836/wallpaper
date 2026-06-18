package pinterest

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/wallpaper/backend/internal/config"
)

const (
	authURL = "https://www.pinterest.com/oauth/"

	ScopeBoardsRead  = "boards:read"
	ScopeBoardsWrite = "boards:write"
	ScopePinsRead    = "pins:read"
	ScopePinsWrite   = "pins:write"
	ScopeUserRead    = "user_accounts:read"
)

var DefaultScopes = []string{
	ScopeBoardsRead,
	ScopeBoardsWrite,
	ScopePinsRead,
	ScopePinsWrite,
	ScopeUserRead,
}

type Client struct {
	appID       string
	appSecret   string
	redirectURL string
	apiBaseURL  string
	tokenURL    string
	httpClient  *http.Client
}

func NewClient(cfg config.PinterestConfig) *Client {
	return &Client{
		appID:       cfg.AppID,
		appSecret:   cfg.AppSecret,
		redirectURL: cfg.RedirectURL,
		apiBaseURL:  strings.TrimRight(cfg.APIBaseURL, "/"),
		tokenURL:    cfg.TokenURL,
		httpClient:  &http.Client{Timeout: 25 * time.Second},
	}
}

func (c *Client) Configured() bool {
	return c.appID != "" && c.appSecret != "" && c.redirectURL != ""
}

func (c *Client) RedirectURL() string {
	return c.redirectURL
}

func (c *Client) AuthCodeURL(state string) string {
	values := url.Values{}
	values.Set("response_type", "code")
	values.Set("client_id", c.appID)
	values.Set("redirect_uri", c.redirectURL)
	values.Set("scope", strings.Join(DefaultScopes, ","))
	values.Set("state", state)
	return authURL + "?" + values.Encode()
}

type TokenResponse struct {
	AccessToken           string `json:"access_token"`
	RefreshToken          string `json:"refresh_token"`
	TokenType             string `json:"token_type"`
	Scope                 string `json:"scope"`
	ExpiresIn             int64  `json:"expires_in"`
	RefreshTokenExpiresIn int64  `json:"refresh_token_expires_in"`
}

func (c *Client) ExchangeCode(ctx context.Context, code string) (*TokenResponse, error) {
	form := url.Values{}
	form.Set("grant_type", "authorization_code")
	form.Set("code", code)
	form.Set("redirect_uri", c.redirectURL)
	return c.tokenRequest(ctx, form)
}

func (c *Client) RefreshToken(ctx context.Context, refreshToken string) (*TokenResponse, error) {
	form := url.Values{}
	form.Set("grant_type", "refresh_token")
	form.Set("refresh_token", refreshToken)
	form.Set("scope", strings.Join(DefaultScopes, ","))
	return c.tokenRequest(ctx, form)
}

func (c *Client) tokenRequest(ctx context.Context, form url.Values) (*TokenResponse, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.tokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.SetBasicAuth(c.appID, c.appSecret)

	var token TokenResponse
	if err := c.do(req, &token); err != nil {
		return nil, err
	}
	if token.AccessToken == "" {
		return nil, fmt.Errorf("pinterest token response missing access_token")
	}
	return &token, nil
}

type UserAccount struct {
	Username     string `json:"username"`
	AccountType  string `json:"account_type"`
	ProfileImage string `json:"profile_image"`
	WebsiteURL   string `json:"website_url"`
}

func (c *Client) GetUserAccount(ctx context.Context, accessToken string) (*UserAccount, error) {
	var account UserAccount
	if err := c.get(ctx, accessToken, "/user_account", &account); err != nil {
		return nil, err
	}
	return &account, nil
}

type Board struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Privacy     string `json:"privacy"`
	URL         string `json:"url"`
}

type listBoardsResponse struct {
	Items    []Board `json:"items"`
	Bookmark string  `json:"bookmark"`
}

func (c *Client) ListBoards(ctx context.Context, accessToken string) ([]Board, error) {
	var boards []Board
	bookmark := ""
	for {
		path := "/boards?page_size=100"
		if bookmark != "" {
			path += "&bookmark=" + url.QueryEscape(bookmark)
		}
		var resp listBoardsResponse
		if err := c.get(ctx, accessToken, path, &resp); err != nil {
			return nil, err
		}
		boards = append(boards, resp.Items...)
		if resp.Bookmark == "" {
			break
		}
		bookmark = resp.Bookmark
	}
	return boards, nil
}

type CreateBoardRequest struct {
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
	Privacy     string `json:"privacy,omitempty"`
}

func (c *Client) CreateBoard(ctx context.Context, accessToken string, reqBody CreateBoardRequest) (*Board, error) {
	if reqBody.Privacy == "" {
		reqBody.Privacy = "PUBLIC"
	}
	var board Board
	if err := c.post(ctx, accessToken, "/boards", reqBody, &board); err != nil {
		return nil, err
	}
	return &board, nil
}

type CreatePinRequest struct {
	BoardID     string           `json:"board_id"`
	Title       string           `json:"title,omitempty"`
	Description string           `json:"description,omitempty"`
	Link        string           `json:"link,omitempty"`
	AltText     string           `json:"alt_text,omitempty"`
	MediaSource ImageMediaSource `json:"media_source"`
}

type ImageMediaSource struct {
	SourceType string `json:"source_type"`
	URL        string `json:"url"`
}

type Pin struct {
	ID      string `json:"id"`
	Link    string `json:"link"`
	Title   string `json:"title"`
	BoardID string `json:"board_id"`
	URL     string `json:"url"`
}

func (c *Client) CreatePin(ctx context.Context, accessToken string, reqBody CreatePinRequest) (*Pin, error) {
	if reqBody.MediaSource.SourceType == "" {
		reqBody.MediaSource.SourceType = "image_url"
	}
	var pin Pin
	if err := c.post(ctx, accessToken, "/pins", reqBody, &pin); err != nil {
		return nil, err
	}
	return &pin, nil
}

func (c *Client) get(ctx context.Context, accessToken, path string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.apiBaseURL+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	return c.do(req, out)
}

func (c *Client) post(ctx context.Context, accessToken, path string, body any, out any) error {
	payload, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.apiBaseURL+path, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/json")
	return c.do(req, out)
}

func (c *Client) do(req *http.Request, out any) error {
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("pinterest api %s %s returned %d: %s", req.Method, req.URL.Path, resp.StatusCode, strings.TrimSpace(string(data)))
	}
	if out == nil || len(data) == 0 {
		return nil
	}
	if err := json.Unmarshal(data, out); err != nil {
		return fmt.Errorf("decode pinterest response: %w", err)
	}
	return nil
}
