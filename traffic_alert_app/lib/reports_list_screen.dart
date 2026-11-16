import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'report_traffic_screen.dart' show backendBaseUrl;

class ReportsListScreen extends StatefulWidget {
  const ReportsListScreen({super.key});

  @override
  State<ReportsListScreen> createState() => _ReportsListScreenState();
}

class _ReportsListScreenState extends State<ReportsListScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _isLoading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(
        const Duration(seconds: 10), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
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
      if (!mounted) return;
      setState(() {
        _reports =
            data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _error = 'Could not load reports. Is the backend running?';
          _isLoading = false;
        });
      }
    }
  }

  Color _color(String severity) {
    switch (severity) {
      case 'Heavy':
        return Colors.red;
      case 'Moderate':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  String _time(dynamic value) =>
      (value ?? '').toString().replaceFirst('T', '   ');

  void _showDetails(Map<String, dynamic> r) {
    final severity = (r['severity'] ?? '').toString();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.location_on, color: _color(severity)),
            const SizedBox(width: 8),
            Expanded(child: Text('Report #${r['id']}')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Severity: $severity',
                style: TextStyle(
                    color: _color(severity), fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Address: ${r['address'] ?? ''}'),
            const SizedBox(height: 8),
            Text('Reported by: ${r['name'] ?? ''}'),
            const SizedBox(height: 8),
            Text('Phone: ${r['phone'] ?? ''}'),
            const SizedBox(height: 8),
            Text('Time: ${_time(r['created_at'])}'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3C72),
        foregroundColor: Colors.white,
        title: Text('All Reports (${_reports.length})'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _reports.isEmpty
                  ? const Center(child: Text('No reports yet'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _reports.length,
                        itemBuilder: (context, i) {
                          final r = _reports[i];
                          final severity = (r['severity'] ?? '').toString();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              onTap: () => _showDetails(r),
                              leading: CircleAvatar(
                                backgroundColor: _color(severity),
                                child: const Icon(Icons.traffic,
                                    color: Colors.white),
                              ),
                              title: Text('${r['address'] ?? ''}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  '${r['name'] ?? ''}  |  ${r['phone'] ?? ''}\n${_time(r['created_at'])}'),
                              isThreeLine: true,
                              trailing: Text(severity,
                                  style: TextStyle(
                                      color: _color(severity),
                                      fontWeight: FontWeight.bold)),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}