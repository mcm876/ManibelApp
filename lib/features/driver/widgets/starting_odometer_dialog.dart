import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';

/// Largest odometer reading accepted — matches the backend's
/// `startingOdometer` bound (POST /api/driver/trips/start).
const double kMaxOdometerKm = 9999999;

/// Parses what the driver typed into an odometer reading in km, or null if it
/// isn't a usable one — empty, letters/symbols, negative, more than one
/// decimal point, or beyond [kMaxOdometerKm]. Shared by the dialog's
/// validation and its tests so they can't drift apart.
double? parseOdometerKm(String input) {
  final text = input.trim().replaceAll(',', '');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) return null;
  final value = double.tryParse(text);
  if (value == null || !value.isFinite || value < 0 || value > kMaxOdometerKm) {
    return null;
  }
  return value;
}

/// "12543" for whole numbers, "12543.5" otherwise.
String formatOdometerKm(double km) =>
    km == km.roundToDouble() ? km.toStringAsFixed(0) : km.toString();

/// Asks for the vehicle's current odometer before a trip can start. Returns
/// the reading in km, or null if the driver cancelled — in which case no trip
/// may be started.
Future<double?> showStartingOdometerDialog(
  BuildContext context, {
  double? initialValue,
}) {
  return showDialog<double>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _StartingOdometerDialog(initialValue: initialValue),
  );
}

class _StartingOdometerDialog extends StatefulWidget {
  const _StartingOdometerDialog({this.initialValue});

  final double? initialValue;

  @override
  State<_StartingOdometerDialog> createState() =>
      _StartingOdometerDialogState();
}

class _StartingOdometerDialogState extends State<_StartingOdometerDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue == null
        ? ''
        : formatOdometerKm(widget.initialValue!),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = parseOdometerKm(_controller.text);
    if (value == null) {
      setState(() => _error = 'Please enter a valid odometer reading.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Start Trip',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Odometer',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              LengthLimitingTextInputFormatter(11),
            ],
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Enter odometer reading',
              suffixText: 'km',
              errorText: _error,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Enter the odometer reading shown on the vehicle right now, before you start the trip.',
            style: TextStyle(
              fontSize: 11,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.only(right: 12, bottom: 8),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700),
          ),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text(
            'Start Trip',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
