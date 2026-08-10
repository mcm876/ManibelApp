import 'package:flutter/material.dart';

class PassengerWaitPoint {
  final String locationName;
  final int count;
  final String direction; // 'To Quiapo' or 'To Pasig'
  final Alignment mapAlignment; // Relative position on the map layout

  PassengerWaitPoint({
    required this.locationName,
    required this.count,
    required this.direction,
    required this.mapAlignment,
  });
}

class StartTripScreen extends StatefulWidget {
  final String driverName;
  final String driverId;
  final String plateNumber;
  final String routeName;

  const StartTripScreen({
    super.key,
    required this.driverName,
    required this.driverId,
    required this.plateNumber,
    this.routeName = 'Quiapo - Pasig',
  });

  @override
  State<StartTripScreen> createState() => _StartTripScreenState();
}

class _StartTripScreenState extends State<StartTripScreen> {
  // Current travel direction toggle: 'To Quiapo' or 'To Pasig'
  String _selectedDirection = 'To Quiapo';

  // Mock passenger wait points along Pasig - Quiapo route
  final List<PassengerWaitPoint> _allWaitPoints = [
    PassengerWaitPoint(
      locationName: 'F. Manalo St. Corner',
      count: 1,
      direction: 'To Quiapo',
      mapAlignment: const Alignment(-0.5, -0.2),
    ),
    PassengerWaitPoint(
      locationName: 'Bagong Ilog Intersection',
      count: 2,
      direction: 'To Quiapo',
      mapAlignment: const Alignment(-0.1, -0.65),
    ),
    PassengerWaitPoint(
      locationName: 'Market Ave Terminal',
      count: 3,
      direction: 'To Quiapo',
      mapAlignment: const Alignment(0.3, -0.6),
    ),
    PassengerWaitPoint(
      locationName: 'Pasig Mega Market',
      count: 5,
      direction: 'To Quiapo',
      mapAlignment: const Alignment(-0.25, 0.3),
    ),
    PassengerWaitPoint(
      locationName: 'Caruncho Ave Stop',
      count: 4,
      direction: 'To Pasig',
      mapAlignment: const Alignment(0.4, 0.1),
    ),
    PassengerWaitPoint(
      locationName: 'San Agustin St.',
      count: 2,
      direction: 'To Pasig',
      mapAlignment: const Alignment(0.6, 0.65),
    ),
  ];

  /// Filter waiting passengers based on selected direction
  List<PassengerWaitPoint> get _filteredWaitPoints {
    return _allWaitPoints
        .where((point) => point.direction == _selectedDirection)
        .toList();
  }

  /// Calculates total passengers currently waiting for the chosen direction
  int get _totalWaitingPassengers {
    return _filteredWaitPoints.fold(0, (sum, item) => sum + item.count);
  }

  /// Handles "End Trip" action and passes state back to Dashboard
  Future<void> _handleEndTrip() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'End Trip',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'Are you sure you want to end this trip? Your status will be set to Offline.',
            style: TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD62828),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('End Trip', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      // Returns 'status': 'Offline' to the dashboard screen
      Navigator.pop(context, {
        'status': 'Offline',
        'completedTrip': true,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      body: Stack(
        children: [
          // 1. MOCK MAP BACKGROUND & ROAD LAYOUT
          _buildMapBackground(),

          // 2. DYNAMIC PASSENGER WAIT BADGES ON MAP
          ..._filteredWaitPoints.map((point) => _buildPassengerBadge(point)),

          // 3. TOP FLOATING HEADER CARD
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // Circular Back Button
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.arrow_back, color: Colors.black, size: 24),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Floating Title Card
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Live Trip Map',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black,
                                ),
                              ),
                              Text(
                                widget.driverName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 4. ROUTE DIRECTION TOGGLE SELECTOR
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildDirectionChip(
                            label: 'Bound for Quiapo',
                            value: 'To Quiapo',
                          ),
                        ),
                        Expanded(
                          child: _buildDirectionChip(
                            label: 'Bound for Pasig',
                            value: 'To Pasig',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 5. PASSENGER SUMMARY COUNTER CARD
          Positioned(
            left: 16,
            right: 16,
            bottom: 110,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8F5E9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.people_alt_rounded, color: Color(0xFF2E7D32), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_totalWaitingPassengers Passengers Waiting',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          'Along $_selectedDirection route',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // 6. CIRCULAR END TRIP FLOATING BUTTON
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: RawMaterialButton(
          onPressed: _handleEndTrip,
          shape: const CircleBorder(),
          elevation: 0,
          fillColor: const Color(0xFFD62828),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.stop_circle_rounded,
                size: 32,
                color: Colors.white,
              ),
              SizedBox(height: 2),
              Text(
                'End Trip',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Toggle button helper for route direction filtering
  Widget _buildDirectionChip({required String label, required String value}) {
    final bool isSelected = _selectedDirection == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDirection = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0038FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : Colors.black54,
          ),
        ),
      ),
    );
  }

  /// Builds green numbered circular badges representing passenger counts on the map
  Widget _buildPassengerBadge(PassengerWaitPoint point) {
    return Align(
      alignment: point.mapAlignment,
      child: GestureDetector(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${point.count} passenger(s) waiting at ${point.locationName}'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D32),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              '${point.count}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Map background graphics imitating street map layout
  Widget _buildMapBackground() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFFE3E8EE),
      child: CustomPaint(
        painter: MapRoadPainter(),
      ),
    );
  }
}

/// Custom painter to draw road lines & map aesthetics matching Pasig map area
class MapRoadPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final secondaryRoadPaint = Paint()
      ..color = const Color(0xFFF0F3F7)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;

    final marketAreaPaint = Paint()
      ..color = const Color(0xFFFFF3E0)
      ..style = PaintingStyle.fill;

    // Draw Pasig Mega Market area block
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.35, size.height * 0.52, size.width * 0.5, size.height * 0.22),
      marketAreaPaint,
    );

    // Main Avenue Path (F. Manalo / Caruncho)
    final path1 = Path()
      ..moveTo(size.width * 0.25, 0)
      ..lineTo(size.width * 0.2, size.height * 0.4)
      ..lineTo(size.width * 0.85, size.height * 0.65)
      ..lineTo(size.width * 0.75, size.height);

    // Secondary connecting streets
    final path2 = Path()
      ..moveTo(0, size.height * 0.25)
      ..lineTo(size.width, size.height * 0.2)
      ..moveTo(0, size.height * 0.45)
      ..lineTo(size.width * 0.8, size.height * 0.42);

    canvas.drawPath(path2, secondaryRoadPaint);
    canvas.drawPath(path1, roadPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}