import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/native_ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Graphify guide logic', () {
    test('Scope có graphify-out đầy đủ -> sinh hướng dẫn đầy đủ theo tài liệu chính thức', () {
      // Dùng chính thư mục dự án này (có graphify-out thật)
      final guide = NativeAiService.buildGraphifyGuideForTest(
          '/home/yenai/Documents/Projects/Typing/apps/plugins/agent-coder');
      expect(guide, isNotNull);
      expect(guide, contains('GRAPH_REPORT.md'));
      expect(guide, contains('graph.json'));
      expect(guide, contains('manifest.json'));
      expect(guide, contains('graphify-out'));
      // Nội dung theo tài liệu chính thức Graphify-Labs
      expect(guide, contains('graphify query'));
      expect(guide, contains('graphify path'));
      expect(guide, contains('graphify explain'));
      expect(guide, contains('EXTRACTED'));
      expect(guide, contains('INFERRED'));
      expect(guide, contains('AMBIGUOUS'));
      expect(guide, contains('graphify update .'));
      expect(guide, contains('git rev-parse HEAD'));
    });

    test('Scope không có graphify-out -> trả về null', () {
      final guide = NativeAiService.buildGraphifyGuideForTest('/tmp');
      expect(guide, isNull);
    });

    test('graphify-out rỗng (không report/graph) -> trả về null', () {
      final tmp = Directory.systemTemp.createTempSync('gfy_test');
      Directory(p.join(tmp.path, 'graphify-out')).createSync();
      final guide = NativeAiService.buildGraphifyGuideForTest(tmp.path);
      expect(guide, isNull);
      tmp.deleteSync(recursive: true);
    });

    test('Chỉ có GRAPH_REPORT.md -> sinh hướng dẫn tối thiểu (không có mục truy vấn đồ thị)', () {
      final tmp = Directory.systemTemp.createTempSync('gfy_test2');
      final gf = Directory(p.join(tmp.path, 'graphify-out'))..createSync();
      File(p.join(gf.path, 'GRAPH_REPORT.md')).writeAsStringSync('# Report');
      final guide = NativeAiService.buildGraphifyGuideForTest(tmp.path);
      expect(guide, isNotNull);
      expect(guide, contains('GRAPH_REPORT.md'));
      expect(guide, isNot(contains('TRUY VẤN ĐỒ THỊ')));
      tmp.deleteSync(recursive: true);
    });

    test('Có wiki/index.md -> hướng dẫn có mục điều hướng wiki', () {
      final tmp = Directory.systemTemp.createTempSync('gfy_test3');
      final gf = Directory(p.join(tmp.path, 'graphify-out'))..createSync();
      File(p.join(gf.path, 'GRAPH_REPORT.md')).writeAsStringSync('# Report');
      File(p.join(gf.path, 'graph.json')).writeAsStringSync('{}');
      Directory(p.join(gf.path, 'wiki')).createSync();
      File(p.join(gf.path, 'wiki', 'index.md')).writeAsStringSync('# Index');
      final guide = NativeAiService.buildGraphifyGuideForTest(tmp.path);
      expect(guide, isNotNull);
      expect(guide, contains('wiki/index.md'));
      expect(guide, contains('ĐIỀU HƯỚNG QUA WIKI'));
      tmp.deleteSync(recursive: true);
    });
  });
}
