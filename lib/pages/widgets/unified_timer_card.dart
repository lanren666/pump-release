import 'package:flutter/material.dart';

import '../../config/app_color.dart';
import '../../config/responsive_text.dart';
import '../../l10n/app_localizations.dart';
import '../control_types.dart';

class UnifiedTimerCard extends StatelessWidget {
  const UnifiedTimerCard({
    super.key,
    required this.displayMode,
    required this.displayMinutes,
    required this.displaySeconds,
    required this.currentPhase,
    required this.effectiveTotalPhases,
    required this.currentHasStarted,
    required this.effectivePhaseDuration,
    required this.elapsedTimeInPhase,
    required this.maxDuration,
    this.deviceMaxDuration,
  });

  final IntensityMode displayMode;
  final String displayMinutes;
  final String displaySeconds;
  final int currentPhase;
  final int effectiveTotalPhases;
  final bool currentHasStarted;
  final Duration effectivePhaseDuration;
  final Duration elapsedTimeInPhase;
  final int maxDuration;
  final int? deviceMaxDuration;

  @override
  Widget build(BuildContext context) {
    final effectivePhaseMinutes = effectivePhaseDuration.inMinutes
        .toString()
        .padLeft(2, '0');
    final effectivePhaseSeconds = (effectivePhaseDuration.inSeconds % 60)
        .toString()
        .padLeft(2, '0');
    final phaseElapsedMinutes = currentHasStarted
        ? elapsedTimeInPhase.inMinutes.toString().padLeft(2, '0')
        : '00';
    final phaseElapsedSeconds = currentHasStarted
        ? (elapsedTimeInPhase.inSeconds % 60).toString().padLeft(2, '0')
        : '00';
    final effectiveMaxDuration = currentHasStarted
        ? (deviceMaxDuration ?? maxDuration)
        : maxDuration;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      key: const Key('unified_timer_card'),
      padding: ResponsiveText.padding(
        context,
        left: 8,
        right: 12,
        top: 12,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFDF7E4), Color(0xFFF5E6B3)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                key: const Key('unified_timer_mode_badge'),
                padding: ResponsiveText.symmetric(
                  context,
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColor.primaryPurple,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  displayMode == IntensityMode.stimulation
                      ? l10n.stimulation
                      : l10n.expression,
                  style: ResponsiveText.caption(
                    context,
                    fontWeight: FontWeight.w500,
                    color: AppColor.white,
                  ),
                ),
              ),
            ],
          ),
          Center(
            child: Text(
              '$displayMinutes:$displaySeconds',
              key: const Key('unified_timer_main'),
              style: ResponsiveText.extraLarge(
                context,
                color: AppColor.textPrimary,
              ),
            ),
          ),
          Center(
            child: Text(
              '${l10n.phase} $currentPhase/$effectiveTotalPhases: '
              '$phaseElapsedMinutes:$phaseElapsedSeconds / '
              '$effectivePhaseMinutes:$effectivePhaseSeconds | '
              '${l10n.max.replaceAll(RegExp(r':'), '')} '
              '$effectiveMaxDuration${l10n.minutes}',
              key: const Key('unified_timer_phase_line'),
              style: ResponsiveText.bodySmall(
                context,
                color: AppColor.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
