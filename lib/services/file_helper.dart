import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';

class FileHelper {
  static Future<void> openFile(String path) async {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      throw Exception('Impossible d\'ouvrir : ${result.message}');
    }
  }

  static Future<String> getDownloadsDirectory() async {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir.path;
    }
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  static Future<void> saveFileBytes(String path, List<int> bytes) async {
    await File(path).writeAsBytes(bytes);
  }

  static Future<void> requestStoragePermissionIfNeeded() async {
    if (Platform.isAndroid) {
      final sdkInt = await getAndroidSdkInt();
      if (sdkInt < 29) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          throw Exception('Permission de stockage refusée');
        }
      }
    }
  }

  static Future<int> getAndroidSdkInt() async {
    if (!Platform.isAndroid) return 0;
    try {
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse((result.stdout as String).trim()) ?? 29;
    } catch (_) {
      return 29;
    }
  }

  static Future<String> getTemporaryDirPath() async {
    final dir = await getTemporaryDirectory();
    return dir.path;
  }
}
