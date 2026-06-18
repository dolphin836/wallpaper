package reddit

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/wallpaper/backend/internal/config"
)

const authURL = "https://www.reddit.com/api/v1/authorize"

const (
	ScopeIdentity = "identity"
	ScopeSubmit   = "submit"
)

var DefaultScopes = []string{
	ScopeIdentity,
	ScopeSubmit,
}

type APIError struct {
	StatusCode int
	Message    string
	Body       string
}

func (e *APIError) Error() string {
	if e.Message != "" {
		return e.Message
	}
	if e.Body != "" {
		return e.Body
	}
	return fmt.Sprintf("reddit api returned %d", e.StatusCode)
}

func IsAPIError(err error) (*APIError, bool) {
	var apiErr *APIError
	if errors.As(err, &apiErr) {
		return apiErr, true
	}
	return nil, false
}

type Client struct {
	clientID     string
	clientSecret string
	redirectURL  string
	apiBaseURL   string
	tokenURL     string
	userAgent    string
	httpClient   *http.Client
}

func NewClient(cfg config.RedditConfig) *Client {
	return &Client{
		clientID:     cfg.ClientID,
		clientSecret: cfg.ClientSecret,
		redirectURL:  cfg.RedirectURL,
		apiBaseURL:   strings.TrimRight(cfg.APIBaseURL, "/"),
		tokenURL:     cfg.TokenURL,
		userAgent:    cfg.UserAgent,
		httpClient:   &http.Client{Timeout: 25 * time.Second},
	}
}

func (c *Client) Configured() bool {
	return c.clientID != "" && c.clientSecret != "" && c.redirectURL != ""
}

func (c *Client) RedirectURL() string {
	return c.redirectURL
}

func (c *Client) AuthCodeURL(state string) string {
	values := url.Values{}
	values.Set("client_id", c.clientID)
	values.Set("response_type", "code")
	values.Set("state", state)
	values.Set("redirect_uri", c.redirectURL)
	values.Set("duration", "permanent")
	values.Set("scope", strings.Join(DefaultScopes, " "))
	return authURL + "?" + values.Encode()
}

type TokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
	Scope        string `json:"scope"`
	ExpiresIn    int64  `json:"expires_in"`
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
	return c.tokenRequest(ctx, form)
}

func (c *Client) tokenRequest(ctx context.Context, form url.Values) (*TokenResponse, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.tokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	c.setUserAgent(req)
	req.SetBasicAuth(c.clientID, c.clientSecret)

	var token TokenResponse
	if err := c.do(req, &token); err != nil {
		return nil, err
	}
	if token.AccessToken == "" {
		return nil, fmt.Errorf("reddit token response missing access_token")
	}
	return &token, nil
}

type UserAccount struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	IconURL string `json:"icon_img"`
}

func (c *Client) GetMe(ctx context.Context, accessToken string) (*UserAccount, error) {
	var account UserAccount
	if err := c.get(ctx, accessToken, "/api/v1/me", &account); err != nil {
		return nil, err
	}
	return &account, nil
}

type SubmitRequest struct {
	Subreddit   string
	Kind        string
	Title       string
	Text        string
	URL         string
	SendReplies bool
}

type SubmitResponse struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	URL       string `json:"url"`
	Permalink string `json:"permalink"`
}

func (c *Client) Submit(ctx context.Context, accessToken string, body SubmitRequest) (*SubmitResponse, error) {
	kind := strings.TrimSpace(body.Kind)
	if kind == "" {
		kind = "self"
	}
	form := url.Values{}
	form.Set("api_type", "json")
	form.Set("sr", cleanSubreddit(body.Subreddit))
	form.Set("kind", kind)
	form.Set("title", body.Title)
	form.Set("sendreplies", boolString(body.SendReplies))
	form.Set("resubmit", "true")
	switch kind {
	case "self":
		form.Set("text", body.Text)
	case "link":
		form.Set("url", body.URL)
	default:
		return nil, fmt.Errorf("unsupported reddit post kind: %s", kind)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.apiBaseURL+"/api/submit", strings.NewReader(form.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	c.setUserAgent(req)

	var envelope struct {
		JSON struct {
			Errors [][]any        `json:"errors"`
			Data   SubmitResponse `json:"data"`
		} `json:"json"`
	}
	if err := c.do(req, &envelope); err != nil {
		return nil, err
	}
	if len(envelope.JSON.Errors) > 0 {
		return nil, &APIError{StatusCode: http.StatusBadRequest, Message: redditErrorMessage(envelope.JSON.Errors)}
	}
	return &envelope.JSON.Data, nil
}

func (c *Client) get(ctx context.Context, accessToken, path string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.apiBaseURL+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	c.setUserAgent(req)
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
		apiErr := &APIError{
			StatusCode: resp.StatusCode,
			Body:       strings.TrimSpace(string(data)),
		}
		var parsed struct {
			Error            string `json:"error"`
			ErrorDescription string `json:"error_description"`
			Message          string `json:"message"`
			Reason           string `json:"reason"`
		}
		if err := json.Unmarshal(data, &parsed); err == nil {
			for _, candidate := range []string{parsed.ErrorDescription, parsed.Message, parsed.Reason, parsed.Error} {
				if strings.TrimSpace(candidate) != "" {
					apiErr.Message = strings.TrimSpace(candidate)
					break
				}
			}
		}
		return apiErr
	}
	if out == nil || len(data) == 0 {
		return nil
	}
	if err := json.Unmarshal(data, out); err != nil {
		return fmt.Errorf("decode reddit response: %w", err)
	}
	return nil
}

func (c *Client) setUserAgent(req *http.Request) {
	userAgent := strings.TrimSpace(c.userAgent)
	if userAgent == "" {
		userAgent = "WallpaperExchange/1.0 by wallpaperexchange"
	}
	req.Header.Set("User-Agent", userAgent)
}

func cleanSubreddit(subreddit string) string {
	subreddit = strings.TrimSpace(subreddit)
	subreddit = strings.TrimPrefix(subreddit, "/")
	subreddit = strings.TrimPrefix(subreddit, "r/")
	subreddit = strings.TrimPrefix(subreddit, "R/")
	return subreddit
}

func boolString(v bool) string {
	if v {
		return "true"
	}
	return "false"
}

func redditErrorMessage(errors [][]any) string {
	parts := make([]string, 0, len(errors))
	for _, row := range errors {
		if len(row) == 0 {
			continue
		}
		code := fmt.Sprint(row[0])
		message := ""
		if len(row) > 1 {
			message = fmt.Sprint(row[1])
		}
		field := ""
		if len(row) > 2 {
			field = fmt.Sprint(row[2])
		}
		if field != "" {
			parts = append(parts, fmt.Sprintf("%s: %s (%s)", code, message, field))
		} else if message != "" {
			parts = append(parts, fmt.Sprintf("%s: %s", code, message))
		} else {
			parts = append(parts, code)
		}
	}
	if len(parts) == 0 {
		return "reddit rejected the submission"
	}
	return strings.Join(parts, "; ")
}
