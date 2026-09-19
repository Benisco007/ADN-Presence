class OpenFilex {
  static Future<OpenFileResult> open(String filePath) async {
    return OpenFileResult(type: ResultType.error, message: 'Non supporté sur Web');
  }
}

class OpenFileResult {
  final ResultType type;
  final String message;
  OpenFileResult({required this.type, required this.message});
}

enum ResultType {
  done,
  fileNotFound,
  noAppToOpen,
  permissionDenied,
  error,
}
