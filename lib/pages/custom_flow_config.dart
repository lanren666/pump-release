import 'dart:convert';

import '../services/database_service.dart';
import '../models/setting.dart';

enum CustomFlowTab { boostMilk, custom1, custom2 }

enum PhaseMode { stimulation, expression }

class Phase {
  PhaseMode mode;
  int duration;

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

class CustomFlowConfig {
  static const String selectedTabKey = 'selected_custom_flow_tab';
  static const String legacyPhasesKey = 'custom_flow_phases';
  static const String custom1Key = 'custom_flow_phases_1';
  static const String custom2Key = 'custom_flow_phases_2';

  static List<Phase> get boostMilkPhases => [
        Phase(mode: PhaseMode.stimulation, duration: 2),
        Phase(mode: PhaseMode.expression, duration: 3),
      ];

  static List<Phase> get defaultCustomPhases => [
        Phase(mode: PhaseMode.stimulation, duration: 2),
        Phase(mode: PhaseMode.expression, duration: 15),
      ];

  static String phasesKeyForTab(CustomFlowTab tab) {
    switch (tab) {
      case CustomFlowTab.boostMilk:
        return '';
      case CustomFlowTab.custom1:
        return custom1Key;
      case CustomFlowTab.custom2:
        return custom2Key;
    }
  }

  static CustomFlowTab tabFromString(String? value) {
    switch (value) {
      case 'custom1':
        return CustomFlowTab.custom1;
      case 'custom2':
        return CustomFlowTab.custom2;
      default:
        return CustomFlowTab.boostMilk;
    }
  }

  static String tabToString(CustomFlowTab tab) {
    switch (tab) {
      case CustomFlowTab.boostMilk:
        return 'boostMilk';
      case CustomFlowTab.custom1:
        return 'custom1';
      case CustomFlowTab.custom2:
        return 'custom2';
    }
  }

  static String formatDescription(List<Phase> phases) {
    return phases.map((p) => '${p.duration}min').join(' -> ');
  }

  static Future<CustomFlowTab> loadSelectedTab(DatabaseService db) async {
    final setting = await db.getSettingByKey(selectedTabKey);
    return tabFromString(setting?.value);
  }

  static Future<void> saveSelectedTab(
    DatabaseService db,
    CustomFlowTab tab,
  ) async {
    final value = tabToString(tab);
    final existing = await db.getSettingByKey(selectedTabKey);
    if (existing != null) {
      await db.updateSettingByKey(selectedTabKey, value);
    } else {
      await db.insertSetting(
        Setting(
          key: selectedTabKey,
          desc: 'Selected custom flow tab',
          value: value,
        ),
      );
    }
  }

  static Future<List<Phase>> loadPhasesForTab(
    DatabaseService db,
    CustomFlowTab tab,
  ) async {
    if (tab == CustomFlowTab.boostMilk) {
      return List.from(boostMilkPhases);
    }

    final key = phasesKeyForTab(tab);
    var setting = await db.getSettingByKey(key);

    if (setting == null && tab == CustomFlowTab.custom1) {
      final legacy = await db.getSettingByKey(legacyPhasesKey);
      if (legacy != null) {
        setting = legacy;
      }
    }

    if (setting != null) {
      final List<dynamic> jsonList = jsonDecode(setting.value);
      return jsonList.map((e) => Phase.fromJson(e)).toList();
    }

    return List.from(defaultCustomPhases);
  }

  static Future<List<Phase>> loadPhasesForSelectedTab(
    DatabaseService db,
  ) async {
    final tab = await loadSelectedTab(db);
    return loadPhasesForTab(db, tab);
  }

  static Future<void> savePhasesForTab(
    DatabaseService db,
    CustomFlowTab tab,
    List<Phase> phases, {
    required String desc,
  }) async {
    if (tab == CustomFlowTab.boostMilk) return;

    final key = phasesKeyForTab(tab);
    final jsonValue = jsonEncode(phases.map((p) => p.toJson()).toList());
    final existing = await db.getSettingByKey(key);
    if (existing != null) {
      await db.updateSettingByKey(key, jsonValue);
    } else {
      await db.insertSetting(
        Setting(key: key, desc: desc, value: jsonValue),
      );
    }
  }
}
