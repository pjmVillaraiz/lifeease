import 'package:url_launcher/url_launcher.dart';

class EmergencyRouteProcessingModule {
  Uri buildDialUri(String phone) {
    final normalized = phone.replaceAll(RegExp(r"[^\d+]"), "");
    return Uri(scheme: "tel", path: normalized);
  }

  Uri buildSmsUri(String phone, {String? message}) {
    final normalized = phone.replaceAll(RegExp(r"[^\d+]"), "");
    return Uri(
      scheme: "sms",
      path: normalized,
      queryParameters: message == null || message.trim().isEmpty
          ? null
          : {'body': message.trim()},
    );
  }

  Future<bool> call(String phone) async {
    final uri = buildDialUri(phone);
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri);
  }

  Future<bool> message(String phone, {String? message}) async {
    final uri = buildSmsUri(phone, message: message);
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri);
  }
}
