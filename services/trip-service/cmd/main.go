package main

import (
	"context"
	"log"
	"net"
	"os"
	"os/signal"
	"ride-sharing/services/trip-service/internal/infrastructure/events"
	"ride-sharing/services/trip-service/internal/infrastructure/grpc"
	"ride-sharing/services/trip-service/internal/infrastructure/repository"
	"ride-sharing/services/trip-service/internal/service"
	"ride-sharing/shared/db"
	"ride-sharing/shared/env"
	"ride-sharing/shared/messaging"
	"ride-sharing/shared/tracing"
	"syscall"
	"time"

	"go.mongodb.org/mongo-driver/mongo"
	grpcserver "google.golang.org/grpc"
)

var GrpcAddr = ":9093"

func main() {
	// Initialize Tracing
	tracerCfg := tracing.Config{
		ServiceName:    "trip-service",
		Environment:    env.GetString("ENVIRONMENT", "development"),
		JaegerEndpoint: env.GetString("JAEGER_ENDPOINT", "http://jaeger:14268/api/traces"),
	}

	sh, err := tracing.InitTracer(tracerCfg)
	if err != nil {
		log.Fatalf("Failed to initialize the tracer: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	defer sh(ctx)

	// Initialize MongoDB with retry to avoid crashing while DB starts up
	mongoCfg := db.NewMongoDefaultConfig()
	mongoClient, mongoDb, err := connectMongoWithRetry(ctx, mongoCfg, 10, 5*time.Second)
	if err != nil {
		log.Fatalf("Failed to initialize MongoDB, err: %v", err)
	}
	defer mongoClient.Disconnect(ctx)

	rabbitMqURI := env.GetString("RABBITMQ_URI", "amqp://rideshare:rideshare@rabbitmq:5672/")

	mongoDBRepo := repository.NewMongoRepository(mongoDb)
	svc := service.NewService(mongoDBRepo)

	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
		<-sigCh
		cancel()
	}()

	lis, err := net.Listen("tcp", GrpcAddr)
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	// RabbitMQ connection with retry to avoid crashing while RabbitMQ starts up
	rabbitmq, err := connectRabbitMQWithRetry(ctx, rabbitMqURI, 10, 5*time.Second)
	if err != nil {
		log.Fatalf("Failed to initialize RabbitMQ, err: %v", err)
	}
	defer rabbitmq.Close()

	log.Println("Starting RabbitMQ connection")

	publisher := events.NewTripEventPublisher(rabbitmq)

	// Start driver consumer
	driverConsumer := events.NewDriverConsumer(rabbitmq, svc)
	go driverConsumer.Listen()

	// Start payment consumer
	paymentConsumer := events.NewPaymentConsumer(rabbitmq, svc)
	go paymentConsumer.Listen()

	// Starting the gRPC server
	grpcServer := grpcserver.NewServer(tracing.WithTracingInterceptors()...)
	grpc.NewGRPCHandler(grpcServer, svc, publisher)

	log.Printf("Starting gRPC server Trip service on port %s", lis.Addr().String())

	go func() {
		if err := grpcServer.Serve(lis); err != nil {
			log.Printf("failed to serve: %v", err)
			cancel()
		}
	}()

	// wait for the shutdown signal
	<-ctx.Done()
	log.Println("Shutting down the server...")
	grpcServer.GracefulStop()
}

func connectMongoWithRetry(ctx context.Context, cfg *db.MongoConfig, attempts int, delay time.Duration) (*mongo.Client, *mongo.Database, error) {
	var lastErr error

	for i := 1; i <= attempts; i++ {
		client, err := db.NewMongoClient(ctx, cfg)
		if err == nil {
			return client, db.GetDatabase(client, cfg), nil
		}

		lastErr = err
		log.Printf("MongoDB connection attempt %d/%d failed: %v", i, attempts, err)

		select {
		case <-time.After(delay):
		case <-ctx.Done():
			return nil, nil, ctx.Err()
		}
	}

	return nil, nil, lastErr
}

func connectRabbitMQWithRetry(ctx context.Context, uri string, attempts int, delay time.Duration) (*messaging.RabbitMQ, error) {
	var lastErr error

	for i := 1; i <= attempts; i++ {
		rabbitmq, err := messaging.NewRabbitMQ(uri)
		if err == nil {
			log.Printf("Successfully connected to RabbitMQ on attempt %d", i)
			return rabbitmq, nil
		}

		lastErr = err
		log.Printf("RabbitMQ connection attempt %d/%d failed: %v", i, attempts, err)

		select {
		case <-time.After(delay):
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}

	return nil, lastErr
}
