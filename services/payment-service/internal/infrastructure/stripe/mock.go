package stripe

import (
	"context"
	"fmt"

	"ride-sharing/services/payment-service/internal/domain"
	"ride-sharing/services/payment-service/pkg/types"

	"github.com/google/uuid"
)

type mockStripeClient struct {
	config *types.PaymentConfig
}

// NewMockStripeClient returns a mock payment processor used for local development
// when real Stripe credentials are not available.
func NewMockStripeClient(config *types.PaymentConfig) domain.PaymentProcessor {
	return &mockStripeClient{
		config: config,
	}
}

func (m *mockStripeClient) CreatePaymentSession(_ context.Context, _ int64, _ string, _ map[string]string) (string, error) {
	sessionID := fmt.Sprintf("mock_session_%s", uuid.New().String())
	return sessionID, nil
}
