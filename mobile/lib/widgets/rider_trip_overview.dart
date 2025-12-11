import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/types.dart';
import '../models/contracts.dart';
import '../providers/rider_provider.dart';
import '../utils/math_utils.dart';
import 'trip_overview_card.dart';
import 'driver_card.dart';
import 'stripe_payment_button.dart';
import 'drivers_list.dart';

class RiderTripOverview extends ConsumerWidget {
  final String userId;
  final Coordinate? destination;
  final VoidCallback? onReset;

  const RiderTripOverview({
    super.key,
    required this.userId,
    this.destination,
    this.onReset,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(riderProvider(userId));
    final notifier = ref.read(riderProvider(userId).notifier);
    
    // Debug: Log state for troubleshooting
    print('RiderTripOverview: error=${state.error}, isLoadingPreview=${state.isLoadingPreview}, tripPreview=${state.tripPreview != null}');

    if (state.error != null) {
      return SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'Connection Error',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                state.error!,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.left,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  // Retry both WebSocket and preview trip if applicable
                  final notifier = ref.read(riderProvider(userId).notifier);
                  notifier.reconnect();
                  // Also retry preview trip if there was a previous attempt
                  await notifier.retryPreviewTrip();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Connection'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (state.tripPreview == null) {
      // Show loading state if preview is being loaded
      if (state.isLoadingPreview) {
        print('RiderTripOverview: Showing loading state');
        return SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text(
                    'Searching for rides...',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait while we find available rides',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }
      
      print('RiderTripOverview: Showing default message (not loading, no preview)');
      
      // Show default message only if we're not in an error state and not loading
      // If destination is provided, show a more helpful message
      return SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_car, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  destination != null ? 'Click Search Rides to find available rides' : 'Enter your destination',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  destination != null 
                      ? 'Your destination is set. Click the Search Rides button above to continue.'
                      : 'Fill in the destination field above to search for rides',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Payment required (when payment session is created but driver might not be assigned yet)
    if (state.tripStatus == TripEvents.paymentSessionCreated &&
        state.paymentSession != null) {
      return SingleChildScrollView(
        child: TripOverviewCard(
          title: 'Payment Required',
          description: state.assignedDriver != null
              ? 'Please complete the payment to confirm your trip'
              : 'Please complete the payment to proceed with your trip',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.assignedDriver != null) ...[
                DriverCard(driver: state.assignedDriver!),
                const SizedBox(height: 16),
              ],
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Trip Amount',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${state.paymentSession!.amount} ${state.paymentSession!.currency}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Trip ID: ${state.paymentSession!.tripID}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              StripePaymentButton(
                paymentSession: state.paymentSession!,
              ),
            ],
          ),
        ),
      );
    }

    // No drivers found
    if (state.tripStatus == TripEvents.noDriversFound) {
      return TripOverviewCard(
        title: 'No drivers found',
        description: 'No drivers found for your trip, please try again later',
        child: OutlinedButton(
          onPressed: () {
            notifier.resetTripStatus();
            onReset?.call();
          },
          child: const Text('Go back'),
        ),
      );
    }

    // Driver assigned
    if (state.tripStatus == TripEvents.driverAssigned) {
      return SingleChildScrollView(
        child: TripOverviewCard(
          title: 'Driver assigned!',
          description: state.paymentSession != null
              ? 'Please complete the payment to confirm your trip'
              : 'Your driver is on the way, waiting for payment confirmation...',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.assignedDriver != null)
                DriverCard(driver: state.assignedDriver!),
              const SizedBox(height: 16),
              
              // Show payment section if payment session is available
              if (state.paymentSession != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Trip Amount',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${state.paymentSession!.amount} ${state.paymentSession!.currency}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Trip ID: ${state.paymentSession!.tripID}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                StripePaymentButton(
                  paymentSession: state.paymentSession!,
                ),
                const SizedBox(height: 12),
              ] else ...[
                // Show loading indicator while waiting for payment session
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        'Preparing payment...',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => notifier.resetTripStatus(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Cancel current trip'),
              ),
            ],
          ),
        ),
      );
    }

    // Trip completed
    if (state.tripStatus == TripEvents.completed) {
      return TripOverviewCard(
        title: 'Trip completed!',
        description: 'Your trip is completed, thank you for using our service!',
        child: OutlinedButton(
          onPressed: () {
            notifier.resetTripStatus();
            onReset?.call();
          },
          child: const Text('Go back'),
        ),
      );
    }

    // Trip cancelled
    if (state.tripStatus == TripEvents.cancelled) {
      return TripOverviewCard(
        title: 'Trip cancelled!',
        description: 'Your trip is cancelled, please try again later',
        child: OutlinedButton(
          onPressed: () {
            notifier.resetTripStatus();
            onReset?.call();
          },
          child: const Text('Go back'),
        ),
      );
    }

    // Looking for driver
    if (state.tripStatus == TripEvents.created) {
      return SingleChildScrollView(
        child: TripOverviewCard(
          title: 'Looking for a driver',
          description:
              'Your trip is confirmed! We\'re matching you with a driver...',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              if (state.tripPreview!.duration > 0)
                Text(
                  'Arriving in: ${MathUtils.convertSecondsToMinutes(state.tripPreview!.duration)} at your destination (${MathUtils.convertMetersToKilometers(state.tripPreview!.distance)})',
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  notifier.resetTripStatus();
                  onReset?.call();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    }

    // Show fare selection
    if (state.tripPreview!.rideFares.isNotEmpty &&
        state.tripPreview!.tripID.isEmpty) {
      return DriversList(
        tripPreview: state.tripPreview!,
        onPackageSelect: (fare) async {
          await notifier.startTrip(fare);
        },
        onCancel: () {
          notifier.resetTripStatus();
          onReset?.call();
        },
      );
    }

    return TripOverviewCard(
      title: 'No trip ride fares',
      description: 'Please refresh the page',
    );
  }
}

