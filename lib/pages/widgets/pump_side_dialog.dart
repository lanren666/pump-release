import 'package:flutter/material.dart';
import '../../config/app_color.dart';
import '../../config/responsive_text.dart';
import '../../l10n/app_localizations.dart';

class PumpSideDialog extends StatefulWidget {
  final String deviceName;
  final Set<String> occupiedPositions;
  final Future<bool> Function(String) onConnect;

  const PumpSideDialog({
    super.key,
    required this.deviceName,
    required this.occupiedPositions,
    required this.onConnect,
  });

  @override
  State<PumpSideDialog> createState() => _PumpSideDialogState();
}

class _PumpSideDialogState extends State<PumpSideDialog> {
  String? _selectedSide;
  bool _isConnecting = false;
  String? _errorMessage;
  bool _sideInitialized = false;

  @override
  void initState() {
    super.initState();
    if (!widget.occupiedPositions.contains('left')) {
      _selectedSide = 'left';
    } else if (!widget.occupiedPositions.contains('right')) {
      _selectedSide = 'right';
    }
  }

  void _initializeSelectedSide() {
    if (!_sideInitialized &&
        (_selectedSide == 'left' || _selectedSide == 'right')) {
      final l10n = AppLocalizations.of(context)!;
      if (_selectedSide == 'left') {
        _selectedSide = l10n.leftSide;
      } else if (_selectedSide == 'right') {
        _selectedSide = l10n.rightSide;
      }
      _sideInitialized = true;
    }
  }

  Future<void> _handleConnect() async {
    if (_selectedSide == null || _isConnecting) return;

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final l10n = AppLocalizations.of(context)!;
      String side;
      if (_selectedSide == l10n.leftSide) {
        side = 'Left';
      } else if (_selectedSide == l10n.rightSide) {
        side = 'Right';
      } else {
        side = _selectedSide!.replaceAll(' Side', '');
      }
      final success = await widget.onConnect(side);

      if (mounted) {
        if (success) {
          Navigator.of(context).pop();
        } else {
          final l10n = AppLocalizations.of(context)!;
          setState(() {
            _isConnecting = false;
            _errorMessage = l10n.failedToConnect(widget.deviceName);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _isConnecting = false;
          _errorMessage = l10n.errorConnecting(widget.deviceName, e.toString());
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _initializeSelectedSide();
    final isLeftOccupied = widget.occupiedPositions.contains('left');
    final isRightOccupied = widget.occupiedPositions.contains('right');

    return Dialog(
      backgroundColor: AppColor.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  AppLocalizations.of(context)!.selectPumpSide,
                  style: ResponsiveText.style(
                    context,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColor.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (!_isConnecting)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(
                        Icons.close,
                        size: 20,
                        color: AppColor.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: ResponsiveText.bodySmall(
                          context,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            _buildSideOption(
              AppLocalizations.of(context)!.leftSide,
              isLeftOccupied,
            ),
            const SizedBox(height: 12),
            _buildSideOption(
              AppLocalizations.of(context)!.rightSide,
              isRightOccupied,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: (_selectedSide != null && !_isConnecting)
                  ? _handleConnect
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColor.primaryPurple,
                foregroundColor: AppColor.white,
                disabledBackgroundColor: Colors.grey.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isConnecting
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColor.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.connecting,
                          style: ResponsiveText.body(
                            context,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      AppLocalizations.of(context)!.connect,
                      style: ResponsiveText.body(
                        context,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideOption(String side, bool isOccupied) {
    final isSelected = _selectedSide == side;
    return InkWell(
      onTap: (isOccupied || _isConnecting)
          ? null
          : () {
              setState(() {
                _selectedSide = side;
                _errorMessage = null;
              });
            },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isOccupied
              ? Colors.grey.withValues(alpha: 0.1)
              : AppColor.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isOccupied
                      ? Colors.grey.withValues(alpha: 0.3)
                      : (isSelected
                            ? AppColor.textPrimary
                            : Colors.grey.withValues(alpha: 0.4)),
                  width: isSelected && !isOccupied ? 0 : 1.5,
                ),
                color: isSelected && !isOccupied
                    ? AppColor.textPrimary
                    : Colors.transparent,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              side,
              style: ResponsiveText.body(
                context,
                color: isOccupied ? Colors.grey : AppColor.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
