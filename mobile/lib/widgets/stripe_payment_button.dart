import 'package:flutter/material.dart';
import '../models/contracts.dart';
import '../services/stripe_service.dart';

class StripePaymentButton extends StatefulWidget {
  final PaymentSessionData paymentSession;

  const StripePaymentButton({
    super.key,
    required this.paymentSession,
  });

  @override
  State<StripePaymentButton> createState() => _StripePaymentButtonState();
}

class _StripePaymentButtonState extends State<StripePaymentButton> {
  bool _isLoading = false;

  Future<void> _handlePayment() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final isMockSession =
          widget.paymentSession.sessionID.startsWith('mock_session');
      print(
          'StripePaymentButton: Initiating payment for trip ${widget.paymentSession.tripID}');
      await StripeService.redirectToCheckout(widget.paymentSession.sessionID);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isMockSession
                ? 'Payment simulated successfully.'
                : 'Redirecting to payment...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('StripePaymentButton: Payment error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Payment error: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handlePayment,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.payment, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Pay ${widget.paymentSession.amount} ${widget.paymentSession.currency}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
