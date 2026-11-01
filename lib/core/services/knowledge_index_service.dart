import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'stealth_vault.dart';

/// Dich vu nen: giu cho bo tai lieu phan tich kien truc ma nguon cua Scope
/// luon tuoi moi, hoan toan tu dong va im lang phia sau giao dien.
///
/// Nguyen tac an toan doi voi nguoi dung:
/// - Khong hien thi bat cu thong bao, tien trinh, cau lenh hay ten cong cu nao.
/// - Qua trinh dong bo chay thong qua bo thong dich trung tinh dat trong thu
///   muc runtime rieng cua ung dung (khong de lai vet ten cong cu trong Scope).
/// - Du lieu phan tich duoc ghi vao thu muc cache an (bat dau bang dau cham)
///   ngay trong Scope (an voi liet ke thong thuong).
/// - Sau moi lan dong bo, du lieu duoc lam sach moi vet ten nhan hieu cong cu
///   truoc khi duoc cap phat cho bo nao Agent.
class KnowledgeIndexService {
  KnowledgeIndexService._();
  static final KnowledgeIndexService instance = KnowledgeIndexService._();

  /// Ten thu muc du lieu phan tich (an voi giao dien thong thuong vi bat dau
  /// bang dau cham).
  static String get cacheDirName => StealthVault.cacheDirName;

  /// Ten goi trung tinh cho tien trinh (khong chua ten nhan hieu cong cu).
  static String get _neutralProcessName => StealthVault.neutralProcessName;

  /// Ten goi trung tinh hien thi trong prompt/bao cao.
  static const String neutralIndexName = 'Tai lieu phan tich kien truc';

  static const Duration _syncInterval = Duration(minutes: 5);
  static const Duration _syncTimeout = Duration(seconds: 300);
  static const Duration _sameScopeDebounce = Duration(seconds: 90);

  bool _running = false;
  bool _runtimeReady = false;
  String? _interpreterPath;
  String? _entryScriptPath;
  String? _sitePackagesPath;
  Timer? _loopTimer;
  String? _currentScope;
  String? _lastSyncScope;
  DateTime? _lastSyncAt;

  /// Scope hien tai can giu du lieu tuoi. Gan scope moi se kich hoat dong bo
  /// ngay lap tuc (co debounce de tranh dong bo lap khi chuyen phien qua lai).
  set currentScope(String? scopePath) {
    final clean = (scopePath != null && scopePath.trim().isNotEmpty)
        ? scopePath.trim()
        : null;
    _currentScope = clean;
    if (clean != null) {
      _triggerSync(clean);
    }
  }

  String get currentScope => _currentScope ?? '';

  void _triggerSync(String scopePath) {
    final now = DateTime.now();
    if (_running) return;
    if (_lastSyncScope == scopePath &&
        _lastSyncAt != null &&
        now.difference(_lastSyncAt!) < _sameScopeDebounce) {
      return;
    }
    unawaited(syncScope(scopePath));
  }

  String cacheDirFor(String scopePath) => p.join(scopePath, cacheDirName);

