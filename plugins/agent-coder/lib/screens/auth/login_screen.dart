import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/app_toast.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = true;

  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _glowAnimation = CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    final auth = context.read<AuthProvider>();

    final success = await auth.login(
      email: _emailController.text,
      password: _passwordController.text,
      rememberMe: _rememberMe,
    );

    if (mounted) {
      if (success) {
        AppToast.success(context, 'Đăng nhập thành công! Chào mừng bạn trở lại.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.4),
            radius: 1.2,
            colors: [
              Color(0xFF161F33),
              AppColors.bgDark,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderDark, width: 1.2),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo & App Branding Header with Pulsing Radiant Glow
                      Center(
                        child: Column(
                          children: [
                            AnimatedBuilder(
                              animation: _glowAnimation,
                              builder: (context, child) {
                                final v = _glowAnimation.value;
                                return Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      // Inner vibrant glow
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.35 + 0.35 * v),
                                        blurRadius: 10 + 14 * v,
                                        spreadRadius: 1 + 3 * v,
                                      ),
                                      // Outer radiating wave
                                      BoxShadow(
                                        color: AppColors.primaryLight.withValues(alpha: 0.15 + 0.25 * v),
                                        blurRadius: 20 + 22 * v,
                                        spreadRadius: 3 + 6 * v,
                                      ),
                                    ],
                                  ),
                                  child: child,
                                );
                              },
                              child: const AppLogo(size: 64, borderRadius: 14),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'AI Type Agent',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textWhite,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Đăng nhập tài khoản quản trị để tiếp tục',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Error Alert Banner
                      if (auth.errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.danger.withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: AppColors.danger,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  auth.errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.primaryLight,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // Email Input Field
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Email tài khoản',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textBody,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(fontSize: 13.5, color: AppColors.textWhite),
                            decoration: const InputDecoration(
                              hintText: 'admin@tadu.vn',
                              prefixIcon: Icon(
                                Icons.mail_outline_rounded,
                                size: 18,
                                color: AppColors.textDim,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Vui lòng nhập email';
                              }
                              final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                              if (!emailRegex.hasMatch(value.trim())) {
                                return 'Định dạng email không hợp lệ';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Password Input Field
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mật khẩu',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textBody,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            style: const TextStyle(fontSize: 13.5, color: AppColors.textWhite),
                            onFieldSubmitted: (_) => _handleLogin(),
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                size: 18,
                                color: AppColors.textDim,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 18,
                                  color: AppColors.textDim,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Vui lòng nhập mật khẩu';
                              }
                              if (value.length < 6) {
                                return 'Mật khẩu phải từ 6 ký tự trở lên';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Remember Me Checkbox Row
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _rememberMe,
                              activeColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              side: const BorderSide(color: AppColors.borderLight),
                              onChanged: (val) {
                                setState(() {
                                  _rememberMe = val ?? true;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _rememberMe = !_rememberMe;
                              });
                            },
                            child: const Text(
                              'Ghi nhớ đăng nhập trên thiết bị',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Submit Login Button
                      SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: auth.isLoading ? null : _handleLogin,
                          child: auth.isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.login_rounded, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'Đăng nhập Control Center',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Standalone / Local Database & Config Button
                      SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.laptop_chromebook_rounded, size: 18),
                          label: const Text(
                            'Dùng Native (Đọc Local DB & Config)',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryLight,
                            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5), width: 1.2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: () async {
                            await auth.loginStandaloneMode();
                            if (context.mounted) {
                              AppToast.success(context, 'Đã mở cơ sở dữ liệu và cấu hình cục bộ');
                            }
                          },
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Security Info / Footer
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 13,
                              color: AppColors.accent.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Kết nối bảo mật HTTPS (api3.tadu.cloud)',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
