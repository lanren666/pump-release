import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../config/app_color.dart';
import '../config/responsive_text.dart';
import '../services/database_service.dart';
import '../l10n/app_localizations.dart';
import 'custom_flow_config.dart';

class CustomFlowPage extends StatefulWidget {
  const CustomFlowPage({super.key});

  @override
  State<CustomFlowPage> createState() => _CustomFlowPageState();
}

class _CustomFlowPageState extends State<CustomFlowPage> {
  static const int _maxPhases = 4;
  static const int _minPhases = 2;
  static const int _minPhaseDuration = 1;
  static const int _maxTotalMinutes = 30;

  final DatabaseService _dbService = DatabaseService();
  CustomFlowTab _selectedTab = CustomFlowTab.boostMilk;
  List<Phase> _phases = [];
  bool _isLoading = true;

  bool get _isReadOnly => _selectedTab == CustomFlowTab.boostMilk;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  int get _totalMinutes =>
      _phases.fold(0, (sum, phase) => sum + phase.duration);

  int _otherPhasesTotal(int index) =>
      _totalMinutes - _phases[index].duration;

  int _maxDurationForPhase(int index) {
    final remaining = _maxTotalMinutes - _otherPhasesTotal(index);
    return remaining.clamp(_minPhaseDuration, _maxTotalMinutes);
  }

  void _ensureTotalWithinLimit() {
    while (_totalMinutes > _maxTotalMinutes) {
      var reduced = false;
      for (int i = _phases.length - 1; i >= 0; i--) {
        if (_phases[i].duration > _minPhaseDuration) {
          _phases[i].duration--;
          reduced = true;
          break;
        }
      }
      if (!reduced) break;
    }
    for (int i = 0; i < _phases.length; i++) {
      final maxForPhase = _maxDurationForPhase(i);
      if (_phases[i].duration > maxForPhase) {
        _phases[i].duration = maxForPhase;
      }
    }
  }

  void _setPhaseDuration(int index, int minutes) {
    final maxForPhase = _maxDurationForPhase(index);
    _phases[index].duration = minutes.clamp(_minPhaseDuration, maxForPhase);
    _ensureTotalWithinLimit();
  }

  Future<void> _loadData() async {
    final selectedTab = await CustomFlowConfig.loadSelectedTab(_dbService);
    var phases = await CustomFlowConfig.loadPhasesForTab(_dbService, selectedTab);
    if (selectedTab != CustomFlowTab.boostMilk) {
      final totalBefore = phases.fold(0, (sum, p) => sum + p.duration);
      _phases = phases;
      _ensureTotalWithinLimit();
      if (totalBefore != _totalMinutes) {
        await _saveCurrentTabPhases();
      }
    } else {
      _phases = phases;
    }
    setState(() {
      _selectedTab = selectedTab;
      _isLoading = false;
    });
  }
  Future<void> _saveCurrentTabPhases() async {
    if (_isReadOnly) return;
    if (!mounted) return;
    await CustomFlowConfig.savePhasesForTab(
      _dbService,
      _selectedTab,
      _phases,
      desc: AppLocalizations.of(context)!.customFlowSettingDesc,
    );
  }

  Future<void> _persistSelectedTab() async {
    await CustomFlowConfig.saveSelectedTab(_dbService, _selectedTab);
  }

  Future<void> _onTabSelected(CustomFlowTab tab) async {
    if (tab == _selectedTab) return;
    await _saveCurrentTabPhases();
    final phases = await CustomFlowConfig.loadPhasesForTab(_dbService, tab);
    await CustomFlowConfig.saveSelectedTab(_dbService, tab);
    if (!mounted) return;
    setState(() {
      _selectedTab = tab;
      _phases = phases;
    });
  }

  Future<void> _onBack() async {
    await _saveCurrentTabPhases();
    await _persistSelectedTab();
    if (mounted) Navigator.of(context).pop(true);
  }

