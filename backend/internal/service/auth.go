package service

import (
	"context"
	"log/slog"
	"strings"

	"golang.org/x/crypto/bcrypt"

	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/model"
	jwtpkg "github.com/wallpaper/backend/internal/pkg/jwt"
	"github.com/wallpaper/backend/internal/repo"
)

type AuthService struct {
	userRepo  *repo.UserRepo
	jwtSecret string
	jwtExpire int
}

func NewAuthService(userRepo *repo.UserRepo, jwtSecret string, jwtExpire int) *AuthService {
	return &AuthService{
		userRepo:  userRepo,
		jwtSecret: jwtSecret,
		jwtExpire: jwtExpire,
	}
}

type RegisterRequest struct {
	Username string `json:"username"`
	Email    string `json:"email"`
	Password string `json:"password"`
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type AuthResponse struct {
	Token string      `json:"token"`
	User  *model.User `json:"user"`
}

func (s *AuthService) Register(ctx context.Context, req RegisterRequest) (*AuthResponse, *errcode.ErrCode) {
	if len(req.Username) < 3 || len(req.Username) > 32 {
		return nil, errcode.ErrInvalidParam
	}
	if !strings.Contains(req.Email, "@") {
		return nil, errcode.ErrInvalidParam
	}
	if len(req.Password) < 8 {
		return nil, errcode.ErrInvalidParam
	}

	existing, err := s.userRepo.GetByUsername(ctx, req.Username)
	if err != nil {
		slog.ErrorContext(ctx, "failed to check username existence", "error", err)
		return nil, errcode.ErrInternal
	}
	if existing != nil {
		return nil, errcode.ErrUserExists
	}

	existing, err = s.userRepo.GetByEmail(ctx, req.Email)
	if err != nil {
		slog.ErrorContext(ctx, "failed to check email existence", "error", err)
		return nil, errcode.ErrInternal
	}
	if existing != nil {
		return nil, errcode.ErrUserExists
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		slog.ErrorContext(ctx, "failed to hash password", "error", err)
		return nil, errcode.ErrInternal
	}

	user := &model.User{
		Username:     req.Username,
		Email:        req.Email,
		PasswordHash: string(hash),
	}
	if err := s.userRepo.Create(ctx, user); err != nil {
		slog.ErrorContext(ctx, "failed to create user", "error", err)
		return nil, errcode.ErrInternal
	}

	token, err := jwtpkg.GenerateToken(user.ID, s.jwtSecret, s.jwtExpire)
	if err != nil {
		slog.ErrorContext(ctx, "failed to generate token", "error", err)
		return nil, errcode.ErrInternal
	}

	user.PasswordHash = ""

	return &AuthResponse{
		Token: token,
		User:  user,
	}, nil
}

func (s *AuthService) Login(ctx context.Context, req LoginRequest) (*AuthResponse, *errcode.ErrCode) {
	user, err := s.userRepo.GetByEmail(ctx, req.Email)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get user by email", "error", err)
		return nil, errcode.ErrInternal
	}
	if user == nil {
		return nil, errcode.ErrWrongPassword
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		return nil, errcode.ErrWrongPassword
	}

	token, err := jwtpkg.GenerateToken(user.ID, s.jwtSecret, s.jwtExpire)
	if err != nil {
		slog.ErrorContext(ctx, "failed to generate token", "error", err)
		return nil, errcode.ErrInternal
	}

	user.PasswordHash = ""

	return &AuthResponse{
		Token: token,
		User:  user,
	}, nil
}
