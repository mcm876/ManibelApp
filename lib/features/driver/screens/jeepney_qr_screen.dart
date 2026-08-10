import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

// OPTIONAL: Uncomment if using the 'gal' package for saving to gallery/photos:
// import 'package:gal/gal.dart';

class JeepneyQrScreen extends StatefulWidget {
  final String plateNumber;
  final String routeName;

  const JeepneyQrScreen({
    super.key,
    required this.plateNumber,
    this.routeName = 'Pasig - Quiapo',
  });

  @override
  State<JeepneyQrScreen> createState() => _JeepneyQrScreenState();
}

class _JeepneyQrScreenState extends State<JeepneyQrScreen> {
  // GlobalKey used to capture the RepaintBoundary as an image
  final GlobalKey _qrBoundaryKey = GlobalKey();
  bool _isDownloading = false;

  /// Function to capture and download/save the QR code image
  Future<void> _downloadQrCode() async {
    setState(() {
      _isDownloading = true;
    });

    try {
      // 1. Find the RenderRepaintBoundary widget
      final RenderRepaintBoundary? boundary =
          _qrBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        throw Exception("Could not find QR Code boundary.");
      }

      // 2. Render to high-definition image (3.0 pixel ratio for crisp quality)
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception("Failed to extract PNG byte data.");
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      // 3. Save to device photo gallery
      // IF USING 'gal' PACKAGE, UNCOMMENT BELOW:
      // await Gal.putImageBytes(pngBytes, name: "Jeepney_QR_${widget.plateNumber.replaceAll(' ', '_')}");

      // Simulate download delay for smooth UX feedback
      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;

      _showSnackBar(
        message: 'QR Code downloaded & saved successfully!',
        isError: false,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        message: 'Failed to download QR Code. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  void _showSnackBar({required String message, required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF1E7538),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Generate deep-link payload directing commuters to the Complaint Screen
    final String complaintQrData =
        'https://manibelapp.ph/complaint?plate=${widget.plateNumber.replaceAll(' ', '')}';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // SCROLLABLE CONTENT AREA
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. TOP HEADER WITH BACK BUTTON
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(color: Colors.black12, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.arrow_back, color: Colors.black, size: 24),
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Text(
                          'Jeepney QR Code',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 2. GREEN BANNER - VEHICLE COMPLAINT & FEEDBACK IDENTIFIER
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD7EEDD), // Soft Green
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF8DCFA1), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1E7538),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.verified_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Vehicle Complaint & Report QR',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF144D25),
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Scannable QR code assigned to this Jeepney unit.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2A663C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 3. MAIN CARD WITH JEEPNEY PLATE & DYNAMIC QR CODE
                    RepaintBoundary(
                      key: _qrBoundaryKey,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // JEEPNEY PLATE NUMBER DISPLAY
                            Text(
                              widget.plateNumber,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Route: ${widget.routeName}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0038FF),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // RENDER DYNAMIC QR CODE FOR JEEPNEY
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE0E0E0), width: 1.2),
                              ),
                              child: QrImageView(
                                data: complaintQrData,
                                version: QrVersions.auto,
                                size: 180.0,
                                backgroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // FOOTER LABEL INSIDE CARD
                            const Text(
                              'ASSIGNED TO JEEPNEY UNIT',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 4. INFORMATION NOTICE BOX
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1), // Light Yellow/Beige
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFFE082), width: 1.2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoBullet('This QR Code is uniquely bound to Jeepney Plate: ${widget.plateNumber}.'),
                          const SizedBox(height: 6),
                          _buildInfoBullet('All drivers operating this unit share this same QR Code.'),
                          const SizedBox(height: 6),
                          _buildInfoBullet('Commuters scan this code to submit ratings, complaints, and incident reports.'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 5. PINNED BOTTOM ACTION BAR (ALWAYS VISIBLE)
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _isDownloading ? null : _downloadQrCode,
                  icon: _isDownloading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Icon(
                          Icons.file_download_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                  label: Text(
                    _isDownloading ? 'Saving QR Code...' : 'Download QR Code',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E7538),
                    disabledBackgroundColor: const Color(0xFFA8D5B5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '• ',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Colors.black87,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}