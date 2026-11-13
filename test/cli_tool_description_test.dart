import 'package:flutter_test/flutter_test.dart';
import 'package:tadu_cloud_ai_agent_mobile/core/services/native_ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeAiService CLI tool description & parameter parsing', () {
    const scopeDir = '/home/yenai/Documents/Projects/Typing/ai.type';

    test('read_file voi tham so Path (Antigravity CLI) hien thi ro duong dan tuong doi trong Scope va khoang dong', () {
      final step = <String, dynamic>{
        'step_index': 2,
        'state': 'ACTIVE',
        'step_type': 'tool',
        'tool_name': 'read_file',
        'tool_info': {
          'name': 'read_file',
          'parameters': {
            'Path': '/home/yenai/Documents/Projects/Typing/ai.type/src/components/Canvas3D.tsx',
            'StartLine': 15,
            'EndLine': 120,
          },
        },
      };

      final params = NativeAiService.extractCliToolParams(step);
      final desc = NativeAiService.describeCliToolCall(
        toolName: 'read_file',
        toolParams: params,
        workingDir: scopeDir,
      );
      expect(desc, 'Đọc file: src/components/Canvas3D.tsx (dòng 15-120)');
    });

    test('read_file voi gia tri Path boc ngoac kep JSON (protobuf string map) duoc lam sach', () {
      final step = <String, dynamic>{
        'step_type': 'tool',
        'tool_name': 'read_file',
        'tool_info': {
          'parameters': {
            'Path': '"/home/yenai/Documents/Projects/Typing/ai.type/src/App.tsx"',
          },
        },
      };

      final params = NativeAiService.extractCliToolParams(step);
      final desc = NativeAiService.describeCliToolCall(
        toolName: 'read_file',
        toolParams: params,
        workingDir: scopeDir,
      );
      expect(desc, 'Đọc file: src/App.tsx');
    });

    test('view_file / ActionViewFile dang snake_case file_path va Claude Read offset/limit', () {
      final stepAgyAction = <String, dynamic>{
        'step_type': 'tool',
        'tool_name': 'view_file',
        'view_file': {
          'file_path': '/home/yenai/Documents/Projects/Typing/ai.type/package.json',
        },
      };
      final desc1 = NativeAiService.describeCliToolCall(
        toolName: 'view_file',
        toolParams: NativeAiService.extractCliToolParams(stepAgyAction),
        workingDir: scopeDir,
      );
      expect(desc1, 'Đọc file: package.json');

      final descClaude = NativeAiService.describeCliToolCall(
        toolName: 'Read',
        toolParams: {
          'file_path': '/home/yenai/Documents/Projects/Typing/ai.type/src/main.ts',
          'offset': 10,
          'limit': 50,
        },
        workingDir: scopeDir,
      );
      expect(descClaude, 'Đọc file: src/main.ts (dòng 10-59)');
    });

    test('edit_file va write_file voi tham so Path bo qua Target/Replacement/Content dai', () {
      final editDesc = NativeAiService.describeCliToolCall(
        toolName: 'edit_file',
        toolParams: {
          'Path': '/home/yenai/Documents/Projects/Typing/ai.type/src/Scene.tsx',
          'Target': 'const oldCode = 1;\n' * 30,
          'Replacement': 'const newCode = 2;\n' * 30,
        },
        workingDir: scopeDir,
      );
      expect(editDesc, 'Sửa file: src/Scene.tsx');

      final writeDesc = NativeAiService.describeCliToolCall(
        toolName: 'write_file',
        toolParams: {
          'Path': '/home/yenai/Documents/Projects/Typing/ai.type/src/utils/glb.ts',
          'Content': 'export function fixGlb() {}\n' * 20,
          'Overwrite': true,
        },
        workingDir: scopeDir,
      );
      expect(writeDesc, 'Ghi file: src/utils/glb.ts');
    });

    test('run_command, search_web, grep_search va list_dir hien thi day du thong tin', () {
      expect(
        NativeAiService.describeCliToolCall(
          toolName: 'run_command',
          toolParams: {'CommandLine': 'npm run build', 'WaitMsBeforeAsync': 5000},
          workingDir: scopeDir,
        ),
        'npm run build',
      );

      expect(
        NativeAiService.describeCliToolCall(
          toolName: 'search_web',
          toolParams: {'query': 'threejs gltf loader broken mesh', 'domain': 'threejs.org'},
          workingDir: scopeDir,
        ),
        'Tìm web: "threejs gltf loader broken mesh" (threejs.org)',
      );

      expect(
        NativeAiService.describeCliToolCall(
          toolName: 'grep_search',
          toolParams: {
            'Query': 'GLTFLoader',
            'SearchPath': '/home/yenai/Documents/Projects/Typing/ai.type/src',
          },
          workingDir: scopeDir,
        ),
        'Tìm "GLTFLoader" trong src',
      );

      expect(
        NativeAiService.describeCliToolCall(
          toolName: 'list_dir',
          toolParams: {
            'DirectoryPath': '/home/yenai/Documents/Projects/Typing/ai.type/public/models',
          },
          workingDir: scopeDir,
        ),
        'Xem thư mục: public/models',
      );
    });

    test('parameters dang chuoi JSON duoc giai ma an toan khong nem loi cast', () {
      final step = <String, dynamic>{
        'step_type': 'tool',
        'tool_name': 'read_file',
        'tool_info': {
          'parameters': '{"Path":"/home/yenai/Documents/Projects/Typing/ai.type/README.md"}',
        },
      };
      final params = NativeAiService.extractCliToolParams(step);
      expect(
        NativeAiService.describeCliToolCall(
          toolName: 'read_file',
          toolParams: params,
          workingDir: scopeDir,
        ),
        'Đọc file: README.md',
      );
    });

    test('sanitizeServerIdentifier chuan hoa ten may chu SSH cho lenh terminal', () {
      expect(NativeAiService.sanitizeServerIdentifier('Plesk (Free)'), 'plesk_free');
      expect(NativeAiService.sanitizeServerIdentifier('Server 3'), 'server_3');
      expect(NativeAiService.sanitizeServerIdentifier('192.168.1.100'), '192_168_1_100');
      expect(NativeAiService.sanitizeServerIdentifier('VPS-Production-01'), 'vps_production_01');
      expect(NativeAiService.sanitizeServerIdentifier(''), 'server');
    });
  });
}
