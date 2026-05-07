package errcode

type ErrCode struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func (e *ErrCode) Error() string { return e.Message }

var (
	Success          = &ErrCode{0, "ok"}
	ErrBadRequest    = &ErrCode{40000, "bad request"}
	ErrInvalidParam  = &ErrCode{40001, "invalid parameter"}
	ErrUnauthorized  = &ErrCode{40100, "unauthorized"}
	ErrTokenExpired  = &ErrCode{40101, "token expired"}
	ErrTokenInvalid  = &ErrCode{40102, "invalid token"}
	ErrWrongPassword = &ErrCode{40103, "wrong password"}
	ErrForbidden     = &ErrCode{40300, "forbidden"}
	ErrNotFound      = &ErrCode{40400, "resource not found"}
	ErrUserExists    = &ErrCode{40901, "username or email already exists"}
	ErrRateLimited   = &ErrCode{42900, "too many requests"}
	ErrInsufficientCoins = &ErrCode{40201, "insufficient coins"}
	ErrInternal          = &ErrCode{50000, "internal server error"}
	ErrUploadFailed      = &ErrCode{50001, "file upload failed"}
)
