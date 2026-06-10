import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../data/models/engagement_excuse_model.dart';
import '../providers/engagement_excuse_provider.dart';

/// Oturum açıkken bekleyen mazaret talebi varsa uygulamayı bloke eder.
class EngagementExcuseGate extends ConsumerStatefulWidget {
  const EngagementExcuseGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<EngagementExcuseGate> createState() =>
      _EngagementExcuseGateState();
}

class _EngagementExcuseGateState extends ConsumerState<EngagementExcuseGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(engagementExcuseActionsProvider).refreshPending();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = ref.watch(isLoggedInProvider);

    ref.listen<bool>(isLoggedInProvider, (previous, next) {
      if (next) {
        ref.invalidate(pendingEngagementExcuseProvider);
      }
    });

    if (!isLoggedIn) return widget.child;

    final pendingAsync = ref.watch(pendingEngagementExcuseProvider);

    return pendingAsync.when(
      data: (pending) {
        if (pending == null) return widget.child;
        return Stack(
          children: [
            widget.child,
            _EngagementExcuseBlockingOverlay(request: pending),
          ],
        );
      },
      loading: () => Stack(
        children: [
          widget.child,
          ModalBarrier(
            dismissible: false,
            color: Colors.black.withValues(alpha: 0.35),
          ),
          const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ],
      ),
      error: (_, __) => widget.child,
    );
  }
}

class _EngagementExcuseBlockingOverlay extends ConsumerStatefulWidget {
  const _EngagementExcuseBlockingOverlay({required this.request});

  final PendingEngagementExcuseModel request;

  @override
  ConsumerState<_EngagementExcuseBlockingOverlay> createState() =>
      _EngagementExcuseBlockingOverlayState();
}

class _EngagementExcuseBlockingOverlayState
    extends ConsumerState<_EngagementExcuseBlockingOverlay> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _charCount => _controller.text.trim().length;

  bool get _canSubmit => _charCount >= 30 && !_isSubmitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref.read(engagementExcuseActionsProvider).submitExcuse(
            requestId: widget.request.id,
            text: _controller.text.trim(),
          );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit_note_rounded,
                            size: 36,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.request.title,
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.tertiaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Mazaret Bildir',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.tertiaryDark,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.request.description,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.neutral700,
                            height: 1.45,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _controller,
                          maxLines: 5,
                          minLines: 4,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Mazaretinizi buraya yazın...',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$_charCount / 30 karakter (minimum)',
                          style: AppTypography.labelSmall.copyWith(
                            color: _charCount >= 30
                                ? AppColors.secondary
                                : AppColors.neutral500,
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.error,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _canSubmit ? _submit : null,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Mazareti Kaydet'),
                        ),
                      ],
                    ),
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