  String _tabLabel(CustomFlowTab tab, AppLocalizations l10n) {
    switch (tab) {
      case CustomFlowTab.boostMilk:
        return l10n.boostMilkFlowTab;
      case CustomFlowTab.custom1:
        return l10n.customFlow1;
      case CustomFlowTab.custom2:
        return l10n.customFlow2;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColor.gradientStart, AppColor.gradientEnd],
            ),
          ),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColor.primaryPurple,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColor.gradientStart, AppColor.gradientEnd],
                  ),
                ),
                child: SingleChildScrollView(
                  padding: ResponsiveText.symmetric(
                    context,
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: ResponsiveText.getSize(context, 4)),
                      _buildInstructionBox(),
                      SizedBox(height: ResponsiveText.getSize(context, 12)),
                      _buildTabBar(),
                      SizedBox(height: ResponsiveText.getSize(context, 12)),
                      ...List.generate(_phases.length, (index) {
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: ResponsiveText.getSize(context, 8),
                          ),
                          child: _buildPhaseCard(index),
                        );
                      }),
                      if (!_isReadOnly) ...[
                        SizedBox(height: ResponsiveText.getSize(context, 8)),
                        _buildAddPhaseButton(),
                      ],
                      SizedBox(height: ResponsiveText.getSize(context, 12)),
                      _buildFlowSummary(),
                      if (!_isReadOnly) ...[
                        SizedBox(height: ResponsiveText.getSize(context, 8)),
                        _buildSaveButton(),
                      ],
                      SizedBox(height: ResponsiveText.getSize(context, 20)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        left: ResponsiveText.getSize(context, 8),
        right: ResponsiveText.getSize(context, 20),
        top: statusBarHeight + ResponsiveText.getSize(context, 8),
        bottom: ResponsiveText.getSize(context, 16),
      ),
      decoration: const BoxDecoration(color: AppColor.primaryPurple),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColor.white),
            onPressed: _onBack,
          ),
          Text(
            AppLocalizations.of(context)!.customFlow,
            style: ResponsiveText.title(
              context,
              fontWeight: FontWeight.bold,
              color: AppColor.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final l10n = AppLocalizations.of(context)!;
    final tabs = CustomFlowTab.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.commonCustomFlows,
          style: ResponsiveText.bodySmall(
            context,
            color: AppColor.textSecondary,
          ),
        ),
        SizedBox(height: ResponsiveText.getSize(context, 8)),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (int i = 0; i < tabs.length; i++) ...[
                if (i > 0) SizedBox(width: ResponsiveText.getSize(context, 8)),
                _buildTabChip(tabs[i], l10n),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabChip(CustomFlowTab tab, AppLocalizations l10n) {
    final isSelected = _selectedTab == tab;
    return InkWell(
      onTap: () => _onTabSelected(tab),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: ResponsiveText.symmetric(context, horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColor.primaryPurple : AppColor.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : Colors.grey.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          _tabLabel(tab, l10n),
          style: ResponsiveText.bodySmall(
            context,
            fontWeight: FontWeight.w500,
            color: isSelected ? AppColor.white : AppColor.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionBox() {
    return Container(
      width: double.infinity,
      padding: ResponsiveText.padding(context, all: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF7E4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Text(
        AppLocalizations.of(context)!.customFlowInstruction,
        style: ResponsiveText.body(context, color: const Color(0xFF6B6B6B)),
      ),
    );
  }

  Widget _buildMenuItem(String text, bool isSelected) {
    return Container(
      color: isSelected
          ? Colors.grey.withValues(alpha: 0.1)
          : Colors.transparent,
      padding: ResponsiveText.symmetric(context, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text),
          if (isSelected)
            Icon(
              Icons.check,
              size: ResponsiveText.getSize(context, 18),
              color: AppColor.primaryPurple,
            ),
        ],
      ),
    );
  }

  Widget _buildPhaseCard(int index) {
    final phase = _phases[index];
    return Container(
      padding: ResponsiveText.symmetric(context, horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: AppColor.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Transform.translate(
                offset: Offset(0, -ResponsiveText.getSize(context, 14)),
                child: Container(
                  width: ResponsiveText.getSize(context, 30),
                  height: ResponsiveText.getSize(context, 30),
                  decoration: const BoxDecoration(
                    color: AppColor.primaryPurple,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: ResponsiveText.bodySmall(
                        context,
                        color: AppColor.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: ResponsiveText.getSize(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.mode,
                      style: ResponsiveText.bodySmall(
                        context,
                        fontWeight: FontWeight.w500,
                        color: AppColor.textSecondary,
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(0, ResponsiveText.getSize(context, -6)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                dropdownMenuTheme: DropdownMenuThemeData(
                                  menuStyle: MenuStyle(
                                    backgroundColor: WidgetStateProperty.all(
                                      AppColor.white,
                                    ),
                                    shape: WidgetStateProperty.all(
                                      RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              child: Container(
                                height: ResponsiveText.getSize(context, 38),
                                padding: ResponsiveText.symmetric(
                                  context,
                                  horizontal: 12,
                                  vertical: 0,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Center(
                                  child: DropdownButton<PhaseMode>(
                                    value: phase.mode,
                                    isExpanded: true,
                                    underline: const SizedBox(),
                                    icon: Icon(
                                      Icons.arrow_drop_down,
                                      size: ResponsiveText.getSize(context, 18),
                                      color: AppColor.textPrimary,
                                    ),
                                    dropdownColor: AppColor.white,
                                    borderRadius: BorderRadius.circular(8),
                                    style: ResponsiveText.body(
                                      context,
                                      color: AppColor.textPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    menuMaxHeight: 120,
                                    items: [
                                      DropdownMenuItem<PhaseMode>(
                                        value: PhaseMode.stimulation,
                                        child: _buildMenuItem(
                                          AppLocalizations.of(
                                            context,
                                          )!.stimulation,
                                          phase.mode == PhaseMode.stimulation,
                                        ),
                                      ),
                                      DropdownMenuItem<PhaseMode>(
                                        value: PhaseMode.expression,
                                        child: _buildMenuItem(
                                          AppLocalizations.of(
                                            context,
                                          )!.expression,
                                          phase.mode == PhaseMode.expression,
                                        ),
                                      ),
                                    ],
                                    selectedItemBuilder:
                                        (BuildContext context) {
                                          final l10n = AppLocalizations.of(
                                            context,
                                          )!;
                                          return [
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(l10n.stimulation),
                                            ),
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(l10n.expression),
                                            ),
                                          ];
                                        },
                                    onChanged: _isReadOnly
                                        ? null
                                        : (PhaseMode? newValue) {
                                            if (newValue != null) {
                                              setState(() {
                                                _phases[index].mode = newValue;
                                              });
                                            }
                                          },
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (!_isReadOnly) ...[
                            SizedBox(width: ResponsiveText.getSize(context, 8)),
                            IconButton(
                              icon: Icon(
                                size: ResponsiveText.getSize(context, 20),
                                Symbols.delete,
                                weight: 800,
                                color: _phases.length > _minPhases
                                    ? Colors.red
                                    : Colors.grey,
                              ),
                              onPressed: _phases.length > _minPhases
                                  ? () {
                                      setState(() {
                                        _phases.removeAt(index);
                                      });
                                    }
                                  : null,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: ResponsiveText.padding(
              context,
              left: 40,
              right: 14,
              top: 0,
              bottom: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppLocalizations.of(context)!.duration,
                  style: ResponsiveText.bodySmall(
                    context,
                    fontWeight: FontWeight.w500,
                    color: AppColor.textSecondary,
                  ),
                ),
                Text(
                  '${phase.duration} ${AppLocalizations.of(context)!.minutes}',
                  style: ResponsiveText.bodySmall(
                    context,
                    fontWeight: FontWeight.w500,
                    color: AppColor.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveText.getSize(context, 0)),
          Padding(
            padding: ResponsiveText.padding(
              context,
              left: 24,
              right: 0,
              top: 2,
              bottom: 2,
            ),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColor.textPrimary,
                inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                thumbColor: AppColor.white,
                thumbShape: _CustomSliderThumb(
                  enabledThumbRadius: ResponsiveText.getSize(context, 8),
                ),
                overlayShape: RoundSliderOverlayShape(
                  overlayRadius: ResponsiveText.getSize(context, 16),
                ),
                trackHeight: ResponsiveText.getSize(context, 16),
                tickMarkShape: const RoundSliderTickMarkShape(
                  tickMarkRadius: 0,
                ),
              ),
              child: Builder(
                builder: (context) {
                  final maxForPhase = _maxDurationForPhase(index);
                  final minForPhase = _minPhaseDuration.toDouble();
                  final span = maxForPhase - _minPhaseDuration;
                  return Slider(
                    value: phase.duration
                        .clamp(_minPhaseDuration, maxForPhase)
                        .toDouble(),
                    min: minForPhase,
                    max: maxForPhase.toDouble(),
                    divisions: span > 0 ? span : null,
                    onChanged: _isReadOnly || span <= 0
                        ? null
                        : (double value) {
                            setState(() {
                              _setPhaseDuration(index, value.round());
                            });
                          },
                  );
                },
              ),
            ),
          ),
          SizedBox(height: ResponsiveText.getSize(context, 0)),
          Padding(
            padding: ResponsiveText.padding(
              context,
              left: 40,
              right: 14,
              top: 0,
              bottom: 0,
            ),
            child: Text(
              phase.mode == PhaseMode.stimulation
                  ? AppLocalizations.of(context)!.stimulationDescription
                  : AppLocalizations.of(context)!.expressionDescription,
              style: ResponsiveText.bodySmall(
                context,
                color: AppColor.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddPhaseButton() {
    final canAdd =
        _phases.length < _maxPhases && _totalMinutes < _maxTotalMinutes;
    final borderColor = canAdd ? AppColor.primaryPurple : Colors.grey;
    final textColor = canAdd ? AppColor.primaryPurple : Colors.grey;

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AppColor.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: canAdd
              ? () {
                  setState(() {
                    final remaining = _maxTotalMinutes - _totalMinutes;
                    _phases.add(
                      Phase(
                        mode: PhaseMode.stimulation,
                        duration: remaining.clamp(_minPhaseDuration, 2),
                      ),
                    );
                  });
                }
              : null,
          borderRadius: BorderRadius.circular(12),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: borderColor,
              strokeWidth: 2,
              dashWidth: 4,
              dashSpace: 2,
              radius: 8,
            ),
            child: Container(
              padding: ResponsiveText.symmetric(context, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 20, color: textColor),
                  SizedBox(width: ResponsiveText.getSize(context, 8)),
                  Text(
                    AppLocalizations.of(context)!.addPhase,
                    style: ResponsiveText.smallTitle(
                      context,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFlowSummary() {
    final totalMinutes = _totalMinutes;
    final isOverLimit = totalMinutes > _maxTotalMinutes;
    final isAtMax = totalMinutes == _maxTotalMinutes;

    return Container(
      padding: ResponsiveText.padding(context, all: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.flowSummary,
            style: ResponsiveText.smallTitle(
              context,
              fontWeight: FontWeight.w500,
              color: AppColor.textPrimary,
            ),
          ),
          SizedBox(height: ResponsiveText.getSize(context, 38)),
          ...List.generate(_phases.length, (index) {
            final phase = _phases[index];
            return Padding(
              padding: EdgeInsets.only(
                bottom: ResponsiveText.getSize(context, 2),
              ),
              child: Text(
                '${index + 1}. ${phase.mode == PhaseMode.stimulation ? AppLocalizations.of(context)!.stimulation : AppLocalizations.of(context)!.expression} → ${phase.duration} ${AppLocalizations.of(context)!.minutes}',
                style: ResponsiveText.body(
                  context,
                  color: AppColor.textPrimary,
                ),
              ),
            );
          }),
          const Divider(),
          Text(
            AppLocalizations.of(context)!.totalMinutes(totalMinutes),
            style: ResponsiveText.smallTitle(
              context,
              fontWeight: FontWeight.w500,
              color: isOverLimit
                  ? Colors.red
                  : (isAtMax ? Colors.orange[800] : AppColor.textPrimary),
            ),
          ),
          if (isOverLimit)
            Padding(
              padding: EdgeInsets.only(
                top: ResponsiveText.getSize(context, 4),
              ),
              child: Text(
                AppLocalizations.of(context)!.customFlowTotalExceeded,
                style: ResponsiveText.bodySmall(
                  context,
                  color: Colors.red,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _totalMinutes > _maxTotalMinutes
            ? null
            : () async {
                if (_totalMinutes > _maxTotalMinutes) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context)!.customFlowTotalExceeded,
                      ),
                    ),
                  );
                  return;
                }
                await _saveCurrentTabPhases();
                await _persistSelectedTab();
                if (mounted) Navigator.of(context).pop(true);
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColor.primaryPurple,
          foregroundColor: AppColor.white,
          padding: ResponsiveText.symmetric(
            context,
            vertical: 6,
            horizontal: 12,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: Text(
          AppLocalizations.of(context)!.saveCustomFlow,
          style: ResponsiveText.smallTitle(
            context,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _CustomSliderThumb extends SliderComponentShape {
  final double enabledThumbRadius;

  const _CustomSliderThumb({this.enabledThumbRadius = 8.0});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(enabledThumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    final Paint borderPaint = Paint()
      ..color = AppColor.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final Paint fillPaint = Paint()
      ..color = AppColor.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, enabledThumbRadius, fillPaint);
    canvas.drawCircle(center, enabledThumbRadius, borderPaint);
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;
  final double radius;

  _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashSpace,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Radius.circular(radius),
        ),
      );

    final dashPath = _dashPath(path, dashWidth, dashSpace);
    canvas.drawPath(dashPath, paint);
  }

  Path _dashPath(Path path, double dashWidth, double dashSpace) {
    final dashPath = Path();
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        dashPath.addPath(
          metric.extractPath(distance, distance + dashWidth),
          Offset.zero,
        );
        distance += dashWidth + dashSpace;
      }
    }

    return dashPath;
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashWidth != dashWidth ||
        oldDelegate.dashSpace != dashSpace ||
        oldDelegate.radius != radius;
  }
}
