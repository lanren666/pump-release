import 'package:flutter/material.dart';

import '../../config/app_color.dart';
import '../../config/responsive_text.dart';
import '../../l10n/app_localizations.dart';

enum LowBatteryDialogVariant {
  /// Before use: insufficient for a full session.
  connectWarning,

  /// During session: host red LED blink (<20 min left).
  runningWarning,

  /// After session: need to charge for next use.
  sessionComplete,
}

/// Low-battery modal aligned with product UI spec.
class LowBatteryDialog extends StatelessWidget {
  const LowBatteryDialog({super.key, required this.variant});

  final LowBatteryDialogVariant variant;

  static Future<void> show(
    BuildContext context,
    LowBatteryDialogVariant variant,
  ) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => LowBatteryDialog(variant: variant),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final message = switch (variant) {
      LowBatteryDialogVariant.connectWarning => l10n.lowBatteryConnectMessage,
      LowBatteryDialogVariant.runningWarning => l10n.lowBatteryRunningMessage,
      LowBatteryDialogVariant.sessionComplete =>
        l10n.lowBatterySessionCompleteMessage,
    };

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: ResponsiveText.symmetric(context, horizontal: 28),
      child: Padding(
        padding: ResponsiveText.symmetric(context, horizontal: 20, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LowBatteryIcon(size: ResponsiveText.getSize(context, 28)),
                SizedBox(width: ResponsiveText.getSize(context, 10)),
                Expanded(
                  child: Text(
                    l10n.lowBatteryTitle,
                    style: ResponsiveText.smallTitle(
                      context,
                      fontWeight: FontWeight.w700,
                      color: AppColor.textPrimary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(
                    Icons.close,
                    size: ResponsiveText.getSize(context, 22),
                    color: AppColor.textSecondary,
                  ),
                ),
              ],
            ),
            SizedBox(height: ResponsiveText.getSize(context, 14)),
            Text(
              message,
              textAlign: TextAlign.center,
              style: ResponsiveText.body(
                context,
                color: AppColor.textSecondary,
              ),
            ),
            SizedBox(height: ResponsiveText.getSize(context, 24)),
            if (variant == LowBatteryDialogVariant.connectWarning) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColor.primaryPurple,
                    foregroundColor: AppColor.white,
                    elevation: 0,
                    padding: ResponsiveText.symmetric(
                      context,
                      vertical: 14,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Text(
                    l10n.lowBatteryGoCharge,
                    style: ResponsiveText.body(
                      context,
                      fontWeight: FontWeight.w600,
                      color: AppColor.white,
                    ),
                  ),
                ),
              ),
              SizedBox(height: ResponsiveText.getSize(context, 12)),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: ResponsiveText.symmetric(
                      context,
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  child: Text(
                    l10n.lowBatteryContinue,
                    style: ResponsiveText.body(
                      context,
                      color: AppColor.primaryPurple,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColor.primaryPurple,
                    foregroundColor: AppColor.white,
                    elevation: 0,
                    padding: ResponsiveText.symmetric(
                      context,
                      vertical: 14,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Text(
                    l10n.lowBatteryGotIt,
                    style: ResponsiveText.body(
                      context,
                      fontWeight: FontWeight.w600,
                      color: AppColor.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LowBatteryIcon extends StatelessWidget {
  const _LowBatteryIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.battery_2_bar,
            size: size,
            color: Colors.red,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.42,
              height: size * 0.42,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.priority_high,
                size: size * 0.34,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
