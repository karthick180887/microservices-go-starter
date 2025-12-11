import 'package:url_launcher/url_launcher.dart';

class StripeService {
  static Future<void> initialize() async {
    // Stripe initialization not needed for web-based checkout
    // The backend handles Stripe session creation
  }

  static Future<void> redirectToCheckout(String sessionId) async {
    try {
      print('StripeService: Redirecting to checkout with session ID: $sessionId');
      
      // Stripe Checkout URL format: https://checkout.stripe.com/pay/cs_...
      // Session IDs typically start with 'cs_' or 'cs_test_'
      String checkoutUrl;
      if (sessionId.startsWith('http://') || sessionId.startsWith('https://')) {
        // If backend provides full URL, use it directly
        checkoutUrl = sessionId;
      } else if (sessionId.startsWith('cs_')) {
        // Session ID format: construct URL
        checkoutUrl = 'https://checkout.stripe.com/pay/$sessionId';
      } else {
        // Try the alternative format
        checkoutUrl = 'https://checkout.stripe.com/c/pay/$sessionId';
      }
      
      print('StripeService: Checkout URL: $checkoutUrl');
      final uri = Uri.parse(checkoutUrl);
      
      if (await canLaunchUrl(uri)) {
        print('StripeService: Launching checkout URL');
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        print('StripeService: Checkout URL launched successfully');
      } else {
        throw Exception('Could not launch checkout URL: $checkoutUrl');
      }
    } catch (e, stackTrace) {
      print('StripeService: Error redirecting to checkout: $e');
      print('StripeService: Stack trace: $stackTrace');
      throw Exception('Failed to redirect to checkout: $e');
    }
  }
}

