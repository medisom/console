import 'package:web/web.dart' as web;

Future<void> openPortalReplace(String url) async {
  web.window.location.replace(url);
}
