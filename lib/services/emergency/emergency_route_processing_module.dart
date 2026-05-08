import 'package:url_launcher/url_launcher.dart';

class EmergencyRouteProcessingModule {
  Uri buildDialUri(String phone) {
    final normalized = phone.replaceAll(RegExp(r"[^\d+]"), "");
    return Uri(scheme: "tel", path: normalized);
  }

  Future<bool> call(String phone) async {
    final uri = buildDialUri(phone);
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri);
  }
}
