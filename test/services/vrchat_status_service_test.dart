import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/models/vrchat_status.dart';
import 'package:portal/services/vrchat_status_service.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late VrchatStatusService service;
  late MockDio mockDio;

  setUp(() {
    mockDio = MockDio();
    service = VrchatStatusService(mockDio);
  });

  void mockSuccessResponse(Map<String, dynamic> responseData) {
    final response = Response(
      data: responseData,
      statusCode: 200,
      requestOptions: RequestOptions(path: ''),
    );
    when(() => mockDio.get(any())).thenAnswer((_) async => response);
  }

  group('VrchatStatusService - Success Cases', () {
    test('1.1: Complete valid response with all fields', () async {
      mockSuccessResponse({
        'status': {
          'indicator': 'none',
          'description': 'All systems operational',
        },
        'components': [
          {
            'id': 'api-group',
            'group': true,
            'name': 'API & Website',
            'status': 'operational',
          },
          {
            'id': 'api-service',
            'group': false,
            'group_id': 'api-group',
            'name': 'API Service',
            'status': 'operational',
          },
          {
            'id': 'website-service',
            'group': false,
            'group_id': 'api-group',
            'name': 'Website',
            'status': 'operational',
          },
          {
            'id': 'game-group',
            'group': true,
            'name': 'Game Servers',
            'status': 'degraded_performance',
          },
          {
            'id': 'us-west-service',
            'group': false,
            'group_id': 'game-group',
            'name': 'US West',
            'status': 'operational',
          },
          {
            'id': 'us-east-service',
            'group': false,
            'group_id': 'game-group',
            'name': 'US East',
            'status': 'partial_outage',
          },
        ],
        'incidents': [
          {
            'id': 'inc-1',
            'name': 'Past Incident',
            'status': 'resolved',
            'impact': 'High impact',
            'incident_updates': [
              {
                'status': 'investigating',
                'body': "We're investigating an issue",
                'created_at': '2024-01-01T10:00:00Z',
              },
              {
                'status': 'resolved',
                'body': 'Issue resolved',
                'created_at': '2024-01-01T12:00:00Z',
              },
            ],
            'created_at': '2024-01-01T10:00:00Z',
            'resolved_at': '2024-01-01T12:00:00Z',
          },
          {
            'id': 'inc-2',
            'name': 'Active Incident',
            'status': 'investigating',
            'impact': 'Medium impact',
            'incident_updates': [
              {
                'status': 'investigating',
                'body': 'Investigating the issue',
                'created_at': '2024-01-02T10:00:00Z',
              },
            ],
            'created_at': '2024-01-02T10:00:00Z',
          },
          {
            'id': 'inc-3',
            'name': 'Monitoring Incident',
            'status': 'monitoring',
            'incident_updates': [],
            'created_at': '2024-01-03T08:00:00Z',
          },
        ],
      });

      final status = await service.fetchStatus();

      expect(status.description, equals('All systems operational'));
      expect(status.indicator, equals(VrchatStatusIndicator.none));
      expect(status.serviceGroups, hasLength(2));

      expect(status.serviceGroups[0].name, equals('API & Website'));
      expect(status.serviceGroups[0].status, equals('operational'));
      expect(status.serviceGroups[0].services, hasLength(2));
      expect(status.serviceGroups[0].services[0].name, equals('API Service'));
      expect(status.serviceGroups[0].services[1].name, equals('Website'));

      expect(status.serviceGroups[1].name, equals('Game Servers'));
      expect(status.serviceGroups[1].status, equals('degraded_performance'));
      expect(status.serviceGroups[1].services, hasLength(2));

      expect(status.activeIncidents, hasLength(2));
      expect(status.activeIncidents[0].id, equals('inc-2'));
      expect(status.activeIncidents[1].id, equals('inc-3'));
    });

    test('1.2: Indicator "none"', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'Normal'},
        'components': [],
        'incidents': [],
      });

      final status = await service.fetchStatus();
      expect(status.indicator, equals(VrchatStatusIndicator.none));
    });

    test('1.3: Indicator "minor"', () async {
      mockSuccessResponse({
        'status': {'indicator': 'minor', 'description': 'Minor issues'},
        'components': [],
        'incidents': [],
      });

      final status = await service.fetchStatus();
      expect(status.indicator, equals(VrchatStatusIndicator.minor));
    });

    test('1.4: Indicator "major"', () async {
      mockSuccessResponse({
        'status': {'indicator': 'major', 'description': 'Major issues'},
        'components': [],
        'incidents': [],
      });

      final status = await service.fetchStatus();
      expect(status.indicator, equals(VrchatStatusIndicator.major));
    });

    test('1.5: Indicator "critical"', () async {
      mockSuccessResponse({
        'status': {'indicator': 'critical', 'description': 'Critical'},
        'components': [],
        'incidents': [],
      });

      final status = await service.fetchStatus();
      expect(status.indicator, equals(VrchatStatusIndicator.critical));
    });
  });

  group('VrchatStatusService - Indicator Edge Cases', () {
    test('2.1: Unknown indicator defaults to "none"', () async {
      mockSuccessResponse({
        'status': {'indicator': 'unknown', 'description': 'Unknown status'},
        'components': [],
        'incidents': [],
      });

      final status = await service.fetchStatus();
      expect(status.indicator, equals(VrchatStatusIndicator.none));
    });
  });

  group('VrchatStatusService - Component Parsing', () {
    test('3.1: Single group with multiple services', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [
          {
            'id': 'group-1',
            'group': true,
            'name': 'Group One',
            'status': 'operational',
          },
          {
            'id': 'service-a',
            'group': false,
            'group_id': 'group-1',
            'name': 'Service A',
            'status': 'operational',
          },
          {
            'id': 'service-b',
            'group': false,
            'group_id': 'group-1',
            'name': 'Service B',
            'status': 'degraded_performance',
          },
        ],
        'incidents': [],
      });

      final status = await service.fetchStatus();
      expect(status.serviceGroups, hasLength(1));
      expect(status.serviceGroups[0].name, equals('Group One'));
      expect(status.serviceGroups[0].status, equals('operational'));
      expect(status.serviceGroups[0].services, hasLength(2));
      expect(status.serviceGroups[0].services[0].name, equals('Service A'));
      expect(status.serviceGroups[0].services[0].status, equals('operational'));
      expect(status.serviceGroups[0].services[1].name, equals('Service B'));
      expect(
        status.serviceGroups[0].services[1].status,
        equals('degraded_performance'),
      );
    });

    test('3.2: Empty components list', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [],
        'incidents': [],
      });

      final status = await service.fetchStatus();
      expect(status.serviceGroups, isEmpty);
    });

    test('3.3: Component without group_id (null)', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [
          {
            'id': 'service-orphan',
            'group': false,
            'group_id': null,
            'name': 'Orphan Service',
            'status': 'operational',
          },
          {
            'id': 'group-1',
            'group': true,
            'name': 'Group One',
            'status': 'operational',
          },
        ],
        'incidents': [],
      });

      final status = await service.fetchStatus();
      expect(status.serviceGroups, hasLength(1));
      expect(status.serviceGroups[0].name, equals('Group One'));
      expect(status.serviceGroups[0].services, isEmpty);
    });

    test('3.4: Component missing group_id field entirely', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [
          {
            'id': 'service-no-group',
            'group': false,
            'name': 'No Group ID',
            'status': 'operational',
          },
        ],
        'incidents': [],
      });

      final status = await service.fetchStatus();
      expect(status.serviceGroups, isEmpty);
    });

    test('3.5: Multiple groups with services', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [
          {
            'id': 'group-a',
            'group': true,
            'name': 'Group A',
            'status': 'operational',
          },
          {
            'id': 'service-a1',
            'group': false,
            'group_id': 'group-a',
            'name': 'Service A1',
            'status': 'operational',
          },
          {
            'id': 'group-b',
            'group': true,
            'name': 'Group B',
            'status': 'major_outage',
          },
          {
            'id': 'service-b1',
            'group': false,
            'group_id': 'group-b',
            'name': 'Service B1',
            'status': 'major_outage',
          },
        ],
        'incidents': [],
      });

      final status = await service.fetchStatus();
      expect(status.serviceGroups, hasLength(2));
      expect(status.serviceGroups[0].name, equals('Group A'));
      expect(status.serviceGroups[0].status, equals('operational'));
      expect(status.serviceGroups[1].name, equals('Group B'));
      expect(status.serviceGroups[1].status, equals('major_outage'));
    });

    test('3.6: Group with no services', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [
          {
            'id': 'empty-group',
            'group': true,
            'name': 'Empty Group',
            'status': 'operational',
          },
        ],
        'incidents': [],
      });

      final status = await service.fetchStatus();
      expect(status.serviceGroups, hasLength(1));
      expect(status.serviceGroups[0].services, isEmpty);
    });

    test('3.7: All component status values', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [
          {
            'id': 'group-1',
            'group': true,
            'name': 'Status Group',
            'status': 'operational',
          },
          {
            'id': 'service-op',
            'group': false,
            'group_id': 'group-1',
            'name': 'Operational',
            'status': 'operational',
          },
          {
            'id': 'service-deg',
            'group': false,
            'group_id': 'group-1',
            'name': 'Degraded',
            'status': 'degraded_performance',
          },
          {
            'id': 'service-part',
            'group': false,
            'group_id': 'group-1',
            'name': 'Partial',
            'status': 'partial_outage',
          },
          {
            'id': 'service-major',
            'group': false,
            'group_id': 'group-1',
            'name': 'Major',
            'status': 'major_outage',
          },
        ],
        'incidents': [],
      });

      final status = await service.fetchStatus();
      final services = status.serviceGroups[0].services;
      expect(services[0].status, equals('operational'));
      expect(services[1].status, equals('degraded_performance'));
      expect(services[2].status, equals('partial_outage'));
      expect(services[3].status, equals('major_outage'));
    });

    test('3.8: Services before their group definition', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [
          {
            'id': 'service-a',
            'group': false,
            'group_id': 'group-1',
            'name': 'Service A',
            'status': 'operational',
          },
          {
            'id': 'group-1',
            'group': true,
            'name': 'Group One',
            'status': 'operational',
          },
        ],
        'incidents': [],
      });

      final status = await service.fetchStatus();
      expect(status.serviceGroups, hasLength(1));
      expect(status.serviceGroups[0].services, hasLength(1));
      expect(status.serviceGroups[0].services[0].name, equals('Service A'));
    });
  });

  group('VrchatStatusService - Incident Parsing', () {
    test('4.1: Multiple incidents, mixed statuses', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [],
        'incidents': [
          {
            'id': 'inc-1',
            'name': 'Investigating Incident',
            'status': 'investigating',
            'impact': 'High impact',
            'incident_updates': [
              {
                'status': 'investigating',
                'body': 'Investigating',
                'created_at': '2024-01-01T10:00:00Z',
              },
            ],
            'created_at': '2024-01-01T10:00:00Z',
          },
          {
            'id': 'inc-2',
            'name': 'Identified Incident',
            'status': 'identified',
            'impact': 'Medium impact',
            'incident_updates': [],
            'created_at': '2024-01-01T11:00:00Z',
          },
          {
            'id': 'inc-3',
            'name': 'Monitoring Incident',
            'status': 'monitoring',
            'incident_updates': [],
            'created_at': '2024-01-01T12:00:00Z',
          },
          {
            'id': 'inc-4',
            'name': 'Resolved Incident',
            'status': 'resolved',
            'impact': 'Low impact',
            'incident_updates': [],
            'created_at': '2024-01-01T08:00:00Z',
            'resolved_at': '2024-01-01T13:00:00Z',
          },
        ],
      });

      final status = await service.fetchStatus();
      expect(status.activeIncidents, hasLength(3));
      expect(
        status.activeIncidents[0].status,
        equals(IncidentStatus.investigating),
      );
      expect(
        status.activeIncidents[1].status,
        equals(IncidentStatus.identified),
      );
      expect(
        status.activeIncidents[2].status,
        equals(IncidentStatus.monitoring),
      );
      expect(status.activeIncidents.any((i) => i.id == 'inc-4'), isFalse);
    });

    test('4.2: All incidents resolved', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [],
        'incidents': [
          {
            'id': 'inc-1',
            'name': 'Resolved 1',
            'status': 'resolved',
            'impact': 'None',
            'incident_updates': [],
            'created_at': '2024-01-01T10:00:00Z',
            'resolved_at': '2024-01-01T11:00:00Z',
          },
          {
            'id': 'inc-2',
            'name': 'Resolved 2',
            'status': 'resolved',
            'incident_updates': [],
            'created_at': '2024-01-01T12:00:00Z',
            'resolved_at': '2024-01-01T13:00:00Z',
          },
        ],
      });

      final status = await service.fetchStatus();
      expect(status.activeIncidents, isEmpty);
    });

    test('4.3: Empty incidents list', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [],
        'incidents': [],
      });

      final status = await service.fetchStatus();
      expect(status.activeIncidents, isEmpty);
    });

    test('4.4: Incident with all optional fields', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [],
        'incidents': [
          {
            'id': 'inc-full',
            'name': 'Full Incident',
            'status': 'investigating',
            'impact': 'Critical impact affecting all services',
            'incident_updates': [
              {
                'status': 'investigating',
                'body': 'Initial report received',
                'created_at': '2024-01-01T10:00:00Z',
              },
              {
                'status': 'identified',
                'body': 'Root cause identified',
                'created_at': '2024-01-01T10:30:00Z',
              },
              {
                'status': 'monitoring',
                'body': 'Fix deployed, monitoring',
                'created_at': '2024-01-01T11:00:00Z',
              },
            ],
            'created_at': '2024-01-01T10:00:00Z',
          },
        ],
      });

      final status = await service.fetchStatus();
      expect(status.activeIncidents, hasLength(1));
      final incident = status.activeIncidents[0];
      expect(incident.id, equals('inc-full'));
      expect(incident.name, equals('Full Incident'));
      expect(incident.impact, equals('Critical impact affecting all services'));
      expect(incident.updates, hasLength(3));
      expect(incident.updates[0].status, equals(IncidentStatus.investigating));
      expect(incident.updates[1].status, equals(IncidentStatus.identified));
      expect(incident.updates[2].status, equals(IncidentStatus.monitoring));
      expect(
        incident.createdAt,
        equals(DateTime.parse('2024-01-01T10:00:00Z')),
      );
    });

    test('4.5: Incident without impact field', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [],
        'incidents': [
          {
            'id': 'inc-no-impact',
            'name': 'No Impact',
            'status': 'investigating',
            'incident_updates': [],
            'created_at': '2024-01-01T10:00:00Z',
          },
        ],
      });

      final status = await service.fetchStatus();
      expect(status.activeIncidents[0].impact, equals(''));
    });

    test('4.6: Incident without resolved_at', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [],
        'incidents': [
          {
            'id': 'inc-no-resolved',
            'name': 'Not Resolved',
            'status': 'investigating',
            'impact': 'Some impact',
            'incident_updates': [],
            'created_at': '2024-01-01T10:00:00Z',
          },
        ],
      });

      final status = await service.fetchStatus();
      expect(status.activeIncidents[0].resolvedAt, isNull);
    });

    test('4.7: Incident with empty updates list', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [],
        'incidents': [
          {
            'id': 'inc-no-updates',
            'name': 'No Updates',
            'status': 'investigating',
            'impact': 'Impact',
            'incident_updates': [],
            'created_at': '2024-01-01T10:00:00Z',
          },
        ],
      });

      final status = await service.fetchStatus();
      expect(status.activeIncidents[0].updates, isEmpty);
    });

    test('4.8: Incident update without body field', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [],
        'incidents': [
          {
            'id': 'inc-no-body',
            'name': 'No Body',
            'status': 'investigating',
            'impact': 'Impact',
            'incident_updates': [
              {'status': 'investigating', 'created_at': '2024-01-01T10:00:00Z'},
            ],
            'created_at': '2024-01-01T10:00:00Z',
          },
        ],
      });

      final status = await service.fetchStatus();
      expect(status.activeIncidents[0].updates[0].body, equals(''));
    });
  });

  group('VrchatStatusService - Incident Status Edge Cases', () {
    test('5.1: Unknown incident status defaults to "investigating"', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [],
        'incidents': [
          {
            'id': 'inc-unknown',
            'name': 'Unknown Status',
            'status': 'unknown_status',
            'incident_updates': [],
            'created_at': '2024-01-01T10:00:00Z',
          },
        ],
      });

      final status = await service.fetchStatus();
      expect(
        status.activeIncidents[0].status,
        equals(IncidentStatus.investigating),
      );
    });
  });

  group('VrchatStatusService - Network Error Cases', () {
    test('6.1: DioException with connection error', () async {
      when(() => mockDio.get(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionError,
        ),
      );

      expect(() => service.fetchStatus(), throwsA(isA<DioException>()));
    });

    test('6.2: DioException with timeout', () async {
      when(() => mockDio.get(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.receiveTimeout,
        ),
      );

      expect(() => service.fetchStatus(), throwsA(isA<DioException>()));
    });

    test('6.3: Generic DioException', () async {
      when(() => mockDio.get(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.badResponse,
        ),
      );

      expect(() => service.fetchStatus(), throwsA(isA<DioException>()));
    });
  });

  group('VrchatStatusService - JSON Parsing Error Cases', () {
    test('7.1: Invalid JSON response (data is string, not map)', () async {
      final response = Response(
        data: 'not valid json',
        statusCode: 200,
        requestOptions: RequestOptions(path: ''),
      );
      when(() => mockDio.get(any())).thenAnswer((_) async => response);

      expect(() => service.fetchStatus(), throwsA(isA<Error>()));
    });

    test('7.2: Response data is not a Map (list instead)', () async {
      final response = Response(
        data: [],
        statusCode: 200,
        requestOptions: RequestOptions(path: ''),
      );
      when(() => mockDio.get(any())).thenAnswer((_) async => response);

      expect(() => service.fetchStatus(), throwsA(isA<Error>()));
    });

    test('7.3: Missing status field', () async {
      mockSuccessResponse({'components': [], 'incidents': []});

      expect(() => service.fetchStatus(), throwsA(isA<Error>()));
    });

    test('7.4: Components is not a List (object instead)', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': {},
        'incidents': [],
      });

      expect(() => service.fetchStatus(), throwsA(isA<Error>()));
    });

    test('7.5: Incidents is not a List (object instead)', () async {
      mockSuccessResponse({
        'status': {'indicator': 'none', 'description': 'OK'},
        'components': [],
        'incidents': {},
      });

      expect(() => service.fetchStatus(), throwsA(isA<Error>()));
    });
  });
}
