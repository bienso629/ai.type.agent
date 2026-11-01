import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/native_ai_service.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/knowledge_index_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Knowledge guide logic', () {
    test('Scope co bo tai lieu phan tich day du -> sinh huong dan day du, khong lo ten cong cu', () {
      // Dung thu muc tam co du lieu phan tich giong cau truc that
      final tmp = Directory.systemTemp.createTempSync('knowledge_test');
      final cache = Directory(p.join(tmp.path, KnowledgeIndexService.cacheDirName))..createSync();
      File(p.join(cache.path, 'GRAPH_REPORT.md')).writeAsStringSync('# Report');
      File(p.join(cache.path, 'graph.json')).writeAsStringSync('{"nodes": []}');
      File(p.join(cache.path, 'manifest.json')).writeAsStringSync('{}');
      Directory(p.join(cache.path, 'wiki')).createSync();
      File(p.join(cache.path, 'wiki', 'index.md')).writeAsStringSync('# Wiki');

      final guide = NativeAiService.buildKnowledgeGuideForTest(tmp.path);
      expect(guide, isNotNull);
      // Cau truc huong dan day du
      expect(guide, contains('GRAPH_REPORT.md'));
      expect(guide, contains('graph.json'));
      expect(guide, contains('index.md'));
      // Do tuoi duoc he thong giu tu dong - guide khong bat AI doi chieu manifest
      expect(guide, contains('tự động ở nền'));
      expect(guide, contains(KnowledgeIndexService.cacheDirName));
      expect(guide, contains('EXTRACTED'));
      expect(guide, contains('INFERRED'));
      expect(guide, contains('AMBIGUOUS'));
      // Khong lo ten cong cu va khong huong dan chay lenh nao
      expect(guide, isNot(contains('graphify')));
      expect(guide, isNot(contains('Graphify')));
      expect(guide, isNot(contains('GRAPHIFY')));
      expect(guide, isNot(contains('command -v')));
      expect(guide, isNot(contains('git rev-parse')));
      tmp.deleteSync(recursive: true);
    });

    test('Scope khong co bo tai lieu phan tich -> tra ve null', () {
      final guide = NativeAiService.buildKnowledgeGuideForTest('/tmp');
      expect(guide, isNull);
    });

    test('Thu muc cache rong (khong report/graph) -> tra ve null', () {
      final tmp = Directory.systemTemp.createTempSync('knowledge_test2');
      Directory(p.join(tmp.path, KnowledgeIndexService.cacheDirName)).createSync();
      final guide = NativeAiService.buildKnowledgeGuideForTest(tmp.path);
      expect(guide, isNull);
      tmp.deleteSync(recursive: true);
    });

    test('Chi co GRAPH_REPORT.md -> sinh huong dan toi thieu (khong co muc truy van do thi)', () {
      final tmp = Directory.systemTemp.createTempSync('knowledge_test3');
      final cache = Directory(p.join(tmp.path, KnowledgeIndexService.cacheDirName))..createSync();
      File(p.join(cache.path, 'GRAPH_REPORT.md')).writeAsStringSync('# Report');
      final guide = NativeAiService.buildKnowledgeGuideForTest(tmp.path);
      expect(guide, isNotNull);
      expect(guide, contains('GRAPH_REPORT.md'));
      expect(guide, isNot(contains('TRUY VẤN DỮ LIỆU ĐỒ THỊ')));
      expect(guide, isNot(contains('graph.json')));
      tmp.deleteSync(recursive: true);
    });

    test('Chi co graph.json -> sinh huong dan co muc truy van do thi, khong co muc bao cao', () {
      final tmp = Directory.systemTemp.createTempSync('knowledge_test4');
      final cache = Directory(p.join(tmp.path, KnowledgeIndexService.cacheDirName))..createSync();
      File(p.join(cache.path, 'graph.json')).writeAsStringSync('{"nodes": []}');
      final guide = NativeAiService.buildKnowledgeGuideForTest(tmp.path);
      expect(guide, isNotNull);
      expect(guide, contains('graph.json'));
      expect(guide, isNot(contains('GRAPH_REPORT.md')));
      tmp.deleteSync(recursive: true);
    });
  });

  group('Brand sanitization logic', () {
    test('sanitizeBrandText loai bo ten cong cu va chi dan CLI', () {
      final input = '''
- Built from commit: `aa125b24`
- Run `graphify update .` after code changes (no API cost).
- graphify_version: 0.9.97
Run graphify query to explore isolated nodes. Graphify rocks. GRAPHIFY RULES.
''';
      final out = KnowledgeIndexService.sanitizeBrandText(input);
      expect(out, isNot(contains('graphify')));
      expect(out, isNot(contains('Graphify')));
      expect(out, isNot(contains('GRAPHIFY')));
      expect(out, isNot(contains('graphify_version')));
      expect(out, isNot(contains('update .`')));
      expect(out, contains('Built from commit'));
    });
  });
}
