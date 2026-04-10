import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../config/app_color.dart';
import '../config/responsive_text.dart';
import '../services/database_service.dart';
import '../models/setting.dart';
import '../l10n/app_localizations.dart';

enum PhaseMode { stimulation, expression }

class Phase {
  PhaseMode mode;
  int duration; // 单位：分钟

  Phase({required this.mode, required this.duration});

  Map<String, dynamic> toJson() => {
    'mode': mode == PhaseMode.stimulation ? 'stimulation' : 'expression',
    'duration': duration,
  };

  factory Phase.fromJson(Map<String, dynamic> json) => Phase(
    mode: json['mode'] == 'stimulation'
        ? PhaseMode.stimulation
        : PhaseMode.expression,
    duration: json['duration'] as int,
  );
}

class CustomFlowPage extends StatefulWidget {
  const CustomFlowPage({super.key});

  @override
  State<CustomFlowPage> createState() => _CustomFlowPageState();
}

class _CustomFlowPageState extends State<CustomFlowPage> {
  static const String _settingKey = 'custom_flow_phases';
  static const int _maxPhases = 4;
  static const int _minPhases = 2;

  String _getSettingDesc(BuildContext context) {
    return AppLocalizations.of(context)!.customFlowSettingDesc;
  }

  final DatabaseService _dbService = DatabaseService();
  List<Phase> _phases = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPhases();
  }

  Future<void> _loadPhases() async {
    final setting = await _dbService.getSettingByKey(_settingKey);
    if (setting != null) {
      final List<dynamic> jsonList = jsonDecode(setting.value);
      _phases = jsonList.map((e) => Phase.fromJson(e)).toList();
    } else {
      // 首次使用时的默认值
      _phases = [
        Phase(mode: PhaseMode.stimulation, duration: 2),
        Phase(mode: PhaseMode.expression, duration: 15),
      ];
    }
    setState(() => _isLoading = false);
  }

  Future<void> _savePhases() async {
    final jsonValue = jsonEncode(_phases.map((p) => p.toJson()).toList());
    final existing = await _dbService.getSettingByKey(_settingKey);
    if (existing != null) {
      await _dbService.updateSettingByKey(_settingKey, jsonValue);
    } else {
      if (!mounted) return;
      await _dbService.insertSetting(
        Setting(
          key: _settingKey,
          desc: _getSettingDesc(context),
          value: jsonValue,
        ),
      );
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
                      ...List.generate(_phases.length, (index) {
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: ResponsiveText.getSize(context, 8),
                          ),
                          child: _buildPhaseCard(index),
                        );
                      }),
                      SizedBox(height: ResponsiveText.getSize(context, 8)),
                      _buildAddPhaseButton(),
                      SizedBox(height: ResponsiveText.getSize(context, 12)),
                      _buildFlowSummary(),
                      SizedBox(height: ResponsiveText.getSize(context, 8)),
                      _buildSaveButton(),
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
            onPressed: () {
              Navigator.of(context).pop();
            },
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
                                    onChanged: (PhaseMode? newValue) {
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
              child: Slider(
                value: phase.duration.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                onChanged: (double value) {
                  final roundedValue = value.roundToDouble();
                  setState(() {
                    _phases[index].duration = roundedValue.toInt();
                  });
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
    final canAdd = _phases.length < _maxPhases;
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
                    _phases.add(
                      Phase(mode: PhaseMode.stimulation, duration: 2),
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
    int totalMinutes = _phases.fold(0, (sum, phase) => sum + phase.duration);

    return Container(
      padding: ResponsiveText.padding(context, all: 16),
      decoration: BoxDecoration(
        color: Color(0xFFF9FAFB),
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
              color: AppColor.textPrimary,
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
        onPressed: () async {
          await _savePhases();
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
