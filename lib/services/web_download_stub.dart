/// Placeholder used on Android / Windows. Only the browser build uses the
/// real version (web_download_web.dart).
void downloadBytes(String fileName, List<int> bytes) {
  throw UnsupportedError('Browser download is only available on the web.');
}
