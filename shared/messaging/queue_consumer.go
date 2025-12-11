package messaging

import (
	"encoding/json"
	"log"

	"ride-sharing/shared/contracts"
)

type QueueConsumer struct {
	rb        *RabbitMQ
	connMgr   *ConnectionManager
	queueName string
}

func NewQueueConsumer(rb *RabbitMQ, connMgr *ConnectionManager, queueName string) *QueueConsumer {
	return &QueueConsumer{
		rb:        rb,
		connMgr:   connMgr,
		queueName: queueName,
	}
}

func (qc *QueueConsumer) Start() error {
	msgs, err := qc.rb.Channel.Consume(
		qc.queueName,
		"",
		true,
		false,
		false,
		false,
		nil,
	)
	if err != nil {
		return err
	}

	go func() {
		for msg := range msgs {
			var msgBody contracts.AmqpMessage
			if err := json.Unmarshal(msg.Body, &msgBody); err != nil {
				log.Println("Failed to unmarshal message:", err)
				continue
			}

			userID := msgBody.OwnerID

			var payload any
			if msgBody.Data != nil {
				if err := json.Unmarshal(msgBody.Data, &payload); err != nil {
					log.Println("Failed to unmarshal payload:", err)
					continue
				}

				// For DriverCmdTripRequest, extract the trip from TripEventData structure
				if msg.RoutingKey == contracts.DriverCmdTripRequest {
					if tripEventData, ok := payload.(map[string]interface{}); ok {
						if trip, exists := tripEventData["trip"]; exists {
							payload = trip
						}
					}
				}
			}

			clientMsg := contracts.WSMessage{
				Type: msg.RoutingKey,
				Data: payload,
			}

			log.Printf("QueueConsumer: Sending message to user %s, type: %s, queue: %s", userID, msg.RoutingKey, qc.queueName)
			if err := qc.connMgr.SendMessage(userID, clientMsg); err != nil {
				log.Printf("Failed to send message to user %s: %v", userID, err)
			} else {
				log.Printf("QueueConsumer: Successfully sent message to user %s, type: %s", userID, msg.RoutingKey)
			}
		}
	}()

	return nil
}
