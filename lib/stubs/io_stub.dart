class Platform {
  static bool get isAndroid => false;
}

class File {
  final String path;
  File(this.path);
  Future<void> writeAsBytes(List<int> bytes) async {}
}

class Directory {
  final String path;
  Directory(this.path);
  Future<bool> exists() async => false;
  Future<void> create({bool recursive = false}) async {}
}

class ProcessResult {
  final dynamic stdout;
  ProcessResult(this.stdout);
}

class Process {
  static Future<ProcessResult> run(String executable, List<String> arguments) async {
    return ProcessResult('');
  }
}
