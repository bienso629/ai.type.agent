# Graph Report - agent-coder  (2026-10-30)

## Corpus Check
- 119 files · ~120,092 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 66 file(s) not represented in the graph (top: (none) 11, .xml 8, .xcconfig 8)

## Summary
- 2119 nodes · 2768 edges · 106 communities (79 shown, 27 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 18 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `22cd6a21`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- flutter_pty_bindings_generated.dart
- chat_screen.dart
- work_schedule_dialog.dart
- terminal_screen.dart
- flutter_pty_unix.c
- dart_api.h
- storage_service.dart
- GeneratedPluginRegistrant.swift
- app_toast.dart
- api_service.dart
- chat_provider.dart
- my_application.cc
- session_list_sidebar.dart
- server_provider.dart
- app_theme.dart
- Pointer
- attachment_item.dart
- flutter_pty.dart
- settings_screen.dart
- server_model.dart
- database_service.dart
- native_ai_service.dart
- metrics_model.dart
- ServerProvider
- flutter_pty/pubspec.yaml
- with
- chat_message.dart
- with
- with
- dependencies
- clipboard_service.dart
- native_ssh_service.dart
- servers_screen.dart
- chat_avatar.dart
- logs_provider.dart
- custom_window_frame.dart
- api_constants.dart
- dashboard_screen.dart
- env
- auth_provider.dart
- local_config_service.dart
- logs_dialog.dart
- package:flutter/material.dart
- metrics_provider.dart
- State
- main_navigation_screen.dart
- win32_window.cpp
- FlutterWindow
- attachment_hover_preview.dart
- gateway_provider.dart
- chat_session.dart
- cli_scanner_service.dart
- flutter_launcher_icons
- core/theme/app_theme.dart
- model_picker_dialog.dart
- ffigen.yaml
- tadu_dialog.dart
- utils.cpp
- Win32Window
- files_screen.dart
- Dart_NativeArgument_Value
- manifest.json
- pubspec.yaml
- .MessageHandler
- ffi.Struct
- file_item.dart
- analysis_options.yaml
- CHANGELOG.md
- dev_dependencies
- ffi.Opaque
- Dart_CodeObserver
- Point
- dart:convert
- MainActivity.kt
- Int64
- windows
- Dart_NativeArgument_Descriptor
- UnnamedUnion1
- CodeElementBuilder
- WorkScheduleDialog
- pdf_export_service.dart
- main.dart
- flutter
- flutter_pty_desktop
- build_deb.sh
- build_linux.sh
- build_macos.sh
- install_ubuntu.sh
- flutter_pty
- app_logo.dart
- 🚀 Hướng Dẫn Chạy & Build App
- dart:io
- StatelessWidget
- LaunchImage.imageset/README.md

## God Nodes (most connected - your core abstractions)
1. `ServerProvider` - 48 edges
2. `dependencies` - 28 edges
3. `ChatProvider` - 22 edges
4. `Win32Window` - 21 edges
5. `ApiService` - 12 edges
6. `Dart_NativeArgument_Value` - 11 edges
7. `with` - 10 edges
8. `with` - 10 edges
9. `with` - 10 edges
10. `FlutterWindow` - 10 edges

## Surprising Connections (you probably didn't know these)
- `_showEditSessionDialog` --references--> `ServerProvider`  [EXTRACTED]
  lib/screens/chat/widgets/session_list_sidebar.dart → lib/providers/server_provider.dart
- `build` --references--> `ServerProvider`  [EXTRACTED]
  lib/screens/files/files_screen.dart → lib/providers/server_provider.dart
- `_buildMobileLayout` --references--> `ServerProvider`  [EXTRACTED]
  lib/screens/main_navigation_screen.dart → lib/providers/server_provider.dart
- `build` --references--> `ServerProvider`  [EXTRACTED]
  lib/screens/servers/servers_screen.dart → lib/providers/server_provider.dart
- `_showAddServerDialog` --references--> `ServerProvider`  [EXTRACTED]
  lib/screens/servers/servers_screen.dart → lib/providers/server_provider.dart

## Import Cycles
- None detected.

## Communities (106 total, 27 thin omitted)

### Community 0 - "flutter_pty_bindings_generated.dart"
Cohesion: 0.01
Nodes (113): ackRead, arguments, as_array, as_bool, as_capability, as_double, as_external_typed_data, as_int32 (+105 more)

### Community 1 - "chat_screen.dart"
Cohesion: 0.01
Nodes (127): add_inline_runs, _aiPromptController, _api, _apiService, _attachedFiles, _buildGreetingBubble, _buildInputBar, _buildLoadMoreBanner (+119 more)

### Community 2 - "work_schedule_dialog.dart"
Cohesion: 0.03
Nodes (60): _aiSub, _api, _applySchedule, build, _buildBody, _buildCalendar, _buildDayCell, _buildDayPanel (+52 more)

### Community 3 - "terminal_screen.dart"
Cohesion: 0.03
Nodes (56): _activePaneIndex, _activeSubPaneId, _addWindow, build, _buildKeyBtn, _buildPaneCard, _buildSplitWorkspace, childPane (+48 more)

### Community 4 - "flutter_pty_unix.c"
Cohesion: 0.05
Nodes (24): pty_ack_read(), pty_create(), pty_error(), pty_getpid(), pty_resize(), pty_write(), set_environment(), start_read_thread() (+16 more)

### Community 5 - "dart_api.h"
Cohesion: 0.04
Nodes (48): Dart_CoreType_Id, Dart_CreateLoadingUnitCallback, Dart_DeferredLoadHandler, Dart_EntropySource, Dart_EnvironmentCallback, Dart_FfiNativeResolver, Dart_FileCloseCallback, Dart_FileOpenCallback (+40 more)

### Community 6 - "storage_service.dart"
Cohesion: 0.04
Nodes (45): addRecentScope, clearAuth, clearRecentScopes, getActiveServerId, getAuthToken, getBiometricEnabled, getDefaultModel, getGatewayUrl (+37 more)

### Community 7 - "GeneratedPluginRegistrant.swift"
Cohesion: 0.05
Nodes (21): Cocoa, file_picker, Flutter, FlutterMacOS, Foundation, AppDelegate, SceneDelegate, RunnerTests (+13 more)

### Community 8 - "app_toast.dart"
Cohesion: 0.05
Nodes (35): _animCtrl, AppToast, build, createState, dispose, duration, error, _fadeAnim (+27 more)

### Community 9 - "api_service.dart"
Cohesion: 0.04
Nodes (41): _ai, checkHealth, clearChatHistory, _client, createChatSession, _db, deleteAllChatSessions, deleteChatSession (+33 more)

### Community 10 - "chat_provider.dart"
Cohesion: 0.05
Nodes (41): anySessionGenerating, _api, clearHistory, createNewSession, _currentSession, currentSessionDocFiles, currentSessionScope, currentStatus (+33 more)

### Community 11 - "my_application.cc"
Cohesion: 0.06
Nodes (15): fl_register_plugins(), main(), first_frame_cb(), my_application_activate(), my_application_class_init(), my_application_dispose(), my_application_init(), my_application_local_command_line() (+7 more)

### Community 12 - "session_list_sidebar.dart"
Cohesion: 0.05
Nodes (41): _animCtrl, _apiService, backgroundColor, child, _close, createState, dispose, _dragExtent (+33 more)

### Community 13 - "server_provider.dart"
Cohesion: 0.05
Nodes (35): _activeAgent, addOrUpdateServer, _api, _checkPreloadState, _cliScanner, _cloudAiModel, deleteServer, _error (+27 more)

### Community 14 - "app_theme.dart"
Cohesion: 0.05
Nodes (30): accent, accentCyan, AppColors, AppRadius, AppTheme, bgDark, borderDark, borderLight (+22 more)

### Community 15 - "Pointer"
Cohesion: 0.06
Nodes (33): Dart_CloseNativePort_Type, Dart_DeleteFinalizableHandle_Type, Dart_DeletePersistentHandle_Type, Dart_DeleteWeakPersistentHandle_Type, Dart_EnterScope_Type, Dart_ErrorGetException_Type, Dart_ErrorGetStackTrace_Type, Dart_ErrorHasException_Type (+25 more)

### Community 16 - "attachment_item.dart"
Cohesion: 0.10
Nodes (19): _checkIsImage, content, copyWith, downloadProgress, error, fromBytes, fromFile, fromJson (+11 more)

### Community 17 - "flutter_pty.dart"
Cohesion: 0.06
Nodes (22): ackRead, arguments, _bindings, _dylib, _ensureInitialized, error, executable, exitCode (+14 more)

### Community 18 - "settings_screen.dart"
Cohesion: 0.06
Nodes (28): _addGoogleStudioKeysFromInput, _api, _apiKeyCtrl, _applyGoogleModelPreset, _applyPreset, _baseUrlCtrl, build, _buildGoogleModelChip (+20 more)

### Community 19 - "server_model.dart"
Cohesion: 0.07
Nodes (25): agentMode, aiModel, apiPort, cliBinary, copyWith, _counter, findMatchingServer, fromJson (+17 more)

### Community 20 - "database_service.dart"
Cohesion: 0.07
Nodes (23): clearChat, createSession, _currentUserKey, _db, deleteAllSessions, deleteSession, _enc, getCliConversationId (+15 more)

### Community 21 - "native_ai_service.dart"
Cohesion: 0.06
Nodes (25): _attachmentEchoRegex, _buildGraphifyGuide, buildGraphifyGuideForTest, _configService, _dbService, disposeAgyWorkers, _executeCommand, _executeLocalCommand (+17 more)

### Community 22 - "metrics_model.dart"
Cohesion: 0.07
Nodes (27): cpuPercent, diskAvail, diskPercent, diskTotal, diskUsed, fromJson, lastSync, loadAvg (+19 more)

### Community 23 - "ServerProvider"
Cohesion: 0.13
Nodes (20): ChatProvider, ServerProvider, _applyInlineDirAsScope, build, _buildMessageItem, ChatScreen, _ChatScreenState, _handleInputKeyEvent (+12 more)

### Community 24 - "flutter_pty/pubspec.yaml"
Cohesion: 0.07
Nodes (27): ffiPlugin, dependencies, ffi, flutter, description, dev_dependencies, ffigen, flutter_lints (+19 more)

### Community 25 - "with"
Cohesion: 0.07
Nodes (26): name, runs-on, steps, jobs, build-windows, name, on, push (+18 more)

### Community 26 - "chat_message.dart"
Cohesion: 0.08
Nodes (22): attachments, ChatHistoryResult, ChatMessageModel, command, content, createdAt, fromJson, hasMore (+14 more)

### Community 27 - "with"
Cohesion: 0.08
Nodes (25): name, runs-on, steps, jobs, build-linux, name, on, push (+17 more)

### Community 28 - "with"
Cohesion: 0.08
Nodes (25): name, runs-on, steps, jobs, build-macos, name, on, push (+17 more)

### Community 29 - "dependencies"
Cohesion: 0.08
Nodes (26): dependencies, crypto, cupertino_icons, dartssh2, encrypt, file_picker, fl_chart, flutter_markdown (+18 more)

### Community 30 - "clipboard_service.dart"
Cohesion: 0.17
Nodes (6): 1, ClipboardService, getClipboardImage, _getLinuxClipboardImage, _getMacClipboardImage, _getWindowsClipboardImage

### Community 31 - "native_ssh_service.dart"
Cohesion: 0.08
Nodes (19): 1, _configService, downloadFile, executeCommand, executeServiceAction, fi, _formatBytes, _formatSpeed (+11 more)

### Community 32 - "servers_screen.dart"
Cohesion: 0.08
Nodes (22): _api, build, createState, _deployingServerId, _deployLogs, _deployScrollCtrls, _deploySubs, dispose (+14 more)

### Community 33 - "chat_avatar.dart"
Cohesion: 0.20
Nodes (8): build, _initials, isLocal, isUser, server, serverName, size, userName

### Community 34 - "logs_provider.dart"
Cohesion: 0.09
Nodes (21): NativeSshService, _api, dispose, fetchLogs, isAutoRefresh, _isLoading, isLocal, _lines (+13 more)

### Community 35 - "custom_window_frame.dart"
Cohesion: 0.09
Nodes (21): build, _checkMaximized, child, createState, CustomWindowFrame, _CustomWindowFrameState, dispose, icon (+13 more)

### Community 36 - "api_constants.dart"
Cohesion: 0.08
Nodes (22): ApiConstants, defaultGatewayUrl, epChat, epChatClear, epChatHistory, epChatSessions, epConfig, epFsDownload (+14 more)

### Community 37 - "dashboard_screen.dart"
Cohesion: 0.12
Nodes (16): ServerModel, MetricsProvider, build, _buildChartCard, _buildGaugeCard, _buildInfoItem, _buildServerSummaryCard, _buildServiceRow (+8 more)

### Community 38 - "env"
Cohesion: 0.09
Nodes (22): env, runs-on, steps, timeout-minutes, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_KEY_IDENTIFIER, APP_STORE_CONNECT_PRIVATE_KEY (+14 more)

### Community 39 - "auth_provider.dart"
Cohesion: 0.10
Nodes (18): DatabaseService, LocalConfigService, _authToken, checkAuthStatus, clearError, _client, _db, _errorMessage (+10 more)

### Community 40 - "local_config_service.dart"
Cohesion: 0.09
Nodes (17): addOrUpdateServer, _cachedConfig, _currentUserKey, defaultRawConfig, deleteServer, _enc, exportServersJson, _extractServersList (+9 more)

### Community 41 - "logs_dialog.dart"
Cohesion: 0.13
Nodes (17): LogsProvider, build, _buildFilterChip, createState, dispose, initState, LogsDialog, _LogsDialogState (+9 more)

### Community 42 - "package:flutter/material.dart"
Cohesion: 0.18
Nodes (5): focusAppWindow, navigatorKey, notifyReplyFinished, _resolveAppIcon, SystemNotificationService

### Community 43 - "metrics_provider.dart"
Cohesion: 0.10
Nodes (17): _api, _cpuHistory, dispose, _error, executeServiceAction, fetchMetrics, getServiceStatus, _isLoading (+9 more)

### Community 44 - "State"
Cohesion: 0.12
Nodes (20): _CodeBlockWidget, _CodeBlockWidgetState, _CommandRunnerModal, _CommandRunnerModalState, _RecentQuestionItem, _RecentQuestionItemState, _ScopeDocsListDialog, _ScopeDocsListDialogState (+12 more)

### Community 45 - "main_navigation_screen.dart"
Cohesion: 0.12
Nodes (11): _activeTabKey, build, _buildDesktopLayout, _buildMobileLayout, createState, _getVisibleTabs, initState, _isSidebarCollapsed (+3 more)

### Community 46 - "win32_window.cpp"
Cohesion: 0.18
Nodes (6): EnableNonClientDpiScaling, Scale(), Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, instance_

### Community 47 - "FlutterWindow"
Cohesion: 0.12
Nodes (4): FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 48 - "attachment_hover_preview.dart"
Cohesion: 0.12
Nodes (14): AttachmentHoverPreview, _AttachmentHoverPreviewState, build, _buildErrorPlaceholder, _buildImageWidget, child, createState, dispose (+6 more)

### Community 49 - "gateway_provider.dart"
Cohesion: 0.11
Nodes (13): StorageService, _api, _errorMessage, GatewayStatus, _gatewayUrl, init, isConnected, _pingMs (+5 more)

### Community 50 - "chat_session.dart"
Cohesion: 0.12
Nodes (15): answerCount, ChatSessionModel, copyWith, createdAt, docFiles, fromJson, id, isPinned (+7 more)

### Community 51 - "cli_scanner_service.dart"
Cohesion: 0.14
Nodes (11): binary, _candidateAgents, CliScannerService, _getSearchPaths, id, _instance, label, LocalCliAgent (+3 more)

### Community 52 - "flutter_launcher_icons"
Cohesion: 0.14
Nodes (14): flutter_launcher_icons, android, image_path, ios, linux, macos, min_sdk_android, web (+6 more)

### Community 53 - "core/theme/app_theme.dart"
Cohesion: 0.21
Nodes (9): GatewayProvider, build, createState, dispose, GatewayConfigScreen, _GatewayConfigScreenState, initState, _tokenCtrl (+1 more)

### Community 54 - "model_picker_dialog.dart"
Cohesion: 0.17
Nodes (11): build, _buildModelCard, createState, dispose, ModelPickerDialog, _ModelPickerDialogState, _searchCtrl, _searchQuery (+3 more)

### Community 55 - "ffigen.yaml"
Cohesion: 0.15
Nodes (12): comments, length, style, description, functions, includes, headers, entry-points (+4 more)

### Community 56 - "tadu_dialog.dart"
Cohesion: 0.15
Nodes (8): actions, build, content, maxHeight, maxWidth, minWidth, onClose, title

### Community 57 - "utils.cpp"
Cohesion: 0.21
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 58 - "Win32Window"
Cohesion: 0.21
Nodes (4): Win32Window, child_content_, quit_on_close_, window_handle_

### Community 59 - "files_screen.dart"
Cohesion: 0.17
Nodes (11): ApiService, _api, build, createState, _currentPath, _directories, FilesScreen, _FilesScreenState (+3 more)

### Community 61 - "Dart_NativeArgument_Value"
Cohesion: 0.18
Nodes (11): Dart_Handle, Dart_NativeArgument_Value, as_bool, as_double, as_instance, as_int32, as_int64, as_native_fields (+3 more)

### Community 62 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 63 - "pubspec.yaml"
Cohesion: 0.20
Nodes (9): description, environment, sdk, flutter, assets, uses-material-design, name, publish_to (+1 more)

### Community 65 - "ffi.Struct"
Cohesion: 0.22
Nodes (8): _Dart_CObject, PtyOptions, UnnamedStruct1, UnnamedStruct2, UnnamedStruct3, UnnamedStruct4, UnnamedStruct5, UnnamedStruct6

### Community 66 - "file_item.dart"
Cohesion: 0.22
Nodes (8): FileItemModel, fromPath, isDirectory, modifiedAt, name, path, permissions, size

### Community 67 - "analysis_options.yaml"
Cohesion: 0.29
Nodes (6): analyzer, errors, deprecated_member_use, include, linter, rules

### Community 68 - "CHANGELOG.md"
Cohesion: 0.12
Nodes (15): 0.0.1, 0.0.2, 0.0.3, 0.0.4, 0.0.5, 0.0.6, 0.0.7, 0.1.0 (+7 more)

### Community 69 - "dev_dependencies"
Cohesion: 0.40
Nodes (5): dev_dependencies, flutter_launcher_icons, flutter_lints, flutter_test, sdk

### Community 70 - "ffi.Opaque"
Cohesion: 0.50
Nodes (3): _Dart_FinalizableHandle, _Dart_WeakPersistentHandle, PtyHandle

### Community 71 - "Dart_CodeObserver"
Cohesion: 0.50
Nodes (4): Dart_CodeObserver, data, on_new_code, Dart_OnNewCodeCallback

### Community 72 - "Point"
Cohesion: 0.21
Nodes (6): Point, x, y, Size, height, width

### Community 73 - "dart:convert"
Cohesion: 0.15
Nodes (6): _cachedKey, decryptValue, EncryptionService, encryptValue, getCryptoKey, _instance

### Community 76 - "windows"
Cohesion: 0.67
Nodes (3): windows, generate, image_path

### Community 77 - "Dart_NativeArgument_Descriptor"
Cohesion: 0.67
Nodes (3): Dart_NativeArgument_Descriptor, index, type

### Community 83 - "pdf_export_service.dart"
Cohesion: 0.17
Nodes (5): _buildInlineSpans, _cleanEmoji, exportMessageToPdf, _loadLogoImage, PdfExportService

### Community 99 - "flutter_pty"
Cohesion: 0.22
Nodes (8): Binding to native code, Buidling and bundling native code, Flutter help, flutter_pty, Invoking native code, Platform, Project stucture, Quick start

### Community 100 - "app_logo.dart"
Cohesion: 0.25
Nodes (4): borderRadius, build, fit, size

### Community 101 - "🚀 Hướng Dẫn Chạy & Build App"
Cohesion: 0.25
Nodes (7): 1. Cài đặt Flutter & Dependencies, 2. Chạy ứng dụng trên Thiết bị / Giả lập, 3. Đóng gói file cài đặt Android APK, 4. Đóng gói cho iOS, 📱 AI Type Agent - Flutter Mobile App, 🚀 Hướng Dẫn Chạy & Build App, 🌟 Tính Năng Chính

### Community 103 - "StatelessWidget"
Cohesion: 0.33
Nodes (5): AppLogo, ChatAvatar, TaduDialog, AiTypeAgentApp, DashboardScreen

## Knowledge Gaps
- **1124 isolated node(s):** `ApiConstants`, `defaultGatewayUrl`, `epConfig`, `epServers`, `epServersUpdate` (+1119 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1594 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **27 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `StorageService` connect `gateway_provider.dart` to `chat_screen.dart`, `terminal_screen.dart`, `storage_service.dart`, `auth_provider.dart`, `api_service.dart`, `server_provider.dart`?**
  _High betweenness centrality (0.054) - this node is a cross-community bridge._
- **What connects `ApiConstants`, `defaultGatewayUrl`, `epConfig` to the rest of the system?**
  _1124 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `flutter_pty_bindings_generated.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.012578616352201259 - nodes in this community are weakly interconnected._
- **Why does `Win32Window` connect `Win32Window` to `.MessageHandler`, `Point`, `win32_window.cpp`, `FlutterWindow`, `flutter_window.h`?**
  _High betweenness centrality (0.019) - this node is a cross-community bridge._
- **Should `chat_screen.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.013605442176870748 - nodes in this community are weakly interconnected._
- **Why does `ServerProvider` connect `ServerProvider` to `servers_screen.dart`, `chat_screen.dart`, `terminal_screen.dart`, `dashboard_screen.dart`, `StatelessWidget`, `logs_dialog.dart`, `session_list_sidebar.dart`, `State`, `server_provider.dart`, `main_navigation_screen.dart`, `settings_screen.dart`, `model_picker_dialog.dart`, `files_screen.dart`?**
  _High betweenness centrality (0.019) - this node is a cross-community bridge._
- **Should `work_schedule_dialog.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.03125 - nodes in this community are weakly interconnected._