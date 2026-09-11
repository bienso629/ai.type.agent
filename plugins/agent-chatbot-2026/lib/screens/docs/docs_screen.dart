import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/services/document_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/tadu_dialog.dart';

class DocsScreen extends StatefulWidget {
  const DocsScreen({super.key});

  @override
  State<DocsScreen> createState() => _DocsScreenState();
}

class _DocsScreenState extends State<DocsScreen> with SingleTickerProviderStateMixin {
  final DocumentService _docService = DocumentService();
  late TabController _tabController;

  List<KnowledgeDocument> _documents = [];
  bool _isLoadingDocs = false;
  bool _isUploading = false;
  bool _isRelearning = false;
  String _relearningStatus = '';
  int? _relearningDocId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDocuments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoadingDocs = true);
    final docs = await _docService.getDocuments();
    if (mounted) {
      setState(() {
        _documents = docs;
        _isLoadingDocs = false;
      });
    }
  }

  String _uploadStatus = '';

  Future<void> _pickAndUploadFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf', 'doc', 'docx', 'xls', 'xlsx', 'csv', 'txt', 'md', 'json',
          'png', 'jpg', 'jpeg', 'webp'
        ],
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() {
        _isUploading = true;
        _uploadStatus = 'Đang chuẩn bị lập chỉ mục tài liệu...';
      });

      int count = 0;
      int failCount = 0;
      for (final pickedFile in result.files) {
        final name = pickedFile.name;
        final path = kIsWeb ? name : (pickedFile.path ?? name);
        final bytes = pickedFile.bytes;

        final docId = await _docService.addDocument(
          name: name,
          filePath: path,
          bytes: bytes,
          onProgress: (status) {
            if (mounted) {
              setState(() {
                _uploadStatus = status;
              });
            }
          },
        );
        if (docId > 0) {
          count++;
        } else {
          failCount++;
        }
      }

      await _loadDocuments();

      if (mounted) {
        if (count > 0 && failCount == 0) {
          AppToast.success(context, 'Đã tải lên và lập chỉ mục thành công $count tài liệu!');
        } else if (count > 0 && failCount > 0) {
          final detail = _docService.lastError != null ? ' (${_docService.lastError})' : '';
          AppToast.warning(context, 'Đã tải thành công $count tài liệu, nhưng thất bại $failCount tài liệu$detail.');
        } else {
          final detail = _docService.lastError != null ? ': ${_docService.lastError}' : '';
          AppToast.error(context, 'Không thể tải tài liệu lên máy chủ$detail');
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi khi tải file: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatus = '';
        });
      }
    }
  }


  Future<void> _relearnSpecificDocument(KnowledgeDocument doc) async {
    if (_isRelearning || _isUploading) return;

    final isScanOrImg = doc.isImage || doc.isScannedPdf;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => TaduDialog(
        title: Text('Học lại tài liệu: ${doc.name}'),
        content: Text(
          isScanOrImg
              ? 'AI Agent sẽ quét lại các trang và chạy Vision OCR để phân tích lại toàn bộ chữ viết, số liệu trong tệp "${doc.name}".\n\nBạn có muốn thực hiện không?'
              : 'AI Agent sẽ lập chỉ mục và cập nhật lại nội dung văn bản cho tệp "${doc.name}".\n\nBạn có muốn thực hiện không?',
          style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textWhite),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy bỏ', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Học lại ngay'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isRelearning = true;
      _relearningDocId = doc.id;
      _relearningStatus = 'Đang phân tích lại: ${doc.name}...';
    });

    try {
      final success = await _docService.relearnSingleDocument(
        doc,
        onProgress: (status) {
          if (mounted) {
            setState(() {
              _relearningStatus = status;
            });
          }
        },
      );

      await _loadDocuments();

      if (mounted) {
        if (success) {
          AppToast.success(context, 'Đã học lại thành công tài liệu "${doc.name}"!');
        } else {
          AppToast.info(context, 'Tài liệu "${doc.name}" đã được cập nhật.');
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Lỗi khi học lại: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRelearning = false;
          _relearningDocId = null;
          _relearningStatus = '';
        });
      }
    }
  }

  Future<void> _toggleDocument(KnowledgeDocument doc) async {
    final nextState = !doc.isEnabled;
    await _docService.toggleDocument(doc.id!, nextState);
    await _loadDocuments();
    if (mounted) {
      AppToast.info(
        context,
        nextState ? 'Đã kích hoạt [${doc.name}] cho AI' : 'Đã tạm tắt [${doc.name}]',
      );
    }
  }

  Future<void> _deleteDocument(KnowledgeDocument doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => TaduDialog(
        title: const Text('Xác nhận xóa tài liệu'),
        content: Text(
          'Bạn có chắc chắn muốn xóa "${doc.name}" khỏi cơ sở tri thức của AI Agent không?',
          style: const TextStyle(fontSize: 13, color: AppColors.textWhite),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy bỏ', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa ngay'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _docService.deleteDocument(doc.id!);
      await _loadDocuments();
      if (mounted) {
        AppToast.success(context, 'Đã xóa tài liệu khỏi cơ sở tri thức.');
      }
    }
  }

  void _previewDocument(KnowledgeDocument doc) {
    showDialog(
      context: context,
      builder: (ctx) {
        return TaduDialog(
          minWidth: 550,
          maxWidth: 750,
          scrollableBody: false,
          title: Row(
            children: [
              _buildExtBadge(doc.extension),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  doc.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Dung lượng: ${doc.formattedSize} • Ngày tải: ${doc.createdAt.toString().split('.')[0]}',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const Divider(color: AppColors.borderDark, height: 20),
              Row(
                children: [
                  Text(
                    doc.isImage
                        ? 'KẾT QUẢ PHÂN TÍCH THỊ GIÁC AI (VISION & OCR):'
                        : (doc.isScannedPdf ? 'KẾT QUẢ QUÉT THỊ GIÁC PDF SCAN (OCR VISION):' : 'DỮ LIỆU ĐÃ TRÍCH XUẤT CHO AI:'),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight, letterSpacing: 0.5),
                  ),
                  const Spacer(),
                  Text(
                    '${doc.content.length} ký tự',
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.bgDark,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.borderDark),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: SelectableText(
                          doc.content.isEmpty ? '(Chưa có nội dung văn bản bóc tách được)' : doc.content,
                          style: const TextStyle(fontSize: 12.5, height: 1.6, color: AppColors.textBody, fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  Color _getExtColor(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'webp':
      case 'gif':
      case 'bmp':
        return const Color(0xFFF59E0B);
      case 'pdf':
        return Colors.redAccent;
      case 'doc':
      case 'docx':
        return Colors.blueAccent;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Colors.greenAccent;
      case 'txt':
      case 'md':
        return AppColors.accentCyan;
      default:
        return AppColors.warning;
    }
  }

  Widget _buildExtBadge(String ext) {
    final color = _getExtColor(ext);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        ext.toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabledCount = _documents.where((d) => d.isEnabled).length;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar with Relearn Button & Upload Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: const BoxDecoration(
              color: AppColors.bgDark,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_stories_rounded, color: AppColors.primaryLight, size: 24),
                const SizedBox(width: 14),
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tài Liệu & Cơ Sở Tri Thức',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Nạp tài liệu, biểu đồ và hình ảnh để AI Agent nghiên cứu, tham khảo và bổ trợ trả lời chi tiết hơn',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
                const Spacer(),

                // Upload Button
                ElevatedButton.icon(
                  onPressed: (_isUploading || _isRelearning) ? null : _pickAndUploadFiles,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                  ),
                  icon: _isUploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.upload_file_rounded, size: 18),
                  label: Text(
                    _isUploading ? 'Đang tải lên...' : 'Tải lên tài liệu & ảnh',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // Indexing & Re-learning Status Progress Bar if running
          if (_isUploading && _uploadStatus.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              color: AppColors.primaryLight.withValues(alpha: 0.15),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _uploadStatus,
                    style: const TextStyle(fontSize: 12, color: AppColors.primaryLight, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          if (_isRelearning || _relearningDocId != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              color: AppColors.cardBg,
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _relearningStatus,
                    style: const TextStyle(fontSize: 12, color: AppColors.accent),
                  ),
                ],
              ),
            ),

          // Tab Bar
          Container(
            decoration: const BoxDecoration(
              color: AppColors.bgDark,
              border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppColors.primaryLight,
              unselectedLabelColor: AppColors.textMuted,
              indicatorColor: AppColors.primaryLight,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              tabs: [
                Tab(
                  child: Row(
                    children: [
                      const Icon(Icons.folder_shared_rounded, size: 16),
                      const SizedBox(width: 8),
                      Text('Tài liệu đã học (${_documents.length})'),
                    ],
                  ),
                ),
                const Tab(
                  child: Row(
                    children: [
                      Icon(Icons.menu_book_rounded, size: 16),
                      SizedBox(width: 8),
                      Text('Cẩm nang hướng dẫn'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Uploaded Knowledge Documents
                _buildKnowledgeBaseTab(enabledCount),

                // Tab 2: System Usage Docs
                _buildHandbookTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKnowledgeBaseTab(int enabledCount) {
    if (_isLoadingDocs) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
      );
    }

    if (_documents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.borderDark),
              ),
              child: const Icon(Icons.auto_stories_rounded, size: 48, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            const Text(
              'Chưa có tài liệu hoặc hình ảnh nào trong cơ sở tri thức',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textWhite),
            ),
            const SizedBox(height: 6),
            const Text(
              'Bấm "Tải lên tài liệu & ảnh" để nạp PDF, Word, Excel, CSV, TXT và ảnh (PNG, JPG) cho AI học hỏi.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: (_isUploading || _isRelearning) ? null : _pickAndUploadFiles,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryLight.withValues(alpha: 0.15),
                foregroundColor: AppColors.primaryLight,
                side: const BorderSide(color: AppColors.primaryLight),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                elevation: 0,
              ),
              icon: const Icon(Icons.cloud_upload_rounded, size: 18),
              label: const Text('Chọn tệp ngay'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Document Cards
        ..._documents.map((doc) => _buildDocumentCard(doc)),
      ],
    );
  }

  Widget _buildDocumentCard(KnowledgeDocument doc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: doc.isEnabled ? AppColors.borderDark : AppColors.borderDark.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          _buildExtBadge(doc.extension),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        doc.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: doc.isEnabled ? AppColors.textWhite : AppColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: doc.isEnabled
                            ? Colors.greenAccent.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        doc.isEnabled ? 'Đang kích hoạt' : 'Tạm ngưng',
                        style: TextStyle(
                          fontSize: 10,
                          color: doc.isEnabled ? Colors.greenAccent : AppColors.textMuted,
                        ),
                      ),
                    ),
                    if (doc.isImage) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Thị giác AI',
                          style: TextStyle(fontSize: 10, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold),
                        ),
                      ),
                    ] else if (doc.isScannedPdf) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purpleAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'PDF Scan OCR',
                          style: TextStyle(fontSize: 10, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${doc.formattedSize} • Cập nhật: ${doc.createdAt.toString().split('.')[0]}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Action buttons
          IconButton(
            icon: const Icon(Icons.visibility_outlined, size: 18, color: AppColors.textMuted),
            tooltip: doc.isImage ? 'Xem phân tích thị giác' : 'Xem trích xuất nội dung',
            onPressed: () => _previewDocument(doc),
          ),
          // Nút học lại dữ liệu cho từng item tài liệu
          IconButton(
            icon: (_relearningDocId == doc.id)
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                  )
                : const Icon(Icons.sync_rounded, size: 18, color: AppColors.accent),
            tooltip: 'Học lại tài liệu này (Vision OCR & Index)',
            onPressed: (_relearningDocId != null || _isRelearning || _isUploading)
                ? null
                : () => _relearnSpecificDocument(doc),
          ),
          Switch(
            value: doc.isEnabled,
            activeThumbColor: AppColors.primaryLight,
            onChanged: (val) => _toggleDocument(doc),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
            tooltip: 'Xóa tài liệu',
            onPressed: () => _deleteDocument(doc),
          ),
        ],
      ),
    );
  }

  Widget _buildHandbookTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildSectionCard(
          icon: Icons.rocket_launch_rounded,
          iconColor: AppColors.primaryLight,
          title: '1. Giới thiệu tổng quan',
          content:
              'AI Agent Chatbot là giải pháp trợ lý thông minh đa năng, hỗ trợ lập kế hoạch công việc, phân tích hệ thống và hỗ trợ kỹ thuật theo thời gian thực. Ứng dụng tích hợp mô hình ngôn ngữ lớn tiên tiến cùng khả năng thực thi tác vụ an toàn.',
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          icon: Icons.chat_bubble_outline_rounded,
          iconColor: AppColors.accent,
          title: '2. Cách tương tác với Trợ lý AI',
          content:
              '• Tạo hội thoại mới: Bấm nút "Hội thoại mới" ở góc trên bên phải để bắt đầu phiên làm việc độc lập.\n'
              '• Ghim hội thoại: Trong danh sách hộp hội thoại, bấm biểu tượng ghim để giữ các phiên quan trọng lên trên đầu.\n'
              '• Tìm kiếm nhanh: Dùng công cụ tìm kiếm trong Hộp Hội Thoại để truy xuất nội dung đã trao đổi trước đó.',
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          icon: Icons.terminal_rounded,
          iconColor: AppColors.accentCyan,
          title: '3. Cơ chế lập kế hoạch & Thực thi',
          content:
              '• Lập kế hoạch: AI Agent tự động hiểu mục tiêu của người dùng, phân tích và chia nhỏ thành các bước thực hiện rõ ràng.\n'
              '• Thực thi lệnh an toàn: Mọi thao tác đều được kiểm soát và ghi log minh bạch để đảm bảo an toàn hệ thống.',
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          icon: Icons.tune_rounded,
          iconColor: AppColors.warning,
          title: '4. Cấu hình Model & Proxy API',
          content:
              '• Chuyển sang mục "Cài đặt" để lựa chọn các dòng Model AI phù hợp (glm-5.3, qwen-2.5-coder, gemini-2.5-flash,...).\n'
              '• Nhập Proxy Base URL và API Key khi kết nối qua cổng proxy riêng để tối ưu băng thông và bảo mật.',
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.textBody),
          ),
        ],
      ),
    );
  }
}
