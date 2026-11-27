import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/services/aitype_admin_service.dart';
import '../../core/services/bank_notification_bridge.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';

class AiTypeAdminScreen extends StatefulWidget {
  final VoidCallback? onOpenDrawer;

  const AiTypeAdminScreen({super.key, this.onOpenDrawer});

  @override
  State<AiTypeAdminScreen> createState() => _AiTypeAdminScreenState();
}

class _AiTypeAdminScreenState extends State<AiTypeAdminScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final AiTypeAdminService _service = AiTypeAdminService();
  final NumberFormat _vndFmt = NumberFormat('#,###', 'vi_VN');
  final DateFormat _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  late final TabController _tabController;

  // Auth / Connection state
  bool _checkingAuth = true;
  bool _isAuthenticated = false;
  String _connectedApiUrl = AiTypeAdminService.defaultApiUrl;
  String _connectedUser = '';

  // Login form state (Email / Mật khẩu)
  bool _loginLoading = false;
  bool _obscurePassword = true;
  final TextEditingController _apiUrlCtrl =
      TextEditingController(text: AiTypeAdminService.defaultApiUrl);
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  // Dashboard summary
  Map<String, dynamic> _summary = {};
  bool _loadingSummary = false;

  // Tab 1: Payment & Bank SMS
  bool _loadingPaymentConfig = false;
  bool _savingPaymentConfig = false;
  bool _showWebhookSecret = false;
  BankListenerStatus _bankListener = BankListenerStatus.unsupported();
  bool _savingBankListener = false;
  bool _sendingLocalTest = false;
  String _webhookUrl = 'https://apiv3.type.vn/v1/payment/bank-sms';
  String _webhookSecret = '';
  String _selectedBankCode = 'VCB';
  List<Map<String, dynamic>> _napasBanks = const [];
  List<Map<String, dynamic>> _recentSmsLogs = const [];
  final TextEditingController _accountNumberCtrl = TextEditingController();
  final TextEditingController _accountHolderCtrl = TextEditingController();
  final TextEditingController _pricePerMonthCtrl = TextEditingController(text: '2000');
  final TextEditingController _allowedSendersCtrl = TextEditingController(text: 'Vietcombank,VCB');

  // Test SMS parser
  bool _testingSms = false;
  Map<String, dynamic>? _testSmsResult;
  final TextEditingController _testSenderCtrl = TextEditingController(text: 'Vietcombank');
  final TextEditingController _testMessageCtrl = TextEditingController(
    text:
        'SD TK 0441000725568 +2,000VND luc 26-11-2026 10:15:00. SD 5,002,000VND. Ref MBVCB.1234567890.AITYP123456',
  );

  // Manual payment confirm
  bool _confirmingManual = false;
  final TextEditingController _manualEmailCtrl = TextEditingController();
  final TextEditingController _manualOrderCodeCtrl = TextEditingController();
  final TextEditingController _manualMonthsCtrl = TextEditingController(text: '1');
  final TextEditingController _manualNoteCtrl = TextEditingController();

  // Tab 2: Transactions
  bool _loadingTransactions = false;
  List<Map<String, dynamic>> _transactions = const [];
  final TextEditingController _txSearchCtrl = TextEditingController();

  // Tab 3: License Keys
  bool _loadingLicenses = false;
  int _totalLicenses = 0;
  List<Map<String, dynamic>> _licenses = const [];
  final TextEditingController _licSearchCtrl = TextEditingController();

  // Tab 4: Forum Users & Groups
  bool _loadingForum = false;
  bool _forumLoadedOnce = false;
  List<Map<String, dynamic>> _forumUsers = const [];
  List<Map<String, dynamic>> _forumGroups = const [];
  final TextEditingController _forumSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadBankListenerStatus();
    _bootstrapAuth();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && BankNotificationBridge.isSupported) {
      _loadBankListenerStatus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _apiUrlCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _accountNumberCtrl.dispose();
    _accountHolderCtrl.dispose();
    _pricePerMonthCtrl.dispose();
    _allowedSendersCtrl.dispose();
    _testSenderCtrl.dispose();
    _testMessageCtrl.dispose();
    _manualEmailCtrl.dispose();
    _manualOrderCodeCtrl.dispose();
    _manualMonthsCtrl.dispose();
    _manualNoteCtrl.dispose();
    _txSearchCtrl.dispose();
    _licSearchCtrl.dispose();
    _forumSearchCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging || !_isAuthenticated) return;
    if (_tabController.index == 1 && _transactions.isEmpty && !_loadingTransactions) {
      _loadTransactions();
    } else if (_tabController.index == 2 && _licenses.isEmpty && !_loadingLicenses) {
      _loadLicenses();
    } else if (_tabController.index == 3 && !_forumLoadedOnce && !_loadingForum) {
      _loadForumUsers();
    }
  }

  Future<void> _bootstrapAuth() async {
    final creds = await _service.getCredentials();
    if (!mounted) return;
    _apiUrlCtrl.text = creds.apiUrl;
    if (creds.token.isEmpty) {
      setState(() {
        _checkingAuth = false;
        _isAuthenticated = false;
      });
      return;
    }

    setState(() {
      _connectedApiUrl = creds.apiUrl;
      _connectedUser = creds.user;
      _isAuthenticated = true;
      _checkingAuth = false;
    });

    await _refreshPrimaryData();
  }

  Future<void> _refreshPrimaryData() async {
    await Future.wait([
      _loadSummary(),
      _loadPaymentConfig(),
      _loadTransactions(),
      _loadLicenses(),
    ]);
  }

  Future<void> _handleAuthFailure(Object error) async {
    if (error is AiTypeAdminException &&
        (error.statusCode == 401 || error.statusCode == 403)) {
      if (mounted) {
        AppToast.error(context, 'Phiên quản trị đã hết hạn hoặc không đủ quyền: ${error.message}');
      }
      await _service.logout();
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
        });
      }
      return;
    }
    if (mounted) {
      AppToast.error(context, error.toString());
    }
  }

  Future<void> _submitLogin() async {
    final apiUrl = _apiUrlCtrl.text.trim();
    if (apiUrl.isEmpty) {
      AppToast.warning(context, 'Vui lòng nhập địa chỉ API AI.Type.');
      return;
    }

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      AppToast.warning(context, 'Vui lòng nhập Email và Mật khẩu quản trị.');
      return;
    }

    setState(() => _loginLoading = true);
    try {
      await _service.loginWithTypeVn(
        apiUrl: apiUrl,
        username: email,
        password: password,
      );
      _passwordCtrl.clear();

      final creds = await _service.getCredentials();
      if (!mounted) return;
      setState(() {
        _connectedApiUrl = creds.apiUrl;
        _connectedUser = creds.user;
        _isAuthenticated = true;
      });
      AppToast.success(context, 'Đã kết nối trung tâm quản trị AI.Type.');
      await _refreshPrimaryData();
    } catch (e) {
      if (mounted) AppToast.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  Future<void> _logout() async {
    await _service.logout();
    if (!mounted) return;
    setState(() {
      _isAuthenticated = false;
      _summary = {};
      _transactions = const [];
      _licenses = const [];
      _forumUsers = const [];
      _forumGroups = const [];
      _forumLoadedOnce = false;
    });
    AppToast.info(context, 'Đã đăng xuất khỏi Quản trị AI.Type.');
  }

  Future<void> _loadSummary() async {
    if (!mounted) return;
    setState(() => _loadingSummary = true);
    try {
      final data = await _service.getSummary();
      if (mounted) setState(() => _summary = data);
    } catch (e) {
      await _handleAuthFailure(e);
    } finally {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  Future<void> _loadPaymentConfig() async {
    if (!mounted) return;
    setState(() => _loadingPaymentConfig = true);
    try {
      final data = await _service.getPaymentConfig();
      if (!mounted) return;
      final banks = ((data['banks'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final logs = ((data['recentSmsLogs'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();

      setState(() {
        _napasBanks = banks;
        _recentSmsLogs = logs;
        _selectedBankCode = (data['bankCode'] ?? 'VCB').toString();
        _accountNumberCtrl.text = (data['accountNumber'] ?? '').toString();
        _accountHolderCtrl.text = (data['accountHolder'] ?? '').toString();
        _pricePerMonthCtrl.text = (data['pricePerMonth'] ?? 2000).toString();
        _allowedSendersCtrl.text = (data['allowedSenders'] ?? 'Vietcombank,VCB').toString();
        _webhookUrl = (data['webhookUrl'] ?? '$_connectedApiUrl/payment/bank-sms').toString();
        _webhookSecret = (data['smsWebhookSecret'] ?? '').toString();
      });
      await _syncBankListenerSecretSilently();
    } catch (e) {
      await _handleAuthFailure(e);
    } finally {
      if (mounted) setState(() => _loadingPaymentConfig = false);
    }
  }

  Future<void> _savePaymentConfig({bool rotateSecret = false}) async {
    final accNum = _accountNumberCtrl.text.trim();
    final accHolder = _accountHolderCtrl.text.trim().toUpperCase();
    final price = int.tryParse(_pricePerMonthCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 2000;
    if (accNum.isEmpty || accHolder.isEmpty) {
      AppToast.warning(context, 'Vui lòng nhập đầy đủ Số tài khoản và Chủ tài khoản.');
      return;
    }

    final bankObj = _napasBanks.cast<Map<String, dynamic>?>().firstWhere(
          (b) => b?['code'] == _selectedBankCode,
          orElse: () => null,
        );

    setState(() => _savingPaymentConfig = true);
    try {
      final updated = await _service.updatePaymentConfig({
        'bankCode': _selectedBankCode,
        if (bankObj != null) 'bankBin': bankObj['bin'],
        if (bankObj != null) 'bankName': bankObj['name'],
        'accountNumber': accNum,
        'accountHolder': accHolder,
        'pricePerMonth': price < 1000 ? 2000 : price,
        'allowedSenders': _allowedSendersCtrl.text.trim(),
        if (rotateSecret) 'rotateSecret': true,
      });

      if (!mounted) return;
      setState(() {
        _webhookSecret = (updated['smsWebhookSecret'] ?? _webhookSecret).toString();
      });
      await _syncBankListenerSecretSilently();
      if (!mounted) return;
      AppToast.success(
        context,
        rotateSecret
            ? 'Đã tạo khóa X-Bank-Webhook-Secret mới và đồng bộ vào dịch vụ đọc thông báo.'
            : 'Đã lưu cấu hình thanh toán ngân hàng trực tiếp.',
      );
    } catch (e) {
      await _handleAuthFailure(e);
    } finally {
      if (mounted) setState(() => _savingPaymentConfig = false);
    }
  }

  Future<void> _loadBankListenerStatus() async {
    final st = await BankNotificationBridge.getStatus();
    if (mounted) {
      setState(() => _bankListener = st);
    }
  }

  Future<void> _syncBankListenerSecretSilently() async {
    if (!BankNotificationBridge.isSupported || _webhookSecret.trim().isEmpty) return;
    try {
      final current = await BankNotificationBridge.getStatus();
      final updated = await BankNotificationBridge.saveConfig(
        enabled: current.enabled,
        webhookUrl: _webhookUrl,
        webhookSecret: _webhookSecret,
        allowedSenders: _allowedSendersCtrl.text.trim().isEmpty
            ? 'Vietcombank,VCB,VCB Digibank'
            : _allowedSendersCtrl.text.trim(),
        listenSmsApps: current.listenSmsApps,
      );
      if (mounted) {
        setState(() => _bankListener = updated);
      }
    } catch (_) {}
  }

  Future<void> _toggleBankListener(bool nextEnabled) async {
    if (!BankNotificationBridge.isSupported) return;
    if (nextEnabled) {
      final latest = await BankNotificationBridge.getStatus();
      if (!latest.permissionGranted) {
        if (mounted) {
          setState(() => _bankListener = latest);
          AppToast.warning(
            context,
            'Vui lòng cấp quyền Đọc thông báo cho AI Type Agent trước khi bật.',
          );
        }
        await BankNotificationBridge.openNotificationSettings();
        return;
      }
      if (_webhookSecret.trim().isEmpty && !latest.hasSecret) {
        if (mounted) {
          AppToast.warning(context, 'Chưa tải được khóa bí mật Webhook từ máy chủ.');
        }
        return;
      }
    }

    setState(() => _savingBankListener = true);
    try {
      final updated = await BankNotificationBridge.saveConfig(
        enabled: nextEnabled,
        webhookUrl: _webhookUrl,
        webhookSecret: _webhookSecret,
        allowedSenders: _allowedSendersCtrl.text.trim().isEmpty
            ? 'Vietcombank,VCB,VCB Digibank'
            : _allowedSendersCtrl.text.trim(),
        listenSmsApps: _bankListener.listenSmsApps,
      );
      if (mounted) {
        setState(() => _bankListener = updated);
        AppToast.success(
          context,
          nextEnabled
              ? 'Đã bật tự động đọc thông báo Vietcombank chạy ngầm.'
              : 'Đã tạm tắt tự động đọc thông báo Vietcombank.',
        );
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Lỗi lưu cấu hình đọc thông báo: $e');
    } finally {
      if (mounted) setState(() => _savingBankListener = false);
    }
  }

  Future<void> _toggleListenSmsApps(bool nextValue) async {
    if (!BankNotificationBridge.isSupported) return;
    setState(() => _savingBankListener = true);
    try {
      final updated = await BankNotificationBridge.saveConfig(
        enabled: _bankListener.enabled,
        webhookUrl: _webhookUrl,
        webhookSecret: _webhookSecret,
        allowedSenders: _allowedSendersCtrl.text.trim().isEmpty
            ? 'Vietcombank,VCB,VCB Digibank'
            : _allowedSendersCtrl.text.trim(),
        listenSmsApps: nextValue,
      );
      if (mounted) setState(() => _bankListener = updated);
    } catch (e) {
      if (mounted) AppToast.error(context, 'Lỗi cập nhật tuỳ chọn SMS: $e');
    } finally {
      if (mounted) setState(() => _savingBankListener = false);
    }
  }

  Future<void> _sendNativeTestNotification() async {
    if (!BankNotificationBridge.isSupported) return;
    await _syncBankListenerSecretSilently();
    setState(() => _sendingLocalTest = true);
    try {
      final acc = _accountNumberCtrl.text.trim().isEmpty ? '0441000725568' : _accountNumberCtrl.text.trim();
      final price = int.tryParse(_pricePerMonthCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 2000;
      final res = await BankNotificationBridge.sendTestForward(
        sender: 'VCB Digibank',
        message: 'SD TK $acc +${_vndFmt.format(price)} VND luc test. Ref MBVCB.TEST.NOORDER',
      );
      await _loadBankListenerStatus();
      await _loadPaymentConfig();
      if (!mounted) return;
      if (res['ok'] == true) {
        AppToast.success(
          context,
          'Đã bắn thử từ Android tới server thành công (HTTP ${res['httpCode']}).',
        );
      } else {
        AppToast.error(
          context,
          'Gửi thử thất bại (HTTP ${res['httpCode']}): ${res['response']}',
        );
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Lỗi gửi thử từ Android: $e');
    } finally {
      if (mounted) setState(() => _sendingLocalTest = false);
    }
  }

  Future<void> _runTestSms() async {
    final msg = _testMessageCtrl.text.trim();
    if (msg.isEmpty) {
      AppToast.warning(context, 'Nhập nội dung tin nhắn SMS mẫu để kiểm thử.');
      return;
    }
    setState(() {
      _testingSms = true;
      _testSmsResult = null;
    });
    try {
      final res = await _service.testBankSms(
        sender: _testSenderCtrl.text.trim(),
        message: msg,
      );
      if (mounted) setState(() => _testSmsResult = res);
    } catch (e) {
      await _handleAuthFailure(e);
    } finally {
      if (mounted) setState(() => _testingSms = false);
    }
  }

  Future<void> _submitManualConfirm() async {
    final email = _manualEmailCtrl.text.trim();
    final months = int.tryParse(_manualMonthsCtrl.text.trim()) ?? 1;
    if (email.isEmpty || !email.contains('@')) {
      AppToast.warning(context, 'Vui lòng nhập email tài khoản hợp lệ.');
      return;
    }
    if (months < 1 || months > 60) {
      AppToast.warning(context, 'Số tháng hợp lệ từ 1 đến 60.');
      return;
    }

    setState(() => _confirmingManual = true);
    try {
      final res = await _service.manualConfirmPayment(
        email: email,
        orderCode: _manualOrderCodeCtrl.text.trim(),
        months: months,
        note: _manualNoteCtrl.text.trim(),
      );
      if (!mounted) return;
      final licKey = ((res['data'] as Map<String, dynamic>?)?['licenseKey'] ?? '').toString();
      AppToast.success(
        context,
        licKey.isNotEmpty
            ? 'Đã duyệt $months tháng cho $email (Key: $licKey)'
            : (res['message'] ?? 'Đã xác nhận thanh toán thành công.').toString(),
      );
      _manualEmailCtrl.clear();
      _manualOrderCodeCtrl.clear();
      _manualNoteCtrl.clear();
      _manualMonthsCtrl.text = '1';
      await Future.wait([_loadSummary(), _loadTransactions(), _loadLicenses()]);
    } catch (e) {
      await _handleAuthFailure(e);
    } finally {
      if (mounted) setState(() => _confirmingManual = false);
    }
  }

  Future<void> _loadTransactions() async {
    if (!mounted) return;
    setState(() => _loadingTransactions = true);
    try {
      final rows = await _service.getTransactions(email: _txSearchCtrl.text.trim());
      if (mounted) setState(() => _transactions = rows);
    } catch (e) {
      await _handleAuthFailure(e);
    } finally {
      if (mounted) setState(() => _loadingTransactions = false);
    }
  }

  Future<void> _loadLicenses() async {
    if (!mounted) return;
    setState(() => _loadingLicenses = true);
    try {
      final res = await _service.getLicenses(query: _licSearchCtrl.text.trim());
      if (mounted) {
        setState(() {
          _totalLicenses = res.total;
          _licenses = res.items;
        });
      }
    } catch (e) {
      await _handleAuthFailure(e);
    } finally {
      if (mounted) setState(() => _loadingLicenses = false);
    }
  }

  Future<void> _loadForumUsers() async {
    if (!mounted) return;
    setState(() => _loadingForum = true);
    try {
      final res = await _service.getForumUsers(query: _forumSearchCtrl.text.trim());
      if (mounted) {
        setState(() {
          _forumUsers = res.users;
          _forumGroups = res.groups;
          _forumLoadedOnce = true;
        });
      }
    } catch (e) {
      await _handleAuthFailure(e);
    } finally {
      if (mounted) setState(() => _loadingForum = false);
    }
  }

  Future<void> _copyText(String value, String label) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) AppToast.success(context, 'Đã sao chép $label.');
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '--';
    try {
      if (raw is num) {
        return _dateFmt.format(DateTime.fromMillisecondsSinceEpoch(raw.toInt()).toLocal());
      }
      final dt = DateTime.tryParse(raw.toString());
      if (dt == null) return raw.toString();
      return _dateFmt.format(dt.toLocal());
    } catch (_) {
      return raw.toString();
    }
  }

  String _formatMoney(dynamic raw) {
    final n = (raw is num) ? raw.toInt() : (int.tryParse(raw?.toString() ?? '0') ?? 0);
    return '${_vndFmt.format(n)} đ';
  }

  // ===========================================================================
  // DIALOGS: CREATE LICENSE, EXTEND LICENSE, FORUM GROUPS
  // ===========================================================================
  Future<void> _showCreateLicenseDialog() async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final monthsCtrl = TextEditingController(text: '1');
    bool assignGroups = true;
    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardBg,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.radius,
                side: const BorderSide(color: AppColors.borderDark),
              ),
              title: const Text(
                'Tạo License Key mới',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textWhite),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    _labeledField(
                      label: 'Email khách hàng *',
                      child: TextField(
                        controller: emailCtrl,
                        maxLines: 1,
                        textAlignVertical: TextAlignVertical.center,
                        style: _adminInputTextStyle,
                        decoration: _adminInputDecoration(hintText: 'khachhang@example.com'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _labeledField(
                      label: 'Tên khách hàng (tùy chọn)',
                      child: TextField(
                        controller: nameCtrl,
                        maxLines: 1,
                        textAlignVertical: TextAlignVertical.center,
                        style: _adminInputTextStyle,
                        decoration: _adminInputDecoration(hintText: 'Nguyễn Văn A'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _labeledField(
                            label: 'Số điện thoại',
                            child: TextField(
                              controller: phoneCtrl,
                              maxLines: 1,
                              textAlignVertical: TextAlignVertical.center,
                              style: _adminInputTextStyle,
                              decoration: _adminInputDecoration(hintText: '09xxxxxxxx'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 120,
                          child: _labeledField(
                            label: 'Số tháng *',
                            child: TextField(
                              controller: monthsCtrl,
                              maxLines: 1,
                              textAlignVertical: TextAlignVertical.center,
                              keyboardType: TextInputType.number,
                              style: _adminInputTextStyle,
                              decoration: _adminInputDecoration(hintText: '1'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      value: assignGroups,
                      onChanged: (v) => setDialogState(() => assignGroups = v ?? true),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'Tự động cấp nhóm quyền trả phí trên type.vn',
                        style: TextStyle(fontSize: 12.5, color: AppColors.textDim),
                      ),
                    ),
                  ],
                ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton.icon(
                  onPressed: submitting
                      ? null
                      : () async {
                          final email = emailCtrl.text.trim();
                          final months = int.tryParse(monthsCtrl.text.trim()) ?? 1;
                          if (email.isEmpty || !email.contains('@')) {
                            AppToast.warning(context, 'Vui lòng nhập email hợp lệ.');
                            return;
                          }
                          setDialogState(() => submitting = true);
                          try {
                            final res = await _service.createLicense(
                              email: email,
                              customerName: nameCtrl.text.trim(),
                              phoneNumber: phoneCtrl.text.trim(),
                              months: months.clamp(1, 60),
                              assignGroups: assignGroups,
                            );
                            final newKey = ((res['data'] as Map<String, dynamic>?)?['licenseKey'] ?? '').toString();
                            if (newKey.isNotEmpty) {
                              await Clipboard.setData(ClipboardData(text: newKey));
                            }
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            if (mounted) {
                              AppToast.success(
                                context,
                                newKey.isNotEmpty
                                    ? 'Đã tạo và sao chép key: $newKey'
                                    : 'Đã tạo License Key thành công.',
                              );
                            }
                            await Future.wait([_loadLicenses(), _loadSummary()]);
                          } catch (e) {
                            if (mounted) AppToast.error(context, e.toString());
                          } finally {
                            if (ctx.mounted) setDialogState(() => submitting = false);
                          }
                        },
                  icon: submitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.vpn_key_rounded, size: 16),
                  label: const Text('Tạo Key'),
                ),
              ],
            );
          },
        );
      },
    );

    emailCtrl.dispose();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    monthsCtrl.dispose();
  }

  Future<void> _showExtendLicenseDialog(Map<String, dynamic> license) async {
    final monthsCtrl = TextEditingController(text: '1');
    final daysCtrl = TextEditingController();
    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardBg,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.radius,
                side: const BorderSide(color: AppColors.borderDark),
              ),
              title: const Text(
                'Gia hạn License Key',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textWhite),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(
                      (license['email'] ?? '--').toString(),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryLight),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      (license['licenseKey'] ?? '').toString(),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: AppColors.textDim),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [1, 3, 6, 12].map((m) {
                        return ActionChip(
                          backgroundColor: AppColors.bgDark,
                          side: const BorderSide(color: AppColors.borderDark),
                          label: Text('+$m tháng', style: const TextStyle(fontSize: 12, color: AppColors.textWhite)),
                          onPressed: () {
                            monthsCtrl.text = '$m';
                            daysCtrl.clear();
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _labeledField(
                            label: 'Cộng thêm (tháng)',
                            child: TextField(
                              controller: monthsCtrl,
                              maxLines: 1,
                              textAlignVertical: TextAlignVertical.center,
                              keyboardType: TextInputType.number,
                              style: _adminInputTextStyle,
                              decoration: _adminInputDecoration(hintText: '1'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _labeledField(
                            label: 'Hoặc số ngày lẻ',
                            child: TextField(
                              controller: daysCtrl,
                              maxLines: 1,
                              textAlignVertical: TextAlignVertical.center,
                              keyboardType: TextInputType.number,
                              style: _adminInputTextStyle,
                              decoration: _adminInputDecoration(hintText: '0'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton.icon(
                  onPressed: submitting
                      ? null
                      : () async {
                          final months = int.tryParse(monthsCtrl.text.trim()) ?? 0;
                          final days = int.tryParse(daysCtrl.text.trim()) ?? 0;
                          if (months <= 0 && days <= 0) {
                            AppToast.warning(context, 'Vui lòng nhập số tháng hoặc số ngày cần cộng thêm.');
                            return;
                          }
                          setDialogState(() => submitting = true);
                          try {
                            final res = await _service.extendLicense(
                              licenseKey: (license['licenseKey'] ?? '').toString(),
                              months: days > 0 ? 0 : months,
                              days: days,
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            if (mounted) {
                              AppToast.success(
                                context,
                                (res['message'] ?? 'Đã gia hạn thành công.').toString(),
                              );
                            }
                            await _loadLicenses();
                          } catch (e) {
                            if (mounted) AppToast.error(context, e.toString());
                          } finally {
                            if (ctx.mounted) setDialogState(() => submitting = false);
                          }
                        },
                  icon: submitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.update_rounded, size: 16),
                  label: const Text('Gia hạn'),
                ),
              ],
            );
          },
        );
      },
    );

    monthsCtrl.dispose();
    daysCtrl.dispose();
  }

  Future<void> _showForumGroupsDialog(Map<String, dynamic> user) async {
    final uid = (user['uid'] as num?)?.toInt() ?? 0;
    if (uid <= 0) return;
    final currentGroups = Set<String>.from(
      ((user['groups'] as List<dynamic>?) ?? []).map((e) => e.toString()),
    );
    String? busySlug;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.cardBg,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.radius,
                side: const BorderSide(color: AppColors.borderDark),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Phân nhóm: ${user['username'] ?? '#$uid'}',
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    (user['email'] ?? '').toString(),
                    style: const TextStyle(fontSize: 12, color: AppColors.textDim),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
                child: _forumGroups.isEmpty
                    ? const Text(
                        'Chưa tải được danh sách nhóm từ type.vn.',
                        style: TextStyle(color: AppColors.textDim),
                      )
                    : SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _forumGroups.map((g) {
                            final slug = (g['slug'] ?? '').toString();
                            final name = (g['name'] ?? slug).toString();
                            final selected = currentGroups.contains(slug);
                            final isBusy = busySlug == slug;
                            return FilterChip(
                              selected: selected,
                              backgroundColor: AppColors.bgDark,
                              selectedColor: AppColors.primary.withValues(alpha: 0.28),
                              checkmarkColor: AppColors.primaryLight,
                              side: BorderSide(
                                color: selected ? AppColors.primaryLight : AppColors.borderDark,
                              ),
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isBusy) ...[
                                    const SizedBox(
                                      width: 11,
                                      height: 11,
                                      child: CircularProgressIndicator(strokeWidth: 1.8),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: selected ? AppColors.textWhite : AppColors.textDim,
                                    ),
                                  ),
                                ],
                              ),
                              onSelected: busySlug != null
                                  ? null
                                  : (nextSelected) async {
                                      setDialogState(() => busySlug = slug);
                                      try {
                                        await _service.updateForumMembership(
                                          uid: uid,
                                          slug: slug,
                                          add: nextSelected,
                                        );
                                        setDialogState(() {
                                          if (nextSelected) {
                                            currentGroups.add(slug);
                                          } else {
                                            currentGroups.remove(slug);
                                          }
                                        });
                                        if (mounted) {
                                          setState(() {
                                            user['groups'] = currentGroups.toList();
                                          });
                                          AppToast.success(
                                            context,
                                            nextSelected
                                                ? 'Đã thêm vào nhóm $name.'
                                                : 'Đã gỡ khỏi nhóm $name.',
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) AppToast.error(context, e.toString());
                                      } finally {
                                        if (ctx.mounted) setDialogState(() => busySlug = null);
                                      }
                                    },
                            );
                          }).toList(),
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Đóng'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================
  bool _isMobile(BuildContext context) => MediaQuery.of(context).size.width < 720;

  @override
  Widget build(BuildContext context) {
    if (_checkingAuth) {
      return const Scaffold(
        backgroundColor: AppColors.bgDark,
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
      );
    }

    if (!_isAuthenticated) {
      return _buildLoginView();
    }

    final isMobile = _isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          _buildTopHeader(isMobile),
          _buildSummaryStrip(isMobile),
          Container(
            width: double.infinity,
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              color: AppColors.sidebarBg,
              border: Border(
                top: BorderSide(color: AppColors.borderDark),
                bottom: BorderSide(color: AppColors.borderDark),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: !isMobile,
              tabAlignment: isMobile ? TabAlignment.fill : TabAlignment.start,
              dividerColor: Colors.transparent,
              indicatorColor: AppColors.primaryLight,
              indicatorWeight: 2.5,
              labelColor: AppColors.primaryLight,
              unselectedLabelColor: AppColors.textDim,
              labelPadding: isMobile
                  ? const EdgeInsets.symmetric(horizontal: 4)
                  : const EdgeInsets.symmetric(horizontal: 16),
              labelStyle: TextStyle(
                fontSize: isMobile ? 12 : 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: TextStyle(
                fontSize: isMobile ? 12 : 13,
                fontWeight: FontWeight.w500,
              ),
              tabs: isMobile
                  ? const [
                      Tab(height: 40, text: 'Thanh toán'),
                      Tab(height: 40, text: 'Giao dịch'),
                      Tab(height: 40, text: 'License'),
                      Tab(height: 40, text: 'Thành viên'),
                    ]
                  : const [
                      Tab(icon: Icon(Icons.account_balance_rounded, size: 17), text: 'Thanh toán & SMS'),
                      Tab(icon: Icon(Icons.receipt_long_rounded, size: 17), text: 'Lịch sử giao dịch'),
                      Tab(icon: Icon(Icons.vpn_key_rounded, size: 17), text: 'License Keys'),
                      Tab(icon: Icon(Icons.group_rounded, size: 17), text: 'Thành viên type.vn'),
                    ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPaymentSmsTab(isMobile),
                _buildTransactionsTab(isMobile),
                _buildLicensesTab(isMobile),
                _buildForumUsersTab(isMobile),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginView() {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Column(
        children: [
          if (widget.onOpenDrawer != null)
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                color: AppColors.bgDark,
                border: Border(bottom: BorderSide(color: AppColors.borderDark, width: 1)),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Mở menu điều hướng',
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(34, 34),
                      fixedSize: const Size(34, 34),
                      maximumSize: const Size(34, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.standard,
                    ),
                    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                    onPressed: widget.onOpenDrawer,
                    icon: const Icon(Icons.menu_rounded, size: 20, color: AppColors.textWhite),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.admin_panel_settings_rounded, color: AppColors.primaryLight, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Quản trị AI.Type',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textWhite),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: AppRadius.radius,
                border: Border.all(color: AppColors.borderDark),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.16),
                          borderRadius: AppRadius.radius,
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                        ),
                        child: const Icon(Icons.admin_panel_settings_rounded,
                            color: AppColors.primaryLight, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Quản trị hệ thống AI.Type',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textWhite,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Đăng nhập bằng Email và Mật khẩu quản trị',
                              style: TextStyle(fontSize: 12, color: AppColors.textDim),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _labeledField(
                    label: 'API Server URL',
                    child: TextField(
                      key: const ValueKey('admin_api_url_input'),
                      controller: _apiUrlCtrl,
                      maxLines: 1,
                      textAlignVertical: TextAlignVertical.center,
                      style: _adminInputTextStyle,
                      decoration: _adminInputDecoration(
                        hintText: 'https://apiv3.type.vn/v1',
                        prefixIcon: const Icon(Icons.dns_outlined, size: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _labeledField(
                    label: 'Email / Tài khoản quản trị (type.vn)',
                    child: TextField(
                      key: const ValueKey('admin_email_input'),
                      controller: _emailCtrl,
                      maxLines: 1,
                      textAlignVertical: TextAlignVertical.center,
                      keyboardType: TextInputType.emailAddress,
                      style: _adminInputTextStyle,
                      decoration: _adminInputDecoration(
                        hintText: 'admin@type.vn',
                        prefixIcon: const Icon(Icons.email_outlined, size: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _labeledField(
                    label: 'Mật khẩu',
                    child: TextField(
                      key: const ValueKey('admin_password_input'),
                      controller: _passwordCtrl,
                      maxLines: 1,
                      textAlignVertical: TextAlignVertical.center,
                      obscureText: _obscurePassword,
                      onSubmitted: (_) => _submitLogin(),
                      style: _adminInputTextStyle,
                      decoration: _adminInputDecoration(
                        hintText: 'Nhập mật khẩu quản trị...',
                        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 16),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                          style: IconButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(30, 30),
                            fixedSize: const Size(30, 30),
                            maximumSize: const Size(30, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      key: const ValueKey('admin_login_submit_button'),
                      onPressed: _loginLoading ? null : _submitLogin,
                      icon: _loginLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.login_rounded, size: 18),
                      label: const Text('Đăng nhập Quản trị'),
                    ),
                  ),
                  ],
                ),
              ),
            ),
          ),
        ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 14,
        vertical: isMobile ? 8 : 12,
      ),
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        border: Border(bottom: BorderSide(color: AppColors.borderDark)),
      ),
      child: Row(
        children: [
          if (widget.onOpenDrawer != null) ...[
            IconButton(
              tooltip: 'Mở menu điều hướng',
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(34, 34),
                fixedSize: const Size(34, 34),
                maximumSize: const Size(34, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
              ),
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
              onPressed: widget.onOpenDrawer,
              icon: const Icon(Icons.menu_rounded, size: 20, color: AppColors.textWhite),
            ),
            const SizedBox(width: 6),
          ],
          Icon(
            Icons.admin_panel_settings_rounded,
            color: AppColors.primaryLight,
            size: isMobile ? 20 : 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quản trị AI.Type',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isMobile ? 14.5 : 15.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textWhite,
                  ),
                ),
                Text(
                  isMobile
                      ? _connectedUser
                      : '$_connectedApiUrl  •  $_connectedUser',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                ),
              ],
            ),
          ),
          if (isMobile) ...[
            IconButton(
              tooltip: 'Làm mới dữ liệu',
              onPressed: _loadingSummary ? null : _refreshPrimaryData,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.cardBg,
                side: const BorderSide(color: AppColors.borderDark),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.radius),
                minimumSize: const Size(34, 34),
                fixedSize: const Size(34, 34),
                padding: EdgeInsets.zero,
              ),
              icon: _loadingSummary
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                    )
                  : const Icon(Icons.refresh_rounded, size: 17, color: AppColors.textWhite),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Đăng xuất',
              onPressed: _logout,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.danger.withValues(alpha: 0.1),
                side: BorderSide(color: AppColors.danger.withValues(alpha: 0.35)),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.radius),
                minimumSize: const Size(34, 34),
                fixedSize: const Size(34, 34),
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.logout_rounded, size: 17, color: AppColors.danger),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: _loadingSummary ? null : _refreshPrimaryData,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Làm mới', style: TextStyle(fontSize: 12.5)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textWhite,
                side: const BorderSide(color: AppColors.borderDark),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded, size: 16, color: AppColors.danger),
              label: const Text('Đăng xuất', style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryStrip(bool isMobile) {
    final pills = [
      _metricPill(
        isMobile ? 'Tháng này' : 'Doanh thu tháng này',
        _formatMoney(_summary['monthRevenue'] ?? 0),
        '${_summary['monthTransactions'] ?? 0} GD',
        AppColors.accent,
        compact: isMobile,
      ),
      _metricPill(
        'Tổng doanh thu',
        _formatMoney(_summary['totalRevenue'] ?? 0),
        '${_summary['totalTransactions'] ?? 0} GD',
        AppColors.primaryLight,
        compact: isMobile,
      ),
      _metricPill(
        'License',
        '${_summary['activeLicenses'] ?? 0} / ${_summary['totalLicenses'] ?? 0}',
        'Còn hạn',
        AppColors.accentCyan,
        compact: isMobile,
      ),
      _metricPill(
        'SMS khớp',
        '${_summary['matchedSms'] ?? 0} / ${_summary['totalSms'] ?? 0}',
        'Vietcombank',
        AppColors.warning,
        compact: isMobile,
      ),
    ];

    if (isMobile) {
      return Container(
        width: double.infinity,
        color: AppColors.bgDark,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (int i = 0; i < pills.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                pills[i],
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      color: AppColors.bgDark,
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: pills,
      ),
    );
  }

  Widget _metricPill(
    String label,
    String value,
    String sub,
    Color accentColor, {
    bool compact = false,
  }) {
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: AppRadius.radius,
          border: Border.all(color: AppColors.borderDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textDim)),
                const SizedBox(width: 6),
                Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: accentColor),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 185),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: AppRadius.radius,
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: accentColor),
          ),
          Text(sub, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: PAYMENT & DIRECT BANK SMS
  // ===========================================================================
  Widget _buildPaymentSmsTab(bool isMobile) {
    if (_loadingPaymentConfig && _napasBanks.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryLight));
    }

    return RefreshIndicator(
      color: AppColors.primaryLight,
      backgroundColor: AppColors.cardBg,
      onRefresh: () async {
        await Future.wait([
          _loadSummary(),
          _loadPaymentConfig(),
          _loadBankListenerStatus(),
        ]);
      },
      child: ListView(
      padding: EdgeInsets.all(isMobile ? 12 : 18),
      children: [
        if (BankNotificationBridge.isSupported) ...[
          _buildAndroidBankListenerCard(isMobile),
          const SizedBox(height: 12),
        ],
        // Card 1: Bank Account Config
        _sectionCard(
          title: 'Tài khoản ngân hàng nhận tiền (Trực tiếp, không qua bên thứ 3)',
          subtitle: 'AI.Type tự sinh mã VietQR nội bộ (EMVCo/NAPAS 247) từ cấu hình này.',
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 700;
                  final bankField = _labeledField(
                    label: 'Ngân hàng (NAPAS BIN)',
                    child: DropdownButtonFormField<String>(
                      initialValue: _napasBanks.any((b) => b['code'] == _selectedBankCode)
                          ? _selectedBankCode
                          : null,
                      isExpanded: true,
                      isDense: true,
                      dropdownColor: AppColors.cardBg,
                      style: _adminInputTextStyle,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textDim),
                      decoration: _adminInputDecoration(
                        hintText: 'Chọn ngân hàng',
                        isDropdown: true,
                      ),
                      items: _napasBanks.map((b) {
                        final code = (b['code'] ?? '').toString();
                        final name = (b['name'] ?? code).toString();
                        final bin = (b['bin'] ?? '').toString();
                        return DropdownMenuItem(
                          value: code,
                          child: Text(
                            '$name ($code · $bin)',
                            overflow: TextOverflow.ellipsis,
                            style: _adminInputTextStyle,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedBankCode = v);
                      },
                    ),
                  );
                  final accNumField = _labeledField(
                    label: 'Số tài khoản',
                    child: TextField(
                      controller: _accountNumberCtrl,
                      maxLines: 1,
                      textAlignVertical: TextAlignVertical.center,
                      style: _adminInputTextStyle,
                      decoration: _adminInputDecoration(hintText: 'Nhập số tài khoản ngân hàng'),
                    ),
                  );
                  final accHolderField = _labeledField(
                    label: 'Chủ tài khoản (IN HOA KHÔNG DẤU)',
                    child: TextField(
                      controller: _accountHolderCtrl,
                      maxLines: 1,
                      textAlignVertical: TextAlignVertical.center,
                      textCapitalization: TextCapitalization.characters,
                      style: _adminInputTextStyle,
                      decoration: _adminInputDecoration(hintText: 'NGUYEN VAN A'),
                    ),
                  );
                  final priceField = _labeledField(
                    label: 'Đơn giá / tháng (VNĐ)',
                    child: TextField(
                      controller: _pricePerMonthCtrl,
                      maxLines: 1,
                      textAlignVertical: TextAlignVertical.center,
                      keyboardType: TextInputType.number,
                      style: _adminInputTextStyle,
                      decoration: _adminInputDecoration(hintText: '145000'),
                    ),
                  );
                  final sendersField = _labeledField(
                    label: 'Đầu số / Brandname SMS cho phép (ngăn cách dấu phẩy)',
                    child: TextField(
                      controller: _allowedSendersCtrl,
                      maxLines: 1,
                      textAlignVertical: TextAlignVertical.center,
                      style: _adminInputTextStyle,
                      decoration: _adminInputDecoration(hintText: 'Vietcombank,VCB'),
                    ),
                  );

                  if (wide) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: bankField),
                            const SizedBox(width: 12),
                            Expanded(child: accNumField),
                            const SizedBox(width: 12),
                            Expanded(child: accHolderField),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            SizedBox(width: 220, child: priceField),
                            const SizedBox(width: 12),
                            Expanded(child: sendersField),
                          ],
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      bankField,
                      const SizedBox(height: 10),
                      accNumField,
                      const SizedBox(height: 10),
                      accHolderField,
                      const SizedBox(height: 10),
                      priceField,
                      const SizedBox(height: 10),
                      sendersField,
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Align(
                alignment: isMobile ? Alignment.center : Alignment.centerRight,
                child: SizedBox(
                  width: isMobile ? double.infinity : null,
                  height: isMobile ? 42 : null,
                  child: ElevatedButton.icon(
                    onPressed: _savingPaymentConfig ? null : () => _savePaymentConfig(),
                    icon: _savingPaymentConfig
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded, size: 16),
                    label: const Text('Lưu cấu hình ngân hàng'),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Card 2: Direct Android SMS Forwarder Webhook
        if (!BankNotificationBridge.isSupported) ...[
          _buildAndroidBankListenerCard(isMobile),
          const SizedBox(height: 14),
        ],
        _sectionCard(
          title: 'Webhook nhận SMS / thông báo trực tiếp từ điện thoại Android',
          subtitle:
              'Agent Coder bản Android đã tích hợp sẵn dịch vụ đọc thông báo VCB Digibank. Mục dưới dùng để sao chép khóa thủ công nếu cần.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _copyableField(
                label: 'POST Webhook URL',
                value: _webhookUrl,
                onCopy: () => _copyText(_webhookUrl, 'Webhook URL'),
              ),
              const SizedBox(height: 10),
              if (isMobile) ...[
                _copyableField(
                  label: 'Header X-Bank-Webhook-Secret',
                  value: _showWebhookSecret
                      ? _webhookSecret
                      : (_webhookSecret.isEmpty ? '--' : '•' * 24),
                  onCopy: () => _copyText(_webhookSecret, 'X-Bank-Webhook-Secret'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _showWebhookSecret = !_showWebhookSecret),
                        icon: Icon(
                          _showWebhookSecret ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 15,
                        ),
                        label: Text(_showWebhookSecret ? 'Ẩn khóa' : 'Hiện khóa', style: const TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textWhite,
                          side: const BorderSide(color: AppColors.borderDark),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _savingPaymentConfig
                            ? null
                            : () => _savePaymentConfig(rotateSecret: true),
                        icon: const Icon(Icons.autorenew_rounded, size: 15),
                        label: const Text('Đổi khóa', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.warning,
                          side: BorderSide(color: AppColors.warning.withValues(alpha: 0.4)),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: _copyableField(
                        label: 'Header X-Bank-Webhook-Secret',
                        value: _showWebhookSecret
                            ? _webhookSecret
                            : (_webhookSecret.isEmpty ? '--' : '•' * 28),
                        onCopy: () => _copyText(_webhookSecret, 'X-Bank-Webhook-Secret'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: _showWebhookSecret ? 'Ẩn khóa bí mật' : 'Hiện khóa bí mật',
                      icon: Icon(
                        _showWebhookSecret ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 18,
                        color: AppColors.textDim,
                      ),
                      onPressed: () => setState(() => _showWebhookSecret = !_showWebhookSecret),
                    ),
                    OutlinedButton.icon(
                      onPressed: _savingPaymentConfig
                          ? null
                          : () => _savePaymentConfig(rotateSecret: true),
                      icon: const Icon(Icons.autorenew_rounded, size: 15),
                      label: const Text('Đổi khóa', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: BorderSide(color: AppColors.warning.withValues(alpha: 0.4)),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bgDark,
                  borderRadius: AppRadius.radius,
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: const SelectableText(
                  'Mẫu cấu hình JSON Body (Content-Type: application/json):\n'
                  '{"sender": "{from}", "message": "{text}"}\n'
                  'Header bắt buộc: X-Bank-Webhook-Secret: <khóa bí mật ở trên>',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: AppColors.textDim, height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Card 3: Test SMS Parser + Card 4: Manual Confirm side-by-side on wide screens
        LayoutBuilder(
          builder: (context, constraints) {
            final testCard = _sectionCard(
              title: 'Kiểm thử đọc tin nhắn SMS Vietcombank',
              subtitle: 'Kiểm tra bộ lọc cộng tiền (+), đúng số tài khoản và mã đơn AITYPxxxxxx (không ghi DB).',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _labeledField(
                    label: 'Người gửi (Sender)',
                    child: TextField(
                      controller: _testSenderCtrl,
                      maxLines: 1,
                      textAlignVertical: TextAlignVertical.center,
                      style: _adminInputTextStyle,
                      decoration: _adminInputDecoration(hintText: 'Vietcombank'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _labeledField(
                    label: 'Nội dung tin nhắn SMS',
                    fixedHeight: false,
                    child: TextField(
                      controller: _testMessageCtrl,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        height: 1.45,
                        color: AppColors.textWhite,
                      ),
                      decoration: _adminInputDecoration(
                        hintText: 'Dán nội dung tin nhắn SMS biến động số dư...',
                        multiline: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: isMobile ? Alignment.center : Alignment.centerRight,
                    child: SizedBox(
                      width: isMobile ? double.infinity : null,
                      height: isMobile ? 40 : null,
                      child: ElevatedButton.icon(
                        onPressed: _testingSms ? null : _runTestSms,
                        icon: _testingSms
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.science_outlined, size: 16),
                        label: const Text('Kiểm thử phân tích SMS'),
                      ),
                    ),
                  ),
                  if (_testSmsResult != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (_testSmsResult!['ok'] == true ? AppColors.accent : AppColors.danger)
                            .withValues(alpha: 0.12),
                        borderRadius: AppRadius.radius,
                        border: Border.all(
                          color: (_testSmsResult!['ok'] == true ? AppColors.accent : AppColors.danger)
                              .withValues(alpha: 0.45),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _testSmsResult!['ok'] == true
                                ? 'HỢP LỆ — Sẽ tự động kích hoạt ${_testSmsResult!['months'] ?? 0} tháng'
                                : 'BỊ TỪ CHỐI — Lý do: ${_testSmsResult!['reason'] ?? 'unknown'}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: _testSmsResult!['ok'] == true ? AppColors.accent : AppColors.danger,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Số tiền: ${_formatMoney(_testSmsResult!['amount'] ?? 0)}  •  '
                            'Mã đơn: ${_testSmsResult!['orderCode'] ?? '--'}  •  '
                            'Mã GD: ${_testSmsResult!['transactionId'] ?? '--'}',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textWhite),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );

            final manualCard = _sectionCard(
              title: 'Duyệt thanh toán thủ công (Dự phòng)',
              subtitle: 'Dùng khi khách chuyển khoản quên ghi mã đơn AITYPxxxxxx hoặc SMS trễ.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _labeledField(
                    label: 'Email tài khoản khách hàng *',
                    child: TextField(
                      controller: _manualEmailCtrl,
                      maxLines: 1,
                      textAlignVertical: TextAlignVertical.center,
                      keyboardType: TextInputType.emailAddress,
                      style: _adminInputTextStyle,
                      decoration: _adminInputDecoration(hintText: 'khachhang@example.com'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _labeledField(
                          label: 'Mã đơn AITYP... (tùy chọn)',
                          child: TextField(
                            controller: _manualOrderCodeCtrl,
                            maxLines: 1,
                            textAlignVertical: TextAlignVertical.center,
                            style: _adminInputTextStyle,
                            decoration: _adminInputDecoration(hintText: 'AITYP123456'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 110,
                        child: _labeledField(
                          label: 'Số tháng *',
                          child: TextField(
                            controller: _manualMonthsCtrl,
                            maxLines: 1,
                            textAlignVertical: TextAlignVertical.center,
                            keyboardType: TextInputType.number,
                            style: _adminInputTextStyle,
                            decoration: _adminInputDecoration(hintText: '1'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _labeledField(
                    label: 'Ghi chú đối soát (tùy chọn)',
                    child: TextField(
                      controller: _manualNoteCtrl,
                      maxLines: 1,
                      textAlignVertical: TextAlignVertical.center,
                      style: _adminInputTextStyle,
                      decoration: _adminInputDecoration(hintText: 'Nhập ghi chú đối soát...'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: isMobile ? Alignment.center : Alignment.centerRight,
                    child: SizedBox(
                      width: isMobile ? double.infinity : null,
                      height: isMobile ? 40 : null,
                      child: ElevatedButton.icon(
                        onPressed: _confirmingManual ? null : _submitManualConfirm,
                        icon: _confirmingManual
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_circle_outline_rounded, size: 16),
                        label: const Text('Xác nhận & cấp bản quyền'),
                      ),
                    ),
                  ),
                ],
              ),
            );

            if (constraints.maxWidth >= 900) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: testCard),
                  const SizedBox(width: 14),
                  Expanded(child: manualCard),
                ],
              );
            }
            return Column(
              children: [
                testCard,
                const SizedBox(height: 14),
                manualCard,
              ],
            );
          },
        ),
        const SizedBox(height: 14),

        // Card 5: Recent Bank SMS Logs
        _sectionCard(
          title: 'Nhật ký SMS ngân hàng gần nhất (${_recentSmsLogs.length})',
          subtitle: 'Hiển thị 20 tin nhắn gần nhất gửi vào endpoint /v1/payment/bank-sms.',
          child: _recentSmsLogs.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text('Chưa có nhật ký SMS ngân hàng nào.', style: TextStyle(color: AppColors.textMuted)),
                  ),
                )
              : Column(
                  children: _recentSmsLogs.map((log) {
                    final status = (log['status'] ?? 'ignored').toString();
                    final statusColor = status == 'matched'
                        ? AppColors.accent
                        : (status == 'duplicate' ? AppColors.warning : AppColors.textMuted);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.bgDark,
                        borderRadius: AppRadius.radius,
                        border: Border.all(color: AppColors.borderDark),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _badge(status.toUpperCase(), statusColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  (log['sender'] ?? 'Unknown').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatDate(log['createdAt']),
                                style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                          if ((log['parsedAmount'] as num? ?? 0) > 0 ||
                              (log['parsedOrderCode'] ?? '').toString().isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if ((log['parsedAmount'] as num? ?? 0) > 0)
                                  Text(
                                    '+${_formatMoney(log['parsedAmount'])}',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.accent),
                                  ),
                                if ((log['parsedOrderCode'] ?? '').toString().isNotEmpty)
                                  _badge(log['parsedOrderCode'].toString(), AppColors.primaryLight),
                              ],
                            ),
                          ],
                          const SizedBox(height: 5),
                          Text(
                            (log['rawText'] ?? '').toString(),
                            style: const TextStyle(fontSize: 12, color: AppColors.textDim),
                          ),
                          if ((log['reason'] ?? '').toString().isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              'Chi tiết: ${log['reason']}',
                              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
      ),
    );
  }

  // ===========================================================================
  // ANDROID NATIVE VIETCOMBANK NOTIFICATION LISTENER CARD
  // ===========================================================================
  Widget _buildAndroidBankListenerCard(bool isMobile) {
    if (!BankNotificationBridge.isSupported) {
      return _sectionCard(
        title: 'Đọc thông báo Vietcombank tích hợp sẵn (Agent Coder Android)',
        subtitle:
            'Tính năng chạy trực tiếp trên điện thoại Android nhận thông báo VCB Digibank — không cần cài MacroDroid hay app bên thứ 3.',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bgDark,
            borderRadius: AppRadius.radius,
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
          ),
          child: const Text(
            'Cài file APK của Agent Coder lên điện thoại Android đang đăng nhập VCB Digibank, vào tab Quản trị AI.Type -> Thanh toán & SMS, cấp quyền Đọc thông báo và bật công tắc. Khóa Webhook sẽ tự đồng bộ hoàn toàn.',
            style: TextStyle(fontSize: 12, color: AppColors.textDim, height: 1.45),
          ),
        ),
      );
    }

    final permOk = _bankListener.permissionGranted;
    final active = _bankListener.enabled && permOk;

    return _sectionCard(
      title: 'Tự động đọc thông báo Vietcombank (Tích hợp sẵn)',
      subtitle:
          'Bắt trực tiếp thông báo từ VCB Digibank và SMS Vietcombank ngay trên điện thoại này, tự gửi về server kể cả khi đóng app.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _badge(
                permOk ? 'ĐÃ CẤP QUYỀN ĐỌC THÔNG BÁO' : 'CHƯA CẤP QUYỀN ĐỌC THÔNG BÁO',
                permOk ? AppColors.accent : AppColors.warning,
              ),
              _badge(
                active ? 'ĐANG LẮNG NGHE NGẦM' : 'ĐANG TẮT',
                active ? AppColors.primaryLight : AppColors.textMuted,
              ),
              if (_bankListener.hasSecret)
                _badge('ĐÃ ĐỒNG BỘ KHÓA WEBHOOK', AppColors.accentCyan),
            ],
          ),
          const SizedBox(height: 12),
          if (isMobile) ...[
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                onPressed: () => BankNotificationBridge.openNotificationSettings(),
                icon: const Icon(Icons.notifications_active_outlined, size: 17),
                label: Text(permOk ? 'Cài đặt quyền thông báo' : 'Cấp quyền Đọc thông báo'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => BankNotificationBridge.openAppDetailsSettings(),
                    icon: const Icon(Icons.security_rounded, size: 14),
                    label: const Text('Thông tin app', style: TextStyle(fontSize: 11.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textWhite,
                      side: const BorderSide(color: AppColors.borderDark),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadBankListenerStatus,
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('Kiểm tra quyền', style: TextStyle(fontSize: 11.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryLight,
                      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ] else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => BankNotificationBridge.openNotificationSettings(),
                  icon: const Icon(Icons.notifications_active_outlined, size: 16),
                  label: Text(permOk ? 'Cài đặt quyền thông báo' : 'Cấp quyền Đọc thông báo'),
                ),
                OutlinedButton.icon(
                  onPressed: () => BankNotificationBridge.openAppDetailsSettings(),
                  icon: const Icon(Icons.security_rounded, size: 15),
                  label: const Text('Mở Thông tin app (Android 13+)', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textWhite,
                    side: const BorderSide(color: AppColors.borderDark),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _loadBankListenerStatus,
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: const Text('Kiểm tra quyền', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryLight,
                    side: BorderSide(color: AppColors.primary.withValues(alpha: 0.45)),
                  ),
                ),
              ],
            ),
          if (!permOk) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: AppRadius.radius,
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
              ),
              child: const Text(
                'Lưu ý trên Android 13 trở lên khi cài file APK: nếu nút bật quyền bị mờ và báo "Cài đặt bị hạn chế", hãy bấm "Mở Thông tin app (Android 13+)" -> chạm dấu 3 chấm góc phải trên -> chọn "Cho phép cài đặt bị hạn chế", sau đó quay lại bật quyền Đọc thông báo cho AI Type Agent.',
                style: TextStyle(fontSize: 11.5, color: AppColors.warning, height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgDark,
              borderRadius: AppRadius.radius,
              border: Border.all(color: AppColors.borderDark),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  dense: isMobile,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 16,
                    vertical: isMobile ? 2 : 4,
                  ),
                  value: _bankListener.enabled,
                  onChanged: _savingBankListener ? null : _toggleBankListener,
                  activeThumbColor: AppColors.primaryLight,
                  title: const Text(
                    'Bật tự động chuyển tiếp thông báo VCB Digibank',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                  ),
                  subtitle: Text(
                    'Đích: $_webhookUrl',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ),
                const Divider(height: 1, color: AppColors.borderDark),
                SwitchListTile(
                  dense: isMobile,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 16,
                    vertical: isMobile ? 2 : 4,
                  ),
                  value: _bankListener.listenSmsApps,
                  onChanged: _savingBankListener ? null : _toggleListenSmsApps,
                  activeThumbColor: AppColors.primaryLight,
                  title: const Text(
                    'Đọc thêm tin nhắn SMS từ Vietcombank',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textWhite),
                  ),
                  subtitle: const Text(
                    'Chỉ lọc tin nhắn khớp Vietcombank / VCB.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Nhật ký chuyển tiếp trên máy này',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDim),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: _sendingLocalTest ? null : _sendNativeTestNotification,
                    icon: _sendingLocalTest
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 13),
                    label: const Text('Bắn thử', style: TextStyle(fontSize: 11.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryLight,
                      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                  if (_bankListener.logs.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () async {
                        await BankNotificationBridge.clearLogs();
                        await _loadBankListenerStatus();
                      },
                      child: const Text('Xóa log', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_bankListener.logs.isEmpty)
            const Text(
              'Chưa có thông báo Vietcombank nào được chuyển tiếp từ máy này.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            )
          else
            Column(
              children: _bankListener.logs.take(10).map((item) {
                final ok = item['ok'] == true;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.bgDark,
                    borderRadius: AppRadius.radius,
                    border: Border.all(color: AppColors.borderDark),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _badge(
                            ok ? 'HTTP ${item['httpCode']}' : 'LỖI ${item['httpCode']}',
                            ok ? AppColors.accent : AppColors.danger,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${item['sender'] ?? ''} (${item['pkg'] ?? ''})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textWhite),
                            ),
                          ),
                          Text(
                            (item['time'] ?? '').toString(),
                            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (item['message'] ?? '').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
                      ),
                      if ((item['response'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Server: ${item['response']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: AppColors.textMuted),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 2: TRANSACTIONS
  // ===========================================================================
  Widget _buildTransactionsTab(bool isMobile) {
    final hPad = isMobile ? 12.0 : 18.0;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _txSearchCtrl,
                  onSubmitted: (_) => _loadTransactions(),
                  maxLines: 1,
                  textAlignVertical: TextAlignVertical.center,
                  style: _adminInputTextStyle,
                  decoration: _adminInputDecoration(
                    hintText: 'Lọc theo email khách hàng...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 17),
                    suffixIcon: isMobile
                        ? IconButton(
                            tooltip: 'Tìm',
                            onPressed: _loadingTransactions ? null : _loadTransactions,
                            icon: const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.primaryLight),
                          )
                        : null,
                    height: 38,
                  ),
                ),
              ),
              if (!isMobile) ...[
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _loadingTransactions ? null : _loadTransactions,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    fixedSize: const Size.fromHeight(38),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.standard,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  ),
                  icon: const Icon(Icons.search_rounded, size: 16),
                  label: const Text('Tìm'),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primaryLight,
            backgroundColor: AppColors.cardBg,
            onRefresh: _loadTransactions,
            child: _loadingTransactions
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
                : _transactions.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: Text('Chưa có lịch sử giao dịch nào.', style: TextStyle(color: AppColors.textMuted)),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 18),
                        itemCount: _transactions.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final tx = _transactions[index];
                          final source = (tx['source'] ?? 'bank_sms').toString();
                          final sourceColor =
                              source == 'manual_admin' ? AppColors.warning : AppColors.accent;
                          final sourceLabel =
                              source == 'manual_admin' ? 'Duyệt thủ công' : 'SMS Ngân hàng';

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.cardBg,
                              borderRadius: AppRadius.radius,
                              border: Border.all(color: AppColors.borderDark),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isMobile) ...[
                                  Row(
                                    children: [
                                      _badge(sourceLabel, sourceColor),
                                      const SizedBox(width: 6),
                                      _badge('${tx['months'] ?? 0} tháng', AppColors.primaryLight),
                                      const Spacer(),
                                      Text(
                                        '+${_formatMoney(tx['amount'])}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.accent,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    (tx['username'] ?? 'Chưa gắn email').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textWhite,
                                    ),
                                  ),
                                ] else
                                  Row(
                                    children: [
                                      _badge(sourceLabel, sourceColor),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          (tx['username'] ?? 'Chưa gắn email').toString(),
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textWhite,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '+${_formatMoney(tx['amount'])}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.accent,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _badge('${tx['months'] ?? 0} tháng', AppColors.primaryLight),
                                    ],
                                  ),
                                const SizedBox(height: 5),
                                Text(
                                  (tx['content'] ?? '').toString(),
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Mã GD: ${tx['transactionId'] ?? '--'}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 10.5,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatDate(tx['createdAt']),
                                      style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 3: LICENSE KEYS
  // ===========================================================================
  Widget _buildLicensesTab(bool isMobile) {
    final hPad = isMobile ? 12.0 : 18.0;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _licSearchCtrl,
                  onSubmitted: (_) => _loadLicenses(),
                  maxLines: 1,
                  textAlignVertical: TextAlignVertical.center,
                  style: _adminInputTextStyle,
                  decoration: _adminInputDecoration(
                    hintText: isMobile
                        ? 'Tìm email, key ($_totalLicenses)...'
                        : 'Tìm theo email, tên khách, License Key hoặc mã đơn ($_totalLicenses)...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 17),
                    suffixIcon: isMobile
                        ? IconButton(
                            tooltip: 'Lọc',
                            onPressed: _loadingLicenses ? null : _loadLicenses,
                            icon: const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.primaryLight),
                          )
                        : null,
                    height: 38,
                  ),
                ),
              ),
              if (!isMobile) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _loadingLicenses ? null : _loadLicenses,
                  icon: const Icon(Icons.search_rounded, size: 16),
                  label: const Text('Lọc'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textWhite,
                    side: const BorderSide(color: AppColors.borderDark),
                    minimumSize: const Size(0, 38),
                    fixedSize: const Size.fromHeight(38),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.standard,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _showCreateLicenseDialog,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  fixedSize: const Size.fromHeight(38),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.standard,
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: 0),
                ),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: Text(isMobile ? 'Tạo Key' : 'Tạo Key mới', style: TextStyle(fontSize: isMobile ? 12 : 13)),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primaryLight,
            backgroundColor: AppColors.cardBg,
            onRefresh: _loadLicenses,
            child: _loadingLicenses
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
                : _licenses.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: Text('Không tìm thấy License Key nào.', style: TextStyle(color: AppColors.textMuted)),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 18),
                        itemCount: _licenses.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final lic = _licenses[index];
                          final isExpired = lic['isExpired'] == true;
                          final daysLeft = (lic['daysLeft'] as num?)?.toInt() ?? 0;
                          final keyStr = (lic['licenseKey'] ?? '').toString();

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.cardBg,
                              borderRadius: AppRadius.radius,
                              border: Border.all(color: AppColors.borderDark),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isMobile) ...[
                                  Row(
                                    children: [
                                      _badge(
                                        isExpired ? 'HẾT HẠN' : 'CÒN $daysLeft NGÀY',
                                        isExpired ? AppColors.danger : AppColors.accent,
                                      ),
                                      const Spacer(),
                                      Text(
                                        'HSD: ${_formatDate(lic['expirationDate'])}',
                                        style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    (lic['email'] ?? lic['customerName'] ?? '--').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textWhite,
                                    ),
                                  ),
                                ] else
                                  Row(
                                    children: [
                                      _badge(
                                        isExpired ? 'HẾT HẠN' : 'CÒN $daysLeft NGÀY',
                                        isExpired ? AppColors.danger : AppColors.accent,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          (lic['email'] ?? lic['customerName'] ?? '--').toString(),
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textWhite,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        'Hết hạn: ${_formatDate(lic['expirationDate'])}',
                                        style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
                                      ),
                                      const SizedBox(width: 10),
                                      OutlinedButton.icon(
                                        onPressed: () => _showExtendLicenseDialog(lic),
                                        icon: const Icon(Icons.update_rounded, size: 14),
                                        label: const Text('Gia hạn', style: TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.primaryLight,
                                          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.45)),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        ),
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.only(left: 10, right: 4, top: 5, bottom: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.bgDark,
                                    borderRadius: AppRadius.radius,
                                    border: Border.all(color: AppColors.borderDark),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: SelectableText(
                                          keyStr,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: isMobile ? 11 : 12,
                                            color: AppColors.primaryLight,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      IconButton(
                                        tooltip: 'Sao chép License Key',
                                        style: IconButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(28, 28),
                                          fixedSize: const Size(28, 28),
                                          maximumSize: const Size(28, 28),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.standard,
                                        ),
                                        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                                        icon: const Icon(Icons.copy_rounded, size: 15, color: AppColors.textDim),
                                        onPressed: () => _copyText(keyStr, 'License Key'),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Thiết bị: ${lic['devicesCount'] ?? 0}  •  '
                                        'Tạo: ${_formatDate(lic['createDate'])}'
                                        '${(lic['orderCode'] ?? '').toString().isNotEmpty ? '  •  ${lic['orderCode']}' : ''}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                                      ),
                                    ),
                                    if (isMobile) ...[
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: () => _showExtendLicenseDialog(lic),
                                        icon: const Icon(Icons.update_rounded, size: 14),
                                        label: const Text('Gia hạn', style: TextStyle(fontSize: 11.5)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.primaryLight,
                                          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.45)),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          minimumSize: const Size(0, 32),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 4: FORUM USERS & GROUPS (type.vn)
  // ===========================================================================
  Widget _buildForumUsersTab(bool isMobile) {
    final hPad = isMobile ? 12.0 : 18.0;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 10, hPad, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _forumSearchCtrl,
                  onSubmitted: (_) => _loadForumUsers(),
                  maxLines: 1,
                  textAlignVertical: TextAlignVertical.center,
                  style: _adminInputTextStyle,
                  decoration: _adminInputDecoration(
                    hintText: isMobile
                        ? 'Tìm username, email, UID...'
                        : 'Tìm thành viên theo username, email hoặc UID...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 17),
                    height: 38,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _loadingForum ? null : _loadForumUsers,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  fixedSize: const Size.fromHeight(38),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.standard,
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: 0),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(isMobile ? 'Tải' : 'Tải thành viên', style: TextStyle(fontSize: isMobile ? 12 : 13)),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primaryLight,
            backgroundColor: AppColors.cardBg,
            onRefresh: _loadForumUsers,
            child: _loadingForum
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
                : _forumUsers.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 100),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Nhấn "Tải ngay" để đồng bộ danh sách thành viên từ diễn đàn type.vn.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.textMuted),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: _loadForumUsers,
                                  icon: const Icon(Icons.cloud_download_outlined, size: 16),
                                  label: const Text('Tải ngay'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 18),
                        itemCount: _forumUsers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final u = _forumUsers[index];
                          final groups = ((u['groups'] as List<dynamic>?) ?? [])
                              .map((e) => e.toString())
                              .toList();
                          final isAdmin = u['administrator'] == true;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.cardBg,
                              borderRadius: AppRadius.radius,
                              border: Border.all(color: AppColors.borderDark),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _badge('#${u['uid']}', AppColors.textDim),
                                    const SizedBox(width: 6),
                                    if (isAdmin) ...[
                                      _badge('ADMIN', AppColors.warning),
                                      const SizedBox(width: 6),
                                    ],
                                    Expanded(
                                      child: Text(
                                        isMobile
                                            ? (u['username'] ?? '').toString()
                                            : '${u['username'] ?? ''}  (${u['email'] ?? 'chưa có email'})',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textWhite,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: () => _showForumGroupsDialog(u),
                                      icon: const Icon(Icons.groups_rounded, size: 14),
                                      label: const Text('Phân nhóm', style: TextStyle(fontSize: 11.5)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.primaryLight,
                                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.45)),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        minimumSize: const Size(0, 32),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ],
                                ),
                                if (isMobile) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    (u['email'] ?? 'Chưa có email').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, color: AppColors.textDim),
                                  ),
                                ],
                                if (groups.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: groups.map((g) {
                                      return _badge(g, AppColors.primaryLight);
                                    }).toList(),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  'Tham gia: ${_formatDate(u['joindate'])}  •  '
                                  'Gần nhất: ${_formatDate(u['lastonline'])}',
                                  style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // UI HELPERS
  // ===========================================================================
  static const TextStyle _adminInputTextStyle = TextStyle(
    fontSize: 12.5,
    color: AppColors.textWhite,
  );

  InputDecoration _adminInputDecoration({
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool multiline = false,
    bool isDropdown = false,
    double height = 34,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
      filled: true,
      fillColor: AppColors.inputBg,
      isDense: true,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      contentPadding: multiline
          ? const EdgeInsets.all(10)
          : isDropdown
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
              : (prefixIcon != null || suffixIcon != null)
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 0)
                  : const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      constraints: multiline ? null : BoxConstraints(minHeight: height, maxHeight: height),
      prefixIconConstraints: prefixIcon != null
          ? BoxConstraints(minWidth: height, minHeight: height)
          : null,
      suffixIconConstraints: suffixIcon != null
          ? BoxConstraints(minWidth: height, minHeight: height)
          : null,
      border: OutlineInputBorder(
        borderRadius: AppRadius.radius,
        borderSide: const BorderSide(color: AppColors.borderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.radius,
        borderSide: const BorderSide(color: AppColors.borderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.radius,
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  Widget _labeledField({
    required String label,
    required Widget child,
    bool fixedHeight = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
        ),
        const SizedBox(height: 6),
        if (fixedHeight) SizedBox(height: 34, child: child) else child,
      ],
    );
  }

  Widget _sectionCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: AppRadius.radius,
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppColors.textWhite),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _copyableField({
    required String label,
    required String value,
    required VoidCallback onCopy,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgDark,
        borderRadius: AppRadius.radius,
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.textWhite),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sao chép $label',
            icon: const Icon(Icons.copy_rounded, size: 17, color: AppColors.primaryLight),
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
