import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/api_service.dart';
import '../../../core/services/remote_file_download_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../models/remote_fs_entry.dart';

/// Hộp thoại tải xuống dạng stream thẳng xuống ổ đĩa (hỗ trợ ảnh, video dung lượng lớn và tệp bất kỳ).
Future<RemoteFileSaveResult?> showStreamingDownloadDialog({
  required BuildContext context,
  required ApiService apiService,
  required String remotePath,
  String? fileName,
}) async {
  final displayName = (fileName != null && fileName.trim().isNotEmpty)
      ? fileName.trim()
      : p.basename(remotePath);
  final kind = RemoteFsEntry.detectKind(displayName);

  int received = 0;
  int total = 0;
  double progress = 0.0;
  bool cancelled = false;
  RemoteFileSaveResult? finalResult;
  StateSetter? dialogSetState;

  final dialogFuture = showDialog<RemoteFileSaveResult?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlgState) {
        dialogSetState = setDlgState;
        final isDone = finalResult?.ok == true;
        final errorMsg = (finalResult != null && !finalResult!.ok) ? finalResult!.error : null;
        final pct = total > 0 ? (progress * 100).clamp(0, 100).toInt() : 0;

        IconData typeIcon = Icons.insert_drive_file_rounded;
        if (kind == 'image') typeIcon = Icons.image_rounded;
        if (kind == 'video') typeIcon = Icons.movie_rounded;
        if (kind == 'audio') typeIcon = Icons.audiotrack_rounded;

        return AlertDialog(
          backgroundColor: AppColors.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: AppColors.borderDark),
          ),
          title: Row(
            children: [
              Icon(
                isDone
                    ? Icons.check_circle_rounded
                    : (errorMsg != null ? Icons.error_outline_rounded : Icons.download_rounded),
                color: isDone ? AppColors.accent : (errorMsg != null ? AppColors.danger : AppColors.accentCyan),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isDone
                      ? 'Tải xuống hoàn tất'
                      : (errorMsg != null ? 'Không thể tải xuống' : 'Đang tải từ máy chính'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(typeIcon, size: 16, color: AppColors.accentCyan),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: isDone ? 1.0 : (total > 0 ? progress : null),
                    minHeight: 7,
                    backgroundColor: AppColors.bgDark,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDone ? AppColors.accent : (errorMsg != null ? AppColors.danger : AppColors.accentCyan),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        isDone
                            ? 'Đã lưu: ${finalResult!.displayLocation}'
                            : (errorMsg ??
                                '${RemoteFileDownloadService.formatBytes(received)}'
                                '${total > 0 ? ' / ${RemoteFileDownloadService.formatBytes(total)}' : ''}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: isDone ? 'monospace' : null,
                          color: errorMsg != null ? AppColors.danger : AppColors.textMuted,
                        ),
                      ),
                    ),
                    if (!isDone && errorMsg == null && total > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '$pct%',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accentCyan,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (isDone &&
                finalResult!.folderToOpen != null &&
                !Platform.isAndroid &&
                !Platform.isIOS)
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_open_rounded, size: 14, color: AppColors.accentCyan),
                label: const Text('Mở thư mục', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  final dir = finalResult!.folderToOpen!;
                  Navigator.pop(ctx, finalResult);
                  unawaited(RemoteFileDownloadService.openLocalFolder(dir));
                },
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDone ? AppColors.primary : AppColors.borderDark,
              ),
              onPressed: () {
                if (finalResult == null) {
                  cancelled = true;
                }
                Navigator.pop(ctx, finalResult);
              },
              child: Text(finalResult != null ? 'Đóng' : 'Hủy'),
            ),
          ],
        );
      },
    ),
  );

  // Chạy tác vụ tải song song với dialog
  unawaited(() async {
    final res = await RemoteFileDownloadService.downloadAndSave(
      api: apiService,
      remotePath: remotePath,
      fileName: displayName,
      onProgress: (rec, tot, prog) {
        received = rec;
        if (tot > 0) total = tot;
        progress = prog;
        dialogSetState?.call(() {});
      },
      isCancelled: () => cancelled,
    );
    finalResult = res;
    if (res.ok) {
      progress = 1.0;
    }
    dialogSetState?.call(() {});
    if (context.mounted && res.ok) {
      AppToast.success(context, 'Đã tải xong: $displayName');
    }
  }());

  return await dialogFuture;
}

