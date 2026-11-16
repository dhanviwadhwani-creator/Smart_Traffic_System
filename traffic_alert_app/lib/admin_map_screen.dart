import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'notification_service.dart';
import 'report_traffic_screen.dart' show backendBaseUrl;
import 'reports_list_screen.dart';

// Optional: paste your real TomTom key here. Leave it empty to use OpenStreetMap.
const String tomTomApiKey = '';

class TrafficReport {
  final int id;
  final String name;
  final String phone;
  final String address;
  final String severity; // 'Low', 'Moderate', 'Heavy'
  final String createdAt;
  final String? photo;
  final LatLng? position;

  TrafficReport({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.severity,
    required this.createdAt,
    required this.photo,
    required this.position,
  });

  factory TrafficReport.fromJson(Map<String, dynamic> json) {
    final lat = json['lat'];
    final lng = json['lng'];
    return TrafficReport(
      id: json['id'] as int,
      name: (json['name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      severity: (json['severity'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      photo: json['photo']?.toString(),
      position: (lat is num && lng is num)
          ? LatLng(lat.toDouble(), lng.toDouble())
          : null,
    );
  }
}

class AdminMapScreen extends StatefulWidget {
  const AdminMapScreen({super.key});

  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> {
  List<TrafficReport> _reports = [];
  bool _isLoading = true;
  String? _error;

  Timer? _timer;
  int _lastSeenId = 0;
  bool _firstLoadDone = false;

  final MapController _mapController = MapController();
  LatLng? _myLocation;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final response = await http
          .get(Uri.parse('$backendBaseUrl/api/reports'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('Server error ${response.statusCode}');
      }
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      final reports = data
          .map((item) => TrafficReport.fromJson(item as Map<String, dynamic>))
          .toList();

      if (reports.isNotEmpty) {
        final maxId = reports.map((r) => r.id).reduce((a, b) => a > b ? a : b);
        if (_firstLoadDone) {
          final newHeavy = reports
              .where((r) => r.id > _lastSeenId && r.severity == 'Heavy')
              .toList();
          for (final r in newHeavy) {
            NotificationService.showHeavyTrafficAlert(r.address);
          }
        }
        if (maxId > _lastSeenId) _lastSeenId = maxId;
      }
      _firstLoadDone = true;

      if (!mounted) return;
      setState(() {
        _reports = reports;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load reports. Is the backend running?';
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _goToMyLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _snack('Please turn on location (GPS)');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack('Location permission denied');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final here = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _myLocation = here);
      _mapController.move(here, 15);
    } catch (e) {
      _snack('Could not get your location');
    }
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'Heavy':
        return Colors.red;
      case 'Moderate':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  String _time(String value) => value.replaceFirst('T', '   ');

  void _showReportDetails(TrafficReport r) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.location_on, color: _severityColor(r.severity)),
            const SizedBox(width: 8),
            Expanded(child: Text('Report #${r.id}')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Severity: ${r.severity}',
                style: TextStyle(
                  color: _severityColor(r.severity),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('Address: ${r.address}'),
              const SizedBox(height: 8),
              Text('Reported by: ${r.name}'),
              const SizedBox(height: 8),
              Text('Phone: ${r.phone}'),
              const SizedBox(height: 8),
              Text('Time: ${_time(r.createdAt)}'),
              if (r.photo != null && r.photo!.isNotEmpty) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    '$backendBaseUrl/uploads/${r.photo}',
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) =>
                        const Text('Photo could not be loaded'),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _statCard(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, color: color, size: 12),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mappedReports = _reports.where((r) => r.position != null).toList()
      ..sort((a, b) =>
          (a.severity == 'Heavy' ? 1 : 0) - (b.severity == 'Heavy' ? 1 : 0));
    final int heavyCount = _reports.where((r) => r.severity == 'Heavy').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin \u2014 Live Traffic Map'),
        backgroundColor: const Color(0xFF1E3C72),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'All Reports',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportsListScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : () => _load(showSpinner: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: const Color(0xFF1E3C72),
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
            child: Row(
              children: [
                _statCard(Icons.place, '${_reports.length}', 'Reports'),
                _statCard(Icons.warning_amber_rounded, '$heavyCount',
                    'Heavy Zones'),
                _statCard(Icons.notifications_active, '$heavyCount',
                    'Alerts Sent'),
              ],
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.all(10),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    initialCenter: LatLng(25.1762, 75.8370), // Kota, Rajasthan
                    initialZoom: 13,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: tomTomApiKey.isEmpty
                          ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                          : 'https://api.tomtom.com/map/1/tile/basic/main/{z}/{x}/{y}.png?key=$tomTomApiKey',
                      userAgentPackageName: 'com.example.traffic_alert_app',
                    ),
                    MarkerLayer(
                      markers: mappedReports.map((report) {
                        return Marker(
                          point: report.position!,
                          width: 46,
                          height: 46,
                          child: GestureDetector(
                            onTap: () => _showReportDetails(report),
                            child: Icon(
                              Icons.location_on,
                              color: _severityColor(report.severity),
                              size: 36,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (_myLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _myLocation!,
                            width: 24,
                            height: 24,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'my_location',
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF1E3C72),
                    onPressed: _goToMyLocation,
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _legendItem(Colors.green, 'Low'),
                _legendItem(Colors.orange, 'Moderate'),
                _legendItem(Colors.red, 'Heavy'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}