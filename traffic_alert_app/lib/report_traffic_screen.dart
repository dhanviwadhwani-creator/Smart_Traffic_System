import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'notification_service.dart';

// 127.0.0.1 works with: adb reverse tcp:5000 tcp:5000 (emulator or USB phone).
const String backendBaseUrl = 'https://smart-traffic-system-b0nh.onrender.com';

class ReportTrafficScreen extends StatefulWidget {
  const ReportTrafficScreen({super.key});

  @override
  State<ReportTrafficScreen> createState() => _ReportTrafficScreenState();
}

class _ReportTrafficScreenState extends State<ReportTrafficScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  String _selectedSeverity = 'Moderate';
  bool _isSubmitting = false;

  File? _photo;
  final ImagePicker _picker = ImagePicker();

  final List<Map<String, dynamic>> _severityOptions = [
    {'label': 'Low', 'color': Colors.green},
    {'label': 'Moderate', 'color': Colors.orange},
    {'label': 'Heavy', 'color': Colors.red},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 60,
        maxWidth: 1280,
      );
      if (picked != null) {
        setState(() => _photo = File(picked.path));
      }
    } catch (e) {
      _showError('Could not pick the photo');
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (_photo != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _photo = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      String? photoB64;
      if (_photo != null) {
        photoB64 = base64Encode(await _photo!.readAsBytes());
      }

      final response = await http
          .post(
            Uri.parse('$backendBaseUrl/api/reports'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': _nameController.text.trim(),
              'phone': _phoneController.text.trim(),
              'address': _addressController.text.trim(),
              'severity': _selectedSeverity,
              'photo': photoB64,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (response.statusCode == 201) {
        if (_selectedSeverity == 'Heavy') {
          NotificationService.showHeavyTrafficAlert(
              _addressController.text.trim());
        }
        _showSuccessDialog();
      } else {
        _showError('Server error (${response.statusCode}). Please try again.');
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Could not reach the server. Is the backend running?');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Report Submitted'),
          ],
        ),
        content: const Text('Thank you! Your traffic report has been saved.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _formKey.currentState!.reset();
              _nameController.clear();
              _phoneController.clear();
              _addressController.clear();
              setState(() {
                _selectedSeverity = 'Moderate';
                _photo = null;
              });
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  InputDecoration _decoration(IconData icon, String hint) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: Colors.grey),
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1E3C72), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        title: const Text('Report Traffic'),
        backgroundColor: const Color(0xFF1E3C72),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Help others by reporting congestion near you',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
              ),
              _label('Full Name'),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: _decoration(Icons.person_outline, 'Your name'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter your name'
                    : null,
              ),
              _label('Phone Number'),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: _decoration(Icons.phone_outlined, 'Phone number'),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'Please enter your phone number';
                  if (value.replaceAll(RegExp(r'[^0-9]'), '').length < 10) {
                    return 'Enter a valid phone number';
                  }
                  return null;
                },
              ),
              _label('Address / Landmark'),
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                decoration:
                    _decoration(Icons.location_on_outlined, 'Where is the traffic?'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter the address or landmark'
                    : null,
              ),
              _label('Traffic Severity'),
              Row(
                children: _severityOptions.map((option) {
                  final String label = option['label'] as String;
                  final Color color = option['color'] as Color;
                  final bool selected = _selectedSeverity == label;
                  return Expanded(
                    child: GestureDetector(
                      onTap: _isSubmitting
                          ? null
                          : () => setState(() => _selectedSeverity = label),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: selected
                              ? color.withValues(alpha: 0.15)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? color : Colors.grey.shade300,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.circle, color: color, size: 12),
                            const SizedBox(height: 8),
                            Text(
                              label,
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: selected ? Colors.black : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _showPhotoOptions,
                icon: const Icon(Icons.add_a_photo),
                label: Text(_photo == null
                    ? 'Add Photo (optional)'
                    : 'Change / Remove Photo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1E3C72),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
              if (_photo != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(_photo!, height: 160, fit: BoxFit.cover),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitReport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3C72),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Submit Report',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}