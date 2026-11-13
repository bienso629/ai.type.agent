import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_pty_desktop/flutter_pty.dart';
import 'package:xterm/xterm.dart';
import 'server_model.dart';

enum TerminalSplitDirection {
  none,
  horizontal,
  vertical,
}

class TerminalPaneItem {
  final String id;
  String title;
  bool isRemoteSsh;
  ServerModel? server;
  late final Terminal terminal;
  late final TerminalController controller;
  late final ScrollController scrollController;
  late final FocusNode focusNode;
  Pty? pty;
  Process? fallbackProcess;
  SSHClient? sshClient;
  SSHSession? sshSession;
  bool isConnected = false;
  bool isConnecting = false;

  String? workingDirectory;

  /// Lenh se tu dong chay ngay sau khi PTY khoi tao xong
  String? initialCommand;

  // Split state specifically for this window/pane
  TerminalSplitDirection splitDirection = TerminalSplitDirection.none;
  TerminalPaneItem? childPane;

  TerminalPaneItem({
    required this.id,
    required this.title,
    this.isRemoteSsh = false,
    this.server,
    this.workingDirectory,
    this.initialCommand,
  }) {
    focusNode = FocusNode();
    terminal = Terminal(
      maxLines: 10000,
    );
    controller = TerminalController();
    scrollController = ScrollController();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'isRemoteSsh': isRemoteSsh,
      'server': server?.toJson(),
      'workingDirectory': workingDirectory,
      'splitDirection': splitDirection.name,
      'childPane': childPane?.toJson(),
    };
  }

  static TerminalPaneItem fromJson(Map<String, dynamic> json) {
    ServerModel? srv;
    if (json['server'] != null) {
      try {
        srv = ServerModel.fromJson(Map<String, dynamic>.from(json['server']));
      } catch (_) {}
    }

    final item = TerminalPaneItem(
      id: json['id'] ?? 'pane_${DateTime.now().millisecondsSinceEpoch}',
      title: json['title'] ?? (json['isRemoteSsh'] == true ? (srv?.name ?? 'SSH Server') : 'Local Machine'),
      isRemoteSsh: json['isRemoteSsh'] == true,
      server: srv,
      workingDirectory: json['workingDirectory'] as String?,
    );

    final splitName = json['splitDirection'] as String?;
    if (splitName != null) {
      item.splitDirection = TerminalSplitDirection.values.firstWhere(
        (e) => e.name == splitName,
        orElse: () => TerminalSplitDirection.none,
      );
    }

    if (json['childPane'] != null) {
      try {
        item.childPane = TerminalPaneItem.fromJson(Map<String, dynamic>.from(json['childPane']));
      } catch (_) {}
    }

    return item;
  }

  void cleanup() {
    try {
      pty?.kill();
      pty = null;
    } catch (_) {}
    try {
      fallbackProcess?.kill();
      fallbackProcess = null;
    } catch (_) {}
    try {
      sshSession?.close();
      sshSession = null;
    } catch (_) {}
    try {
      sshClient?.close();
      sshClient = null;
    } catch (_) {}

    childPane?.cleanup();
  }

  void dispose() {
    controller.dispose();
    scrollController.dispose();
    focusNode.dispose();
    cleanup();
    childPane?.dispose();
  }
}
