class ApiConstants {
  static const String defaultGatewayUrl = 'http://127.0.0.1:8765';
  static const int defaultPrimaryHostPort = 8765;
  static const int discoveryPort = 8766;

  // Remote Primary <-> Secondary Control Endpoints
  static const String epRemoteInfo = '/api/remote/info';
  static const String epRemoteEvents = '/api/remote/events';
  static const String epRemoteDisconnect = '/api/remote/disconnect';
  static const String epModels = '/api/models';
  static const String epPairRequest = '/api/pair/request';
  static const String epPairStatus = '/api/pair/status';

  // REST Endpoints
  static const String epConfig = '/api/config';
  static const String epServers = '/api/servers';
  static const String epServersUpdate = '/api/servers/update';
  static const String epServersDelete = '/api/servers/delete';
  static const String epServersSelect = '/api/servers/select';

  static const String epChatSessions = '/api/chat/sessions';
  static const String epChatHistory = '/api/chat/history';
  static const String epChatClear = '/api/chat/clear';
  static const String epChat = '/api/chat';
  static const String epChatLive = '/api/chat/live';
  static const String epChatStop = '/api/chat/stop';

  static const String epWorkSchedules = '/api/work-schedules';

  static const String epSshTest = '/api/ssh/test';
  static const String epServerHealth = '/api/server/health';
  static const String epSystemInfo = '/api/server/system-info';
  static const String epMetrics = '/api/server/metrics';
  static const String epServiceAction = '/api/server/service-action';
  static const String epServerLogs = '/api/server/logs';
  static const String epServerDeploy = '/api/server/deploy';

  static const String epFsListDirs = '/api/fs/list_dirs';
  static const String epFsListEntries = '/api/fs/list_entries';
  static const String epFsDownload = '/api/fs/download';
  static const String epFsUpload = '/api/fs/upload';

  // WebSocket Endpoints
  static const String wsTerminal = '/ws/terminal';
}
