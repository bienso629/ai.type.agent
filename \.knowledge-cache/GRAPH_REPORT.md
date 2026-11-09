# Graph Report - agent-coder  (2026-11-09)

## Corpus Check
- 126 files · ~123,134 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 77 file(s) not represented in the graph (top: (none) 14, .xml 8, .xcconfig 8)

## Summary
- 2188 nodes · 2848 edges · 105 communities (78 shown, 27 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 18 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `add63521`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.


## Community Hubs (Navigation)
- flutter_pty_bindings_generated.dart
- chat_screen.dart
- flutter_pty_unix.c
- terminal_screen.dart
- work_schedule_dialog.dart
- dart_api.h
- storage_service.dart
- GeneratedPluginRegistrant.swift
- FlutterWindow
- api_service.dart
- chat_message.dart
- chat_provider.dart
- my_application.cc
- session_list_sidebar.dart
- server_provider.dart
- app_theme.dart
- Pointer
- knowledge_index_service.dart
- native_ai_service.dart
- flutter_pty.dart
- settings_screen.dart
- ServerProvider
- server_model.dart
- database_service.dart
- stealth_vault.dart
- metrics_model.dart
- flutter_pty/pubspec.yaml
- with
- with
- with
- dependencies
- native_ssh_service.dart
- servers_screen.dart
- logs_provider.dart
- custom_window_frame.dart
- api_constants.dart
- logs_dialog.dart
- local_config_service.dart
- env
- State
- dashboard_screen.dart
- metrics_provider.dart
- dart:io
- auth_provider.dart
- attachment_item.dart
- gateway_provider.dart
- win32_window.cpp
- app_toast.dart
- Win32Window
- chat_session.dart
- CHANGELOG.md
- tadu_dialog.dart
- flutter_launcher_icons
- files_screen.dart
- ../../core/theme/app_theme.dart
- dart:convert
- ffigen.yaml
- clipboard_service.dart
- utils.cpp
- pdf_export_service.dart
- ServerProvider
- model_picker_dialog.dart
- main.dart
- package:flutter/material.dart
- Dart_NativeArgument_Value
- manifest.json
- system_notification_service.dart
- pubspec.yaml
- .MessageHandler
- ffi.Struct
- file_item.dart
- flutter_pty
- 🚀 Hướng Dẫn Chạy & Build App
- analysis_options.yaml
- dev_dependencies
- ffi.Opaque
- Dart_CodeObserver
- string
- MainActivity.kt
- Int64
- windows
- Dart_NativeArgument_Descriptor
- UnnamedUnion1
- LaunchImage.imageset/README.md
- CodeElementBuilder
- WorkScheduleDialog
- flutter
- flutter_pty_desktop
- build_deb.sh
- build_linux.sh
- build_macos.sh
- install_ubuntu.sh
- Point

## God Nodes (most connected - your core abstractions)
1. `ServerProvider` - 48 edges
2. `dependencies` - 28 edges
3. `ChatProvider` - 21 edges
4. `Win32Window` - 21 edges
5. `ApiService` - 12 edges
6. `Dart_NativeArgument_Value` - 11 edges
7. `with` - 10 edges
8. `with` - 10 edges
9. `with` - 10 edges
10. `FlutterWindow` - 10 edges

## Surprising Connections (you probably didn't know these)
- `build` --references--> `ServerProvider`  [EXTRACTED]
  lib/screens/files/files_screen.dart → lib/providers/server_provider.dart
- `_buildMobileLayout` --references--> `ServerProvider`  [EXTRACTED]
  lib/screens/main_navigation_screen.dart → lib/providers/server_provider.dart
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  windows/runner/main.cpp → windows/runner/utils.cpp
- `build` --references--> `AuthProvider`  [EXTRACTED]
  lib/screens/auth/login_screen.dart → lib/providers/auth_provider.dart
- `_handleLogin` --references--> `AuthProvider`  [EXTRACTED]
  lib/screens/auth/login_screen.dart → lib/providers/auth_provider.dart

## Import Cycles
- None detected.

## Communities (105 total, 27 thin omitted)

### Community 0 - "flutter_pty_bindings_generated.dart"
Cohesion: 0.01
Nodes (113): ackRead, arguments, as_array, as_bool, as_capability, as_double, as_external_typed_data, as_int32 (+105 more)

### Community 1 - "chat_screen.dart"
Cohesion: 0.01
Nodes (125): add_inline_runs, _aiPromptController, _api, _apiService, _attachedFiles, _buildGreetingBubble, _buildInputBar, _buildLoadMoreBanner (+117 more)

### Community 2 - "flutter_pty_unix.c"
Cohesion: 0.06
Nodes (23): pty_ack_read(), pty_create(), pty_error(), pty_getpid(), pty_resize(), pty_write(), set_environment(), start_read_thread() (+15 more)

### Community 3 - "terminal_screen.dart"
Cohesion: 0.03
Nodes (54): _activePaneIndex, _activeSubPaneId, _addWindow, _buildKeyBtn, _buildPaneCard, _buildSplitWorkspace, childPane, cleanup (+46 more)

### Community 4 - "work_schedule_dialog.dart"
Cohesion: 0.03
Nodes (60): _aiSub, _api, _applySchedule, build, _buildBody, _buildCalendar, _buildDayCell, _buildDayPanel (+52 more)

### Community 5 - "dart_api.h"
Cohesion: 0.04
Nodes (48): Dart_CoreType_Id, Dart_CreateLoadingUnitCallback, Dart_DeferredLoadHandler, Dart_EntropySource, Dart_EnvironmentCallback, Dart_FfiNativeResolver, Dart_FileCloseCallback, Dart_FileOpenCallback (+40 more)

### Community 6 - "storage_service.dart"
Cohesion: 0.04
Nodes (45): addRecentScope, clearAuth, clearRecentScopes, getActiveServerId, getAuthToken, getBiometricEnabled, getDefaultModel, getGatewayUrl (+37 more)

### Community 7 - "GeneratedPluginRegistrant.swift"
Cohesion: 0.05
Nodes (21): Cocoa, file_picker, Flutter, FlutterMacOS, Foundation, AppDelegate, SceneDelegate, RunnerTests (+13 more)

### Community 8 - "FlutterWindow"
Cohesion: 0.12
Nodes (4): FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 9 - "api_service.dart"
Cohesion: 0.04
Nodes (41): _ai, checkHealth, clearChatHistory, _client, createChatSession, _db, deleteAllChatSessions, deleteChatSession (+33 more)

### Community 10 - "chat_message.dart"
Cohesion: 0.08
Nodes (22): attachments, ChatHistoryResult, ChatMessageModel, command, content, createdAt, fromJson, hasMore (+14 more)

### Community 11 - "chat_provider.dart"
Cohesion: 0.05
Nodes (41): anySessionGenerating, _api, clearHistory, createNewSession, _currentSession, currentSessionDocFiles, currentSessionScope, currentStatus (+33 more)

### Community 12 - "my_application.cc"
Cohesion: 0.06
Nodes (15): fl_register_plugins(), main(), first_frame_cb(), my_application_activate(), my_application_class_init(), my_application_dispose(), my_application_init(), my_application_local_command_line() (+7 more)

### Community 13 - "session_list_sidebar.dart"
Cohesion: 0.05
Nodes (40): _animCtrl, _apiService, backgroundColor, child, _close, createState, dispose, _dragExtent (+32 more)

### Community 14 - "server_provider.dart"
Cohesion: 0.05
Nodes (35): _activeAgent, addOrUpdateServer, _api, _checkPreloadState, _cliScanner, _cloudAiModel, deleteServer, _error (+27 more)

### Community 15 - "app_theme.dart"
Cohesion: 0.05
Nodes (30): accent, accentCyan, AppColors, AppRadius, AppTheme, bgDark, borderDark, borderLight (+22 more)

### Community 16 - "Pointer"
Cohesion: 0.06
Nodes (33): Dart_CloseNativePort_Type, Dart_DeleteFinalizableHandle_Type, Dart_DeletePersistentHandle_Type, Dart_DeleteWeakPersistentHandle_Type, Dart_EnterScope_Type, Dart_ErrorGetException_Type, Dart_ErrorGetStackTrace_Type, Dart_ErrorHasException_Type (+25 more)

### Community 17 - "knowledge_index_service.dart"
Cohesion: 0.06
Nodes (29): _builtCommit, cacheDirFor, cacheDirName, _currentScope, dispose, ensureRuntime, _entryScriptPath, _gitHead (+21 more)

### Community 18 - "native_ai_service.dart"
Cohesion: 0.06
Nodes (28): _attachmentEchoRegex, _buildKnowledgeGuide, buildKnowledgeGuideForTest, _configService, _dbService, disposeAgyWorkers, _endsCleanly, _executeCommand (+20 more)

### Community 19 - "flutter_pty.dart"
Cohesion: 0.06
Nodes (22): ackRead, arguments, _bindings, _dylib, _ensureInitialized, error, executable, exitCode (+14 more)

### Community 20 - "settings_screen.dart"
Cohesion: 0.07
Nodes (26): _addGoogleStudioKeysFromInput, _api, _apiKeyCtrl, _applyGoogleModelPreset, _applyPreset, _baseUrlCtrl, _buildGoogleModelChip, _buildInfoBox (+18 more)

### Community 21 - "ServerProvider"
Cohesion: 0.12
Nodes (11): _activeTabKey, build, _buildDesktopLayout, _buildMobileLayout, createState, _getVisibleTabs, initState, _isSidebarCollapsed (+3 more)

### Community 22 - "server_model.dart"
Cohesion: 0.07
Nodes (25): agentMode, aiModel, apiPort, cliBinary, copyWith, _counter, findMatchingServer, fromJson (+17 more)

### Community 23 - "database_service.dart"
Cohesion: 0.07
Nodes (23): clearChat, createSession, _currentUserKey, _db, deleteAllSessions, deleteSession, _enc, getCliConversationId (+15 more)

### Community 24 - "stealth_vault.dart"
Cohesion: 0.07
Nodes (25): brandQuery, brandTitle, brandUpper, brandVersion, cacheDirName, configHomeDir, _d, entryScriptName (+17 more)

### Community 25 - "metrics_model.dart"
Cohesion: 0.07
Nodes (27): cpuPercent, diskAvail, diskPercent, diskTotal, diskUsed, fromJson, lastSync, loadAvg (+19 more)

### Community 26 - "flutter_pty/pubspec.yaml"
Cohesion: 0.07
Nodes (27): ffiPlugin, dependencies, ffi, flutter, description, dev_dependencies, ffigen, flutter_lints (+19 more)

### Community 27 - "with"
Cohesion: 0.07
Nodes (26): name, runs-on, steps, jobs, build-windows, name, on, push (+18 more)

### Community 28 - "with"
Cohesion: 0.08
Nodes (25): name, runs-on, steps, jobs, build-linux, name, on, push (+17 more)

### Community 29 - "with"
Cohesion: 0.08
Nodes (25): name, runs-on, steps, jobs, build-macos, name, on, push (+17 more)

### Community 30 - "dependencies"
Cohesion: 0.08
Nodes (26): dependencies, crypto, cupertino_icons, dartssh2, encrypt, file_picker, fl_chart, flutter_markdown (+18 more)

### Community 31 - "native_ssh_service.dart"
Cohesion: 0.08
Nodes (20): 1, _configService, downloadFile, executeCommand, executeServiceAction, fi, _formatBytes, _formatSpeed (+12 more)

### Community 32 - "servers_screen.dart"
Cohesion: 0.09
Nodes (20): _api, createState, _deployingServerId, _deployLogs, _deployScrollCtrls, _deploySubs, dispose, _executeSystemdAction (+12 more)

### Community 33 - "logs_provider.dart"
Cohesion: 0.09
Nodes (20): _api, dispose, fetchLogs, isAutoRefresh, _isLoading, isLocal, _lines, _logs (+12 more)

### Community 34 - "custom_window_frame.dart"
Cohesion: 0.05
Nodes (35): AttachmentHoverPreview, _AttachmentHoverPreviewState, build, _buildErrorPlaceholder, _buildImageWidget, child, createState, dispose (+27 more)

### Community 35 - "api_constants.dart"
Cohesion: 0.08
Nodes (22): ApiConstants, defaultGatewayUrl, epChat, epChatClear, epChatHistory, epChatSessions, epConfig, epFsDownload (+14 more)

### Community 36 - "logs_dialog.dart"
Cohesion: 0.13
Nodes (17): LogsProvider, build, _buildFilterChip, createState, dispose, initState, LogsDialog, _LogsDialogState (+9 more)

### Community 37 - "local_config_service.dart"
Cohesion: 0.09
Nodes (17): addOrUpdateServer, _cachedConfig, _currentUserKey, defaultRawConfig, deleteServer, _enc, exportServersJson, _extractServersList (+9 more)

### Community 38 - "env"
Cohesion: 0.09
Nodes (22): env, runs-on, steps, timeout-minutes, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_KEY_IDENTIFIER, APP_STORE_CONNECT_PRIVATE_KEY (+14 more)

### Community 39 - "State"
Cohesion: 0.11
Nodes (22): _CodeBlockWidget, _CodeBlockWidgetState, _CommandRunnerModal, _CommandRunnerModalState, _RecentQuestionItem, _RecentQuestionItemState, _ScopeDocsListDialog, _ScopeDocsListDialogState (+14 more)

### Community 40 - "dashboard_screen.dart"
Cohesion: 0.12
Nodes (16): MetricsProvider, build, _buildChartCard, _buildGaugeCard, _buildInfoItem, _buildServerSummaryCard, _buildServiceRow, _buildServicesCard (+8 more)

### Community 41 - "metrics_provider.dart"
Cohesion: 0.09
Nodes (17): _api, _cpuHistory, dispose, _error, executeServiceAction, fetchMetrics, getServiceStatus, _isLoading (+9 more)

### Community 42 - "dart:io"
Cohesion: 0.10
Nodes (12): binary, _candidateAgents, CliScannerService, _getSearchPaths, id, _instance, label, LocalCliAgent (+4 more)

### Community 43 - "auth_provider.dart"
Cohesion: 0.10
Nodes (18): DatabaseService, LocalConfigService, _authToken, checkAuthStatus, clearError, _client, _db, _errorMessage (+10 more)

### Community 44 - "attachment_item.dart"
Cohesion: 0.08
Nodes (22): _checkIsImage, _checkIsMedia, content, copyWith, downloadProgress, error, fromBytes, fromFile (+14 more)

### Community 45 - "gateway_provider.dart"
Cohesion: 0.11
Nodes (13): StorageService, _api, _errorMessage, GatewayStatus, _gatewayUrl, init, isConnected, _pingMs (+5 more)

### Community 46 - "win32_window.cpp"
Cohesion: 0.15
Nodes (6): EnableNonClientDpiScaling, Scale(), Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, instance_

### Community 47 - "app_toast.dart"
Cohesion: 0.05
Nodes (35): _animCtrl, AppToast, build, createState, dispose, duration, error, _fadeAnim (+27 more)

### Community 48 - "Win32Window"
Cohesion: 0.18
Nodes (7): Size, height, width, Win32Window, child_content_, quit_on_close_, window_handle_

### Community 49 - "chat_session.dart"
Cohesion: 0.12
Nodes (15): answerCount, ChatSessionModel, copyWith, createdAt, docFiles, fromJson, id, isPinned (+7 more)

### Community 50 - "CHANGELOG.md"
Cohesion: 0.12
Nodes (15): 0.0.1, 0.0.2, 0.0.3, 0.0.4, 0.0.5, 0.0.6, 0.0.7, 0.1.0 (+7 more)

### Community 52 - "tadu_dialog.dart"
Cohesion: 0.17
Nodes (8): actions, build, content, maxHeight, maxWidth, minWidth, onClose, title

### Community 53 - "flutter_launcher_icons"
Cohesion: 0.14
Nodes (14): flutter_launcher_icons, android, image_path, ios, linux, macos, min_sdk_android, web (+6 more)

### Community 54 - "files_screen.dart"
Cohesion: 0.18
Nodes (9): ApiService, _api, build, createState, _currentPath, _directories, initState, _isLoading (+1 more)

### Community 55 - "../../core/theme/app_theme.dart"
Cohesion: 0.21
Nodes (9): GatewayProvider, build, createState, dispose, GatewayConfigScreen, _GatewayConfigScreenState, initState, _tokenCtrl (+1 more)

### Community 56 - "dart:convert"
Cohesion: 0.15
Nodes (6): _cachedKey, decryptValue, EncryptionService, encryptValue, getCryptoKey, _instance

### Community 57 - "ffigen.yaml"
Cohesion: 0.15
Nodes (12): comments, length, style, description, functions, includes, headers, entry-points (+4 more)

### Community 58 - "clipboard_service.dart"
Cohesion: 0.18
Nodes (6): 1, ClipboardService, getClipboardImage, _getLinuxClipboardImage, _getMacClipboardImage, _getWindowsClipboardImage

### Community 59 - "utils.cpp"
Cohesion: 0.19
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 60 - "pdf_export_service.dart"
Cohesion: 0.15
Nodes (5): _buildInlineSpans, _cleanEmoji, exportMessageToPdf, _loadLogoImage, PdfExportService

### Community 61 - "ServerProvider"
Cohesion: 0.10
Nodes (26): ChatProvider, ServerProvider, _applyInlineDirAsScope, build, _buildMessageItem, ChatScreen, _ChatScreenState, _handleInputKeyEvent (+18 more)

### Community 62 - "model_picker_dialog.dart"
Cohesion: 0.17
Nodes (11): build, _buildModelCard, createState, dispose, ModelPickerDialog, _ModelPickerDialogState, _searchCtrl, _searchQuery (+3 more)

### Community 65 - "package:flutter/material.dart"
Cohesion: 0.09
Nodes (17): AppLogo, borderRadius, build, fit, size, build, ChatAvatar, _initials (+9 more)

### Community 66 - "Dart_NativeArgument_Value"
Cohesion: 0.18
Nodes (11): Dart_Handle, Dart_NativeArgument_Value, as_bool, as_double, as_instance, as_int32, as_int64, as_native_fields (+3 more)

### Community 67 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 68 - "system_notification_service.dart"
Cohesion: 0.20
Nodes (5): focusAppWindow, navigatorKey, notifyReplyFinished, _resolveAppIcon, SystemNotificationService

### Community 69 - "pubspec.yaml"
Cohesion: 0.20
Nodes (9): description, environment, sdk, flutter, assets, uses-material-design, name, publish_to (+1 more)

### Community 71 - "ffi.Struct"
Cohesion: 0.22
Nodes (8): _Dart_CObject, PtyOptions, UnnamedStruct1, UnnamedStruct2, UnnamedStruct3, UnnamedStruct4, UnnamedStruct5, UnnamedStruct6

### Community 72 - "file_item.dart"
Cohesion: 0.22
Nodes (8): FileItemModel, fromPath, isDirectory, modifiedAt, name, path, permissions, size

### Community 73 - "flutter_pty"
Cohesion: 0.22
Nodes (8): Binding to native code, Buidling and bundling native code, Flutter help, flutter_pty, Invoking native code, Platform, Project stucture, Quick start

### Community 74 - "🚀 Hướng Dẫn Chạy & Build App"
Cohesion: 0.25
Nodes (7): 1. Cài đặt Flutter & Dependencies, 2. Chạy ứng dụng trên Thiết bị / Giả lập, 3. Đóng gói file cài đặt Android APK, 4. Đóng gói cho iOS, 📱 AI Type Agent - Flutter Mobile App, 🚀 Hướng Dẫn Chạy & Build App, 🌟 Tính Năng Chính

### Community 75 - "analysis_options.yaml"
Cohesion: 0.29
Nodes (6): analyzer, errors, deprecated_member_use, include, linter, rules

### Community 76 - "dev_dependencies"
Cohesion: 0.40
Nodes (5): dev_dependencies, flutter_launcher_icons, flutter_lints, flutter_test, sdk

### Community 77 - "ffi.Opaque"
Cohesion: 0.50
Nodes (3): _Dart_FinalizableHandle, _Dart_WeakPersistentHandle, PtyHandle

### Community 78 - "Dart_CodeObserver"
Cohesion: 0.50
Nodes (4): Dart_CodeObserver, data, on_new_code, Dart_OnNewCodeCallback

### Community 82 - "windows"
Cohesion: 0.67
Nodes (3): windows, generate, image_path

### Community 83 - "Dart_NativeArgument_Descriptor"
Cohesion: 0.67
Nodes (3): Dart_NativeArgument_Descriptor, index, type

### Community 104 - "Point"
Cohesion: 0.50
Nodes (3): Point, x, y

## Knowledge Gaps
- **1182 isolated node(s):** `ApiConstants`, `defaultGatewayUrl`, `epConfig`, `epServers`, `epServersUpdate` (+1177 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1658 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **27 thin communities (<3 nodes) omitted from report** — run truy van do thi to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `StorageService` connect `gateway_provider.dart` to `chat_screen.dart`, `terminal_screen.dart`, `storage_service.dart`, `api_service.dart`, `auth_provider.dart`, `server_provider.dart`?**
  _High betweenness centrality (0.032) - this node is a cross-community bridge._
- **What connects `ApiConstants`, `defaultGatewayUrl`, `epConfig` to the rest of the system?**
  _1182 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `flutter_pty_bindings_generated.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.012658227848101266 - nodes in this community are weakly interconnected._
- **Why does `ApiService` connect `files_screen.dart` to `servers_screen.dart`, `logs_provider.dart`, `chat_screen.dart`, `work_schedule_dialog.dart`, `api_service.dart`, `metrics_provider.dart`, `chat_provider.dart`, `gateway_provider.dart`, `server_provider.dart`, `session_list_sidebar.dart`, `settings_screen.dart`?**
  _High betweenness centrality (0.018) - this node is a cross-community bridge._
- **Should `chat_screen.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.013793103448275862 - nodes in this community are weakly interconnected._
- **Why does `ServerProvider` connect `ServerProvider` to `servers_screen.dart`, `chat_screen.dart`, `terminal_screen.dart`, `logs_dialog.dart`, `State`, `dashboard_screen.dart`, `session_list_sidebar.dart`, `server_provider.dart`, `settings_screen.dart`, `ServerProvider`, `files_screen.dart`, `../../core/theme/app_theme.dart`, `model_picker_dialog.dart`?**
  _High betweenness centrality (0.018) - this node is a cross-community bridge._
- **Should `flutter_pty_unix.c` be split into smaller, more focused modules?**
  _Cohesion score 0.06412583182093164 - nodes in this community are weakly interconnected._