/// Lightbox xem trước ảnh phóng to (InteractiveViewer) kèm nút tải xuống ngay về máy.
Future<void> showRemoteImagePreviewDialog({
  required BuildContext context,
  required ApiService apiService,
  required String remotePath,
  required String fileName,
  required bool isSecondaryMode,
  Uri? remoteUri,
  Map<String, String>? remoteHeaders,
}) async {
  Uri? effectiveUri = remoteUri;
  Map<String, String>? effectiveHeaders = remoteHeaders;
  if (isSecondaryMode && effectiveUri == null) {
    final req = await apiService.buildRemoteFileRequest(remotePath, inline: true);
    effectiveUri = req?.uri;
    effectiveHeaders = req?.headers;
  }
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: const Color(0xEE0D1117),
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: AppColors.borderDark),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.cardBg,
                border: Border(bottom: BorderSide(color: AppColors.borderDark)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.image_rounded, size: 16, color: AppColors.accentCyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 14),
                    label: const Text('Tải về máy', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      unawaited(
                        showStreamingDownloadDialog(
                          context: context,
                          apiService: apiService,
                          remotePath: remotePath,
                          fileName: fileName,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Đóng',
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: Center(
                  child: isSecondaryMode
                      ? (effectiveUri != null
                          ? Image.network(
                              effectiveUri.toString(),
                              headers: effectiveHeaders,
                              fit: BoxFit.contain,
                              loadingBuilder: (c, child, loading) =>
                                  loading == null ? child : const CircularProgressIndicator(strokeWidth: 2),
                              errorBuilder: (c, e, s) => const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Không thể tải xem trước ảnh này. Hãy bấm "Tải về máy".',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ),
                            )
                          : const Text('Không tạo được địa chỉ tải ảnh.', style: TextStyle(color: AppColors.textMuted)))
                      : (File(remotePath).existsSync()
                          ? Image.file(File(remotePath), fit: BoxFit.contain)
                          : const Text('Tệp ảnh không tồn tại.', style: TextStyle(color: AppColors.textMuted))),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Trình duyệt thư mục & tệp (Ảnh, Video, Âm thanh, Tài liệu) từ máy App Chính cho phép xem trước & tải xuống.
class RemoteFilesBrowserDialog extends StatefulWidget {
  final String? initialPath;
  final bool isSecondaryMode;
  final ApiService? apiService;

  const RemoteFilesBrowserDialog({
    super.key,
    this.initialPath,
    required this.isSecondaryMode,
    this.apiService,
  });

  @override
  State<RemoteFilesBrowserDialog> createState() => _RemoteFilesBrowserDialogState();
}

class _RemoteFilesBrowserDialogState extends State<RemoteFilesBrowserDialog> {
  late final ApiService _api;
  final TextEditingController _searchCtrl = TextEditingController();

  String _currentPath = '';
  String? _parentPath;
  List<RemoteFsEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  String _filter = 'all'; // 'all' | 'image' | 'video' | 'file'
  final Set<String> _selectedPaths = {};

  // Cache thông tin URL + header xác thực cho thumbnail ảnh
  String? _remoteBaseOrigin;
  Map<String, String>? _remoteHeaders;

  // Trạng thái tải hàng loạt hoặc tải đơn ngay trong hộp thoại
  bool _isDownloading = false;
  bool _cancelRequested = false;
  String _downloadingName = '';
  int _receivedBytes = 0;
  int _totalBytes = 0;
  double _downloadProgress = 0.0;
  int _batchIndex = 0;
  int _batchTotal = 0;
  String? _lastSavedLocation;
  String? _lastFolderToOpen;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? ApiService();
    _currentPath = widget.initialPath?.trim() ?? '';
    _bootstrap();
  }

  @override
  void dispose() {
    _cancelRequested = true;
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (widget.isSecondaryMode) {
      final probe = await _api.buildRemoteFileRequest('__probe__', inline: true);
      if (probe != null && mounted) {
        _remoteBaseOrigin = '${probe.uri.scheme}://${probe.uri.authority}${probe.uri.path}';
        _remoteHeaders = probe.headers;
      }
    }
    await _loadEntries();
  }

  Future<void> _loadEntries({String? targetPath}) async {
    final pathToLoad = targetPath ?? _currentPath;
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.listRemoteEntries(
      path: pathToLoad,
      filter: _filter,
      search: _searchCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _currentPath = res.currentPath;
      _parentPath = res.parentPath;
      _entries = res.entries;
      _error = res.error;
      _selectedPaths.removeWhere((pStr) => !_entries.any((e) => !e.isDir && e.path == pStr));
    });
  }

  Uri? _thumbnailUriFor(String filePath) {
    if (_remoteBaseOrigin == null) return null;
    return Uri.parse('$_remoteBaseOrigin?path=${Uri.encodeQueryComponent(filePath)}&inline=1');
  }

  Future<void> _downloadEntries(List<RemoteFsEntry> items) async {
    if (items.isEmpty || _isDownloading) return;
    setState(() {
      _isDownloading = true;
      _cancelRequested = false;
      _batchIndex = 0;
      _batchTotal = items.length;
      _lastSavedLocation = null;
      _lastFolderToOpen = null;
    });

    int successCount = 0;
    String? lastLocation;
    String? lastFolder;

    for (var i = 0; i < items.length; i++) {
      if (_cancelRequested || !mounted) break;
      final item = items[i];
      setState(() {
        _batchIndex = i + 1;
        _downloadingName = item.name;
        _receivedBytes = 0;
        _totalBytes = item.size;
        _downloadProgress = 0.0;
      });
      final res = await RemoteFileDownloadService.downloadAndSave(
        api: _api,
        remotePath: item.path,
        fileName: item.name,
        onProgress: (rec, tot, prog) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = rec;
            if (tot > 0) _totalBytes = tot;
            _downloadProgress = prog;
          });
        },
        isCancelled: () => _cancelRequested,
      );
      if (res.ok) {
        successCount++;
        lastLocation = res.displayLocation;
        lastFolder = res.folderToOpen;
      }
    }

    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      _selectedPaths.clear();
      _lastSavedLocation = lastLocation;
      _lastFolderToOpen = lastFolder;
    });

    if (successCount > 0) {
      AppToast.success(
        context,
        items.length == 1
            ? 'Đã tải xong "${items.first.name}" về máy.'
            : 'Đã tải xong $successCount/${items.length} tệp về máy.',
      );
    } else if (!_cancelRequested) {
      AppToast.error(context, 'Không thể tải tệp từ App Chính.');
    }
  }

  IconData _entryIcon(RemoteFsEntry entry) {
    if (entry.isDir) return Icons.folder_rounded;
    if (entry.isImage) return Icons.image_rounded;
    if (entry.isVideo) return Icons.movie_rounded;
    if (entry.isAudio) return Icons.audiotrack_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _entryColor(RemoteFsEntry entry) {
    if (entry.isDir) return AppColors.warning;
    if (entry.isImage) return AppColors.accent;
    if (entry.isVideo) return AppColors.accentCyan;
    if (entry.isAudio) return AppColors.primaryLight;
    return AppColors.textMuted;
  }

  Widget _buildFilterChip(String value, String label) {
    final active = _filter == value;
    return InkWell(
      key: ValueKey('remote_fs_filter_$value'),
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        if (_filter == value) return;
        setState(() => _filter = value);
        unawaited(_loadEntries());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withValues(alpha: 0.22) : AppColors.inputBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? AppColors.primaryLight : AppColors.borderDark,
            width: active ? 1.1 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            color: active ? AppColors.primaryLight : AppColors.textBody,
          ),
        ),
      ),
    );
  }

  Widget _buildLeadingVisual(RemoteFsEntry entry) {
    if (entry.isImage) {
      final thumbUri = widget.isSecondaryMode ? _thumbnailUriFor(entry.path) : null;
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 38,
          height: 38,
          color: AppColors.bgDark,
          child: widget.isSecondaryMode
              ? (thumbUri != null
                  ? Image.network(
                      thumbUri.toString(),
                      headers: _remoteHeaders,
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      errorBuilder: (_, _, _) => const Icon(Icons.image_rounded, size: 18, color: AppColors.accent),
                    )
                  : const Icon(Icons.image_rounded, size: 18, color: AppColors.accent))
              : (File(entry.path).existsSync()
                  ? Image.file(
                      File(entry.path),
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      errorBuilder: (_, _, _) => const Icon(Icons.image_rounded, size: 18, color: AppColors.accent),
                    )
                  : const Icon(Icons.image_rounded, size: 18, color: AppColors.accent)),
        ),
      );
    }

    final color = _entryColor(entry);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.7),
      ),
      child: Icon(_entryIcon(entry), size: 19, color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isCompactMobile = screenSize.width < 600;
    final dialogWidth = isCompactMobile ? (screenSize.width - 20) : 780.0;
    final dialogHeight = isCompactMobile ? (screenSize.height * 0.85) : 580.0;

    return Dialog(
      key: const ValueKey('remote_files_browser_dialog'),
      backgroundColor: AppColors.cardBg,
      insetPadding: EdgeInsets.all(isCompactMobile ? 10 : 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: AppColors.borderDark),
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // 1. Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: AppColors.bgDark,
                border: Border(bottom: BorderSide(color: AppColors.borderDark)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_download_rounded, size: 18, color: AppColors.accentCyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.isSecondaryMode ? 'Tệp, Ảnh & Video trên App Chính' : 'Tệp trong thư mục làm việc',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                    ),
                  ),
                  if (_parentPath != null)
                    IconButton(
                      key: const ValueKey('remote_fs_up_button'),
                      tooltip: 'Lên thư mục cha',
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.arrow_upward_rounded, size: 17, color: AppColors.accentCyan),
                      onPressed: _loading ? null : () => _loadEntries(targetPath: _parentPath),
                    ),
                  IconButton(
                    tooltip: 'Làm mới',
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.refresh_rounded, size: 17, color: AppColors.textMuted),
                    onPressed: _loading ? null : () => _loadEntries(),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 2. Path & Filter/Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.inputBg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_outlined, size: 13, color: AppColors.warning),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _currentPath.isNotEmpty ? _currentPath : '/',
                            key: const ValueKey('remote_fs_current_path'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.accentCyan),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (isCompactMobile) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildFilterChip('all', 'Tất cả'),
                        _buildFilterChip('image', 'Hình ảnh'),
                        _buildFilterChip('video', 'Video'),
                        _buildFilterChip('file', 'Tệp'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 32,
                      child: TextField(
                        key: const ValueKey('remote_fs_search_input'),
                        controller: _searchCtrl,
                        style: const TextStyle(fontSize: 12),
                        textAlignVertical: TextAlignVertical.center,
                        onSubmitted: (_) => _loadEntries(),
                        decoration: InputDecoration(
                          hintText: 'Tìm theo tên tệp...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 15),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.close_rounded, size: 14),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    unawaited(_loadEntries());
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          constraints: const BoxConstraints(minHeight: 32, maxHeight: 32),
                          prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ),
                    ),
                  ] else
                    Row(
                      children: [
                        Wrap(
                          spacing: 6,
                          children: [
                            _buildFilterChip('all', 'Tất cả'),
                            _buildFilterChip('image', 'Hình ảnh'),
                            _buildFilterChip('video', 'Video'),
                            _buildFilterChip('file', 'Tệp'),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 32,
                            child: TextField(
                              key: const ValueKey('remote_fs_search_input'),
                              controller: _searchCtrl,
                              style: const TextStyle(fontSize: 12),
                              textAlignVertical: TextAlignVertical.center,
                              onSubmitted: (_) => _loadEntries(),
                              decoration: InputDecoration(
                                hintText: 'Tìm theo tên tệp (Enter)...',
                                prefixIcon: const Icon(Icons.search_rounded, size: 15),
                                suffixIcon: _searchCtrl.text.isNotEmpty
                                    ? IconButton(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.close_rounded, size: 14),
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          unawaited(_loadEntries());
                                        },
                                      )
                                    : null,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                constraints: const BoxConstraints(minHeight: 32, maxHeight: 32),
                                prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // 3. Active download or saved status bar
            if (_isDownloading)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.primaryLight.withValues(alpha: 0.45)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _batchTotal > 1
                                ? 'Đang tải ($_batchIndex/$_batchTotal): $_downloadingName'
                                : 'Đang tải: $_downloadingName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${RemoteFileDownloadService.formatBytes(_receivedBytes)}'
                          '${_totalBytes > 0 ? ' / ${RemoteFileDownloadService.formatBytes(_totalBytes)}' : ''}',
                          style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: AppColors.accentCyan),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => setState(() => _cancelRequested = true),
                          child: const Text(
                            'Hủy',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.danger),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: _totalBytes > 0 ? _downloadProgress : null,
                        minHeight: 5,
                        backgroundColor: AppColors.bgDark,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accentCyan),
                      ),
                    ),
                  ],
                ),
              )
            else if (_lastSavedLocation != null)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 15, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Đã lưu tại: $_lastSavedLocation',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textWhite),
                      ),
                    ),
                    if (_lastFolderToOpen != null && !Platform.isAndroid && !Platform.isIOS) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => RemoteFileDownloadService.openLocalFolder(_lastFolderToOpen!),
                        child: const Text(
                          'Mở thư mục',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accentCyan),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            // 4. Batch selection bar
            if (_selectedPaths.isNotEmpty && !_isDownloading)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Đã chọn ${_selectedPaths.length} tệp',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.accentCyan),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => setState(() => _selectedPaths.clear()),
                      child: const Text('Bỏ chọn', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton.icon(
                      key: const ValueKey('remote_fs_batch_download_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 14),
                      label: Text('Tải ${_selectedPaths.length} tệp', style: const TextStyle(fontSize: 11.5)),
                      onPressed: () {
                        final targets = _entries.where((e) => !e.isDir && _selectedPaths.contains(e.path)).toList();
                        unawaited(_downloadEntries(targets));
                      },
                    ),
                  ],
                ),
              ),

            // 5. File / Folder List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : (_error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12, color: AppColors.danger),
                            ),
                          ),
                        )
                      : (_entries.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Text(
                                  'Thư mục này chưa có ảnh, video hay tệp nào khớp bộ lọc.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              itemCount: _entries.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 6),
                              itemBuilder: (ctx, idx) {
                                final entry = _entries[idx];
                                final isSelected = _selectedPaths.contains(entry.path);
                                final badgeLabel = entry.isDir
                                    ? 'THƯ MỤC'
                                    : (entry.isImage
                                        ? 'ẢNH'
                                        : (entry.isVideo
                                            ? 'VIDEO'
                                            : (entry.isAudio
                                                ? 'ÂM THANH'
                                                : (entry.extension.isNotEmpty
                                                    ? entry.extension.toUpperCase()
                                                    : 'TỆP'))));
                                final badgeColor = _entryColor(entry);

                                return Material(
                                  color: isSelected
                                      ? AppColors.primary.withValues(alpha: 0.14)
                                      : AppColors.inputBg,
                                  borderRadius: BorderRadius.circular(4),
                                  child: InkWell(
                                    key: ValueKey('remote_fs_entry_${entry.name}'),
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () {
                                      if (entry.isDir) {
                                        unawaited(_loadEntries(targetPath: entry.path));
                                      } else if (entry.isImage) {
                                        unawaited(
                                          showRemoteImagePreviewDialog(
                                            context: context,
                                            apiService: _api,
                                            remotePath: entry.path,
                                            fileName: entry.name,
                                            isSecondaryMode: widget.isSecondaryMode,
                                            remoteUri: _thumbnailUriFor(entry.path),
                                            remoteHeaders: _remoteHeaders,
                                          ),
                                        );
                                      } else {
                                        unawaited(_downloadEntries([entry]));
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isSelected
                                              ? AppColors.primaryLight.withValues(alpha: 0.6)
                                              : AppColors.borderDark,
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          if (!entry.isDir)
                                            SizedBox(
                                              width: 26,
                                              height: 26,
                                              child: Checkbox(
                                                value: isSelected,
                                                visualDensity: VisualDensity.compact,
                                                activeColor: AppColors.primaryLight,
                                                onChanged: _isDownloading
                                                    ? null
                                                    : (v) {
                                                        setState(() {
                                                          if (v == true) {
                                                            _selectedPaths.add(entry.path);
                                                          } else {
                                                            _selectedPaths.remove(entry.path);
                                                          }
                                                        });
                                                      },
                                              ),
                                            ),
                                          if (!entry.isDir) const SizedBox(width: 4),
                                          _buildLeadingVisual(entry),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  entry.name,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.textWhite,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: badgeColor.withValues(alpha: 0.14),
                                                        borderRadius: BorderRadius.circular(3),
                                                      ),
                                                      child: Text(
                                                        badgeLabel,
                                                        style: TextStyle(
                                                          fontSize: 9.5,
                                                          fontWeight: FontWeight.bold,
                                                          color: badgeColor,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      entry.formattedSize,
                                                      style: const TextStyle(
                                                        fontSize: 10.5,
                                                        fontFamily: 'monospace',
                                                        color: AppColors.textMuted,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (entry.isDir)
                                            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted)
                                          else
                                            IconButton(
                                              key: ValueKey('remote_fs_download_${entry.name}'),
                                              tooltip: 'Tải về máy',
                                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                              padding: EdgeInsets.zero,
                                              icon: const Icon(
                                                Icons.download_rounded,
                                                size: 18,
                                                color: AppColors.accentCyan,
                                              ),
                                              onPressed: _isDownloading ? null : () => _downloadEntries([entry]),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ))),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thẻ hiển thị nhanh các ảnh, video hoặc tệp mà Agent vừa xuất ra trong câu trả lời Chat để bấm xem/tải về ngay.
class RemoteChatDetectedFilesBar extends StatefulWidget {
  final List<String> paths;
  final bool isSecondaryMode;
  final ApiService apiService;

  const RemoteChatDetectedFilesBar({
    super.key,
    required this.paths,
    required this.isSecondaryMode,
    required this.apiService,
  });

  @override
  State<RemoteChatDetectedFilesBar> createState() => _RemoteChatDetectedFilesBarState();
}

class _RemoteChatDetectedFilesBarState extends State<RemoteChatDetectedFilesBar> {
  String? _remoteBaseOrigin;
  Map<String, String>? _remoteHeaders;

  @override
  void initState() {
    super.initState();
    _loadHeadersIfSecondary();
  }

  Future<void> _loadHeadersIfSecondary() async {
    if (!widget.isSecondaryMode) return;
    final probe = await widget.apiService.buildRemoteFileRequest('__probe__', inline: true);
    if (probe != null && mounted) {
      setState(() {
        _remoteBaseOrigin = '${probe.uri.scheme}://${probe.uri.authority}${probe.uri.path}';
        _remoteHeaders = probe.headers;
      });
    }
  }

  Uri? _thumbUri(String filePath) {
    if (_remoteBaseOrigin == null) return null;
    return Uri.parse('$_remoteBaseOrigin?path=${Uri.encodeQueryComponent(filePath)}&inline=1');
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isSecondaryMode) return const SizedBox.shrink();
    final visiblePaths = widget.paths.take(8).toList();
    if (visiblePaths.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tệp trên máy chính (bấm để xem / tải về):',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: visiblePaths.map((filePath) {
              final name = p.basename(filePath);
              final kind = RemoteFsEntry.detectKind(filePath);
              final isImage = kind == 'image';
              final isVideo = kind == 'video';
              final ext = p.extension(name).replaceFirst('.', '').toUpperCase();
              final uri = widget.isSecondaryMode ? _thumbUri(filePath) : null;

              return Material(
                color: AppColors.bgDark,
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    if (isImage) {
                      unawaited(
                        showRemoteImagePreviewDialog(
                          context: context,
                          apiService: widget.apiService,
                          remotePath: filePath,
                          fileName: name,
                          isSecondaryMode: widget.isSecondaryMode,
                          remoteUri: uri,
                          remoteHeaders: _remoteHeaders,
                        ),
                      );
                    } else {
                      unawaited(
                        showStreamingDownloadDialog(
                          context: context,
                          apiService: widget.apiService,
                          remotePath: filePath,
                          fileName: name,
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isImage)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: Container(
                              width: 30,
                              height: 30,
                              color: AppColors.cardBg,
                              child: widget.isSecondaryMode
                                  ? (uri != null
                                      ? Image.network(
                                          uri.toString(),
                                          headers: _remoteHeaders,
                                          fit: BoxFit.cover,
                                          cacheWidth: 96,
                                          errorBuilder: (_, _, _) =>
                                              const Icon(Icons.image_rounded, size: 15, color: AppColors.accent),
                                        )
                                      : const Icon(Icons.image_rounded, size: 15, color: AppColors.accent))
                                  : Image.file(
                                      File(filePath),
                                      fit: BoxFit.cover,
                                      cacheWidth: 96,
                                      errorBuilder: (_, _, _) =>
                                          const Icon(Icons.image_rounded, size: 15, color: AppColors.accent),
                                    ),
                            ),
                          )
                        else
                          Icon(
                            isVideo ? Icons.movie_rounded : Icons.insert_drive_file_rounded,
                            size: 16,
                            color: isVideo ? AppColors.accentCyan : AppColors.warning,
                          ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textWhite,
                                ),
                              ),
                              Text(
                                isImage ? 'ẢNH' : (isVideo ? 'VIDEO' : (ext.isNotEmpty ? ext : 'TỆP')),
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: isImage
                                      ? AppColors.accent
                                      : (isVideo ? AppColors.accentCyan : AppColors.textMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => showStreamingDownloadDialog(
                            context: context,
                            apiService: widget.apiService,
                            remotePath: filePath,
                            fileName: name,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.download_rounded, size: 15, color: AppColors.accentCyan),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
