import 'package:portal/providers/group_calendar_provider.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/providers/vrchat_status_provider.dart';

class TestGroupMonitorNotifier extends GroupMonitorNotifier {
  TestGroupMonitorNotifier(this._initialState, {String userId = 'usr_test'})
    : super(userId);

  final GroupMonitorState _initialState;

  @override
  GroupMonitorState build() => _initialState;
}

class TestGroupCalendarNotifier extends GroupCalendarNotifier {
  TestGroupCalendarNotifier(this._initialState, {String userId = 'usr_test'})
    : super(userId);

  final GroupCalendarState _initialState;

  @override
  GroupCalendarState build() => _initialState;
}

class TestVrchatStatusNotifier extends VrchatStatusNotifier {
  TestVrchatStatusNotifier(this._initialState);

  final VrchatStatusState _initialState;

  @override
  VrchatStatusState build() => _initialState;
}