  /// Thu muc runtime trung tinh (nam trong thu muc cau hinh ung dung, khong
  /// de lai bat cu dau vet ten cong cu nao ben trong Scope nguoi dung).
  Directory _runtimeDir() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    return Directory(p.join(
        home, StealthVault.configHomeDir, StealthVault.runtimeDirName));
  }

  /// Kiem tra Scope da co bo du lieu phan tich chua.
  bool hasIndex(String scopePath) {
    try {
      return File(p.join(cacheDirFor(scopePath), 'graph.json')).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Khoi dong vong lap dong bo dinh ky (goi mot lan khi ung dung khoi dong).
  void startBackgroundLoop() {
    _loopTimer ??= Timer.periodic(_syncInterval, (_) {
      final scope = _currentScope;
      if (scope != null && scope.isNotEmpty) {
        unawaited(syncScope(scope));
      }
    });
  }

  /// Chuan bi bo thong dich trung tinh: tim bo thong dich cua cong cu phan tich
  /// tren may, tao symlink ten trung tinh + entry script trung tinh trong thu
  /// muc runtime rieng. Tra ve true neu san sang.
  Future<bool> ensureRuntime() async {
    if (_runtimeReady &&
        _interpreterPath != null &&
        _entryScriptPath != null &&
        _sitePackagesPath != null) {
      return true;
    }
    try {
      final which =
        await Process.run('which', <String>[StealthVault.toolPkg]);
      if (which.exitCode != 0) return false;
      final toolPath = (which.stdout as String? ?? '').trim();
      if (toolPath.isEmpty) return false;

      final real = await Process.run('readlink', <String>['-f', toolPath]);
      final realPath = real.exitCode == 0
          ? (real.stdout as String? ?? '').trim()
          : toolPath;
      final binPath = realPath.isNotEmpty ? realPath : toolPath;
      if (!File(binPath).existsSync()) return false;

      final interpreter = p.join(p.dirname(binPath), 'python');
      if (!File(interpreter).existsSync()) return false;

      // Tim thu muc site-packages cua bo thong dich (de import duoc module
      // phan tich khi chay thong qua symlink trung tinh).
      final baseDir = p.dirname(p.dirname(binPath));
      String? sitePackages;
      final libDir = Directory(p.join(baseDir, 'lib'));
      if (libDir.existsSync()) {
        await for (final entry in libDir.list(followLinks: true)) {
          if (entry is Directory &&
              p.basename(entry.path).startsWith('python')) {
            final candidate = p.join(entry.path, 'site-packages');
            if (Directory(candidate).existsSync()) {
              sitePackages = candidate;
              break;
            }
          }
        }
      }
      if (sitePackages == null || sitePackages.isEmpty) return false;

      // Tao symlink bo thong dich trung tinh + entry script trung tinh.
      final runtimeDir = _runtimeDir();
      if (!runtimeDir.existsSync()) {
        runtimeDir.createSync(recursive: true);
      }
      final interpreterLink = Link(p.join(runtimeDir.path, 'py'));
      if (interpreterLink.existsSync()) {
        await interpreterLink.delete();
      }
      await interpreterLink.create(interpreter);

      // Entry script KHONG chua ten nhan hieu cong cu: ten module duoc nap qua
      // bien moi truong, argv[0] duoc dat thanh ten goi trung tinh.
      final entryFile =
        File(p.join(runtimeDir.path, StealthVault.entryScriptName));
      entryFile.writeAsStringSync(
        'import importlib, os, sys\n'
        'pkg = os.environ.get("' + StealthVault.envPkg + '", "")\n'
        'if not pkg:\n'
        '    raise SystemExit(2)\n'
        'mod = importlib.import_module(pkg + ".__main__")\n'
        'sys.argv[0] = "$_neutralProcessName"\n'
        'raise SystemExit(mod.main())\n',
      );

      _interpreterPath = interpreterLink.path;
      _entryScriptPath = entryFile.path;
      _sitePackagesPath = sitePackages;
      _runtimeReady = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Doc commit HEAD hien tai cua Scope (neu la repository git).
  Future<String?> _gitHead(String scopePath) async {
    try {
      final res = await Process.run(
        'git',
        <String>['rev-parse', 'HEAD'],
        workingDirectory: scopePath,
        runInShell: false,
      );
      if (res.exitCode != 0) return null;
      final out = (res.stdout as String? ?? '').trim();
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  /// Doc commit ma bo du lieu phan tich duoc build tu (neu co).
  String? _builtCommit(String cacheDir) {
    try {
      final report = File(p.join(cacheDir, StealthVault.reportFileName));
      if (!report.existsSync()) return null;
      final content = report.readAsStringSync();
      final m = RegExp(r'Built from commit:\s*`?([0-9a-f]{7,40})`?')
          .firstMatch(content);
      return m?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// Lam sach moi vet ten nhan hieu cong cu trong noi dung tai lieu truoc khi
  /// cap phat cho bo nao Agent.
  static String sanitizeBrandText(String input) {
    var s = input;
    // Bo chi dan CLI lam moi (viec lam moi dien ra tu dong, khong cho AI chay
    // lenh nao lien quan).
    s = s.replaceAll(
        RegExp(r'^\s*-?\s*Run `[^`]*update \.`[^\n]*$', multiLine: true), '');
    s = s.replaceAll(StealthVault.brandQuery, StealthVault.neutralQuery);
    s = s.replaceAll(StealthVault.brandVersion, StealthVault.neutralVersion);
    s = s.replaceAll(StealthVault.brandTitle, StealthVault.neutralTitle);
    s = s.replaceAll(StealthVault.brandUpper, StealthVault.neutralUpper);
    s = s.replaceAll(StealthVault.toolPkg, StealthVault.neutralDash);
    return s;
  }

  /// Lam sach du lieu trong thu muc cache (chi ghi lai khi co thay doi).
  void _sanitizeCacheFiles(String cacheDir) {
    try {
      final dir = Directory(cacheDir);
      if (!dir.existsSync()) return;
      for (final name in <String>[StealthVault.reportFileName, 'graph.json']) {
        final f = File(p.join(cacheDir, name));
        if (!f.existsSync()) continue;
        final original = f.readAsStringSync();
        final cleaned = sanitizeBrandText(original);
        if (cleaned != original) {
          f.writeAsStringSync(cleaned, flush: true);
        }
      }
    } catch (_) {
      // Im lang tuyet doi.
    }
  }

  /// Dong bo du lieu phan tich cho mot Scope. Im lang toan bo: moi loi duoc
  /// nuot, khong co gi duoc in ra hay thong bao cho nguoi dung.
  Future<void> syncScope(String scopePath) async {
    if (_running) return;
    try {
      final scopeDir = Directory(scopePath);
      if (!scopeDir.existsSync()) return;
      final ready = await ensureRuntime();
      if (!ready ||
          _interpreterPath == null ||
          _entryScriptPath == null ||
          _sitePackagesPath == null) {
        return;
      }

      final cacheDir = cacheDirFor(scopePath);
      final indexExists =
          File(p.join(cacheDir, 'graph.json')).existsSync();

      // Chien luoc nhe: chay khong force (nhanh, tu phat hien thay doi cau truc
      // cay); chi force khi chua co du lieu hoac commit HEAD da doi so voi
      // commit ghi trong bao cao (muc do tuoi cua du lieu).
      var force = !indexExists;
      if (!force) {
        final head = await _gitHead(scopePath);
        final built = _builtCommit(cacheDir);
        if (head != null && built != null && head != built) force = true;
      }

      final args = <String>[
        'update',
        scopePath,
        if (force) '--force',
      ];

      final environment = <String, String>{
        ...Platform.environment,
        StealthVault.envPkg: StealthVault.toolPkg,
        StealthVault.envOut: cacheDir,
        'PYTHONPATH': _sitePackagesPath!,
      };

      _running = true;
      try {
        final process = await Process.start(
          _interpreterPath!,
          <String>[_entryScriptPath!, ...args],
          environment: environment,
          workingDirectory: scopePath,
          runInShell: false,
          mode: ProcessStartMode.normal,
        );

        // Nuot het output de ong khong bi day (khong in ra bat cu dau).
        final stdoutDone =
            process.stdout.fold<int>(0, (acc, _) => acc);
        final stderrDone =
            process.stderr.fold<int>(0, (acc, _) => acc);

        var exited = false;
        try {
          await process.exitCode.timeout(_syncTimeout, onTimeout: () {
            try {
              process.kill();
            } catch (_) {}
            return -1;
          });
          exited = true;
        } catch (_) {
          exited = false;
        }
        if (exited) {
          await Future.wait(<Future<int>>[stdoutDone, stderrDone]);
        }
        _sanitizeCacheFiles(cacheDir);
        _lastSyncScope = scopePath;
        _lastSyncAt = DateTime.now();
      } finally {
        _running = false;
      }
    } catch (_) {
      // Im lang tuyet doi.
    } finally {
      _running = false;
    }
  }

  /// Go vong lap dong bo khi ung dung tat.
  @mustCallSuper
  void dispose() {
    _loopTimer?.cancel();
    _loopTimer = null;
  }
}
