package repo

import (
	"context"
	"fmt"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

type CoinRepo struct {
	db *gorm.DB
}

func NewCoinRepo(db *gorm.DB) *CoinRepo {
	return &CoinRepo{db: db}
}

// AddCoins atomically adds amount to user balance and writes a transaction log.
// amount can be negative (deduction). Returns the new balance.
// The caller must guarantee amount validity; this method rejects negative resulting balance.
func (r *CoinRepo) AddCoins(ctx context.Context, userID int64, amount int64, txType string, refID int64, desc string) (int64, error) {
	var newBalance int64
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		result := tx.Model(&model.User{}).
			Where("id = ?", userID)
		if amount < 0 {
			result = result.Where("coins >= ?", -amount)
		}
		result = result.UpdateColumn("coins", gorm.Expr("coins + ?", amount))
		if result.Error != nil {
			return fmt.Errorf("update coins: %w", result.Error)
		}
		if result.RowsAffected == 0 {
			return fmt.Errorf("insufficient coins")
		}

		var user model.User
		if err := tx.Select("coins").Where("id = ?", userID).First(&user).Error; err != nil {
			return fmt.Errorf("read balance: %w", err)
		}
		newBalance = user.Coins

		txn := model.CoinTransaction{
			UserID:      userID,
			Amount:      amount,
			Balance:     newBalance,
			TxType:      txType,
			RefID:       refID,
			Description: desc,
		}
		if err := tx.Create(&txn).Error; err != nil {
			return fmt.Errorf("create transaction: %w", err)
		}
		return nil
	})
	return newBalance, err
}

func (r *CoinRepo) GetBalance(ctx context.Context, userID int64) (int64, error) {
	var user model.User
	err := r.db.WithContext(ctx).Select("coins").Where("id = ?", userID).First(&user).Error
	return user.Coins, err
}

func (r *CoinRepo) ListTransactions(ctx context.Context, userID int64, cursor int64, limit int) ([]model.CoinTransaction, error) {
	query := r.db.WithContext(ctx).
		Where("user_id = ?", userID)
	if cursor > 0 {
		query = query.Where("id < ?", cursor)
	}
	var txns []model.CoinTransaction
	err := query.Order("id DESC").Limit(limit).Find(&txns).Error
	return txns, err
}
