package repo

import (
	"context"
	"fmt"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

const SystemUserID int64 = 0

type CoinRepo struct {
	db *gorm.DB
}

func NewCoinRepo(db *gorm.DB) *CoinRepo {
	return &CoinRepo{db: db}
}

// addCoinsInTx updates user balance and writes a transaction log within the given tx.
// System user (id=0) allows negative balance; real users do not.
func addCoinsInTx(tx *gorm.DB, userID int64, amount int64, txType string, refID int64, desc string) (int64, error) {
	result := tx.Model(&model.User{}).Where("id = ?", userID)
	if amount < 0 && userID != SystemUserID {
		result = result.Where("coins >= ?", -amount)
	}
	result = result.UpdateColumn("coins", gorm.Expr("coins + ?", amount))
	if result.Error != nil {
		return 0, fmt.Errorf("update coins: %w", result.Error)
	}
	if result.RowsAffected == 0 {
		return 0, fmt.Errorf("insufficient coins")
	}

	var user model.User
	if err := tx.Select("coins").Where("id = ?", userID).First(&user).Error; err != nil {
		return 0, fmt.Errorf("read balance: %w", err)
	}

	txn := model.CoinTransaction{
		UserID:      userID,
		Amount:      amount,
		Balance:     user.Coins,
		TxType:      txType,
		RefID:       refID,
		Description: desc,
	}
	if err := tx.Create(&txn).Error; err != nil {
		return 0, fmt.Errorf("create transaction: %w", err)
	}
	return user.Coins, nil
}

// Transfer moves coins from one user to another with double-entry bookkeeping.
// Both sides are written in a single transaction; if the source has insufficient
// coins the entire operation is rolled back.
// Returns the new balance of toUserID.
func (r *CoinRepo) Transfer(ctx context.Context, fromID, toID int64, amount int64, fromTxType, toTxType string, refID int64, fromDesc, toDesc string) (int64, error) {
	var toBalance int64
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if _, err := addCoinsInTx(tx, fromID, -amount, fromTxType, refID, fromDesc); err != nil {
			return fmt.Errorf("debit from %d: %w", fromID, err)
		}
		bal, err := addCoinsInTx(tx, toID, amount, toTxType, refID, toDesc)
		if err != nil {
			return fmt.Errorf("credit to %d: %w", toID, err)
		}
		toBalance = bal
		return nil
	})
	return toBalance, err
}

// HasTransaction reports whether userID already has a transaction of
// txType referencing refID. Used as an idempotency guard so rewards
// keyed to a wallpaper (e.g. upload_reward on review approval) can't
// be paid twice across reject-undo-approve cycles.
func (r *CoinRepo) HasTransaction(ctx context.Context, userID int64, txType string, refID int64) (bool, error) {
	var count int64
	err := r.db.WithContext(ctx).
		Model(&model.CoinTransaction{}).
		Where("user_id = ? AND tx_type = ? AND ref_id = ?", userID, txType, refID).
		Count(&count).Error
	return count > 0, err
}

func (r *CoinRepo) GetBalance(ctx context.Context, userID int64) (int64, error) {
	var user model.User
	err := r.db.WithContext(ctx).Select("coins").Where("id = ?", userID).First(&user).Error
	return user.Coins, err
}

func (r *CoinRepo) CountTransactions(ctx context.Context, userID int64) (int64, error) {
	var count int64
	err := r.db.WithContext(ctx).
		Model(&model.CoinTransaction{}).
		Where("user_id = ?", userID).
		Count(&count).Error
	return count, err
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
