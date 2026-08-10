import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_assets.dart';
import '../screens/driver_menu_drawer.dart';
import 'daily_operations_screen.dart';
import 'driver_notification_screen.dart';
import 'start_trip.dart'; // Connected Start Trip Screen

class DriverDashboardScreen extends StatefulWidget {
  final String driverName;
  final String driverId;
  final String plateNumber;
  final String routeName;

  const DriverDashboardScreen({
    super.key,
    required this.driverName,
    required this.driverId,
    this.plateNumber = 'ABC 1234',
    this.routeName = 'Quiapo - Pasig',
  });

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _selectedStatus = 'Offline';

  // Dynamic metrics state
  int _todaysTrips = 12;
  double _todaysEarnings = 1250.0;
  bool _hasUnreadNotification = true;

  /// Determines dynamic greeting based on current time of day
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning,';
    } else if (hour < 17) {
      return 'Good afternoon,';
    } else {
      return 'Good evening,';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8F9FA),

      // Custom Drawer with Dynamic Plate Number and Route Name
      drawer: DriverMenuDrawer(
        driverName: widget.driverName,
        driverId: widget.driverId,
        plateNumber: widget.plateNumber,
        routeName: widget.routeName,
      ),

      body: SafeArea(
        child: Column(
          children: [
            // 1. TOP NAVBAR HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu_rounded, size: 30, color: Colors.black87),
                    onPressed: () {
                      _scaffoldKey.currentState?.openDrawer();
                    },
                  ),

                  // Center Logo
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        AppAssets.jeepneyLogo,
                        width: 64,
                        height: 64,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.directions_bus_filled_rounded,
                          size: 48,
                          color: AppColors.logoBlue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                          children: [
                            TextSpan(
                              text: 'Manibel',
                              style: TextStyle(color: AppColors.logoBlue),
                            ),
                            TextSpan(
                              text: 'App',
                              style: TextStyle(color: AppColors.logoRed),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Dynamic Notification Bell Icon
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_none_rounded, size: 28, color: Colors.black87),
                        onPressed: () async {
                          setState(() {
                            _hasUnreadNotification = false;
                          });

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NotificationsScreen(driverId: widget.driverId),
                            ),
                          );
                        },
                      ),
                      if (_hasUnreadNotification)
                        Positioned(
                          right: 12,
                          top: 12,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE23F3F),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // 2. DASHBOARD CONTENT LIST
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8.0),
                child: Column(
                  children: [
                    // PROFILE GREETING CARD
                    _buildCardWrapper(
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 28,
                            backgroundColor: Color(0xFFD9D9D9),
                            child: Icon(Icons.person, size: 36, color: Colors.black38),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _getGreeting(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black54,
                                  ),
                                ),
                                Text(
                                  widget.driverName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Driver ID: ${widget.driverId}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.logoBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Status Badge Dropdown
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _selectedStatus == 'Online'
                                  ? const Color(0xFFE8F5E9)
                                  : const Color(0xFFFADBD8),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _selectedStatus == 'Online'
                                    ? Colors.green
                                    : const Color(0xFFE6B0AA),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedStatus,
                                isDense: true,
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                                items: <String>['Offline', 'Online'].map((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: value == 'Online' ? Colors.green : Colors.red,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          value,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: value == 'Online'
                                                ? Colors.green[800]
                                                : Colors.red[800],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (newValue) {
                                  if (newValue != null) {
                                    setState(() {
                                      _selectedStatus = newValue;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // LIVE LOCATION TRACKING MAP PREVIEW
                    _buildCardWrapper(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Live Location Tracking',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black,
                                ),
                              ),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.green,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'Live',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              height: 180,
                              width: double.infinity,
                              child: Stack(
                                children: [
                                  Container(
                                    color: const Color(0xFFE5E9EE),
                                    child: const Center(
                                      child: Icon(
                                        Icons.map_outlined,
                                        size: 60,
                                        color: Colors.black26,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 10,
                                    bottom: 10,
                                    child: Column(
                                      children: [
                                        _buildMapCircleBtn(Icons.my_location_rounded),
                                        const SizedBox(height: 8),
                                        _buildMapCircleBtn(Icons.layers_rounded),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // SUMMARY STATS (TODAY'S TRIPS & EARNINGS)
                    _buildCardWrapper(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                _buildStatIcon(
                                  icon: Icons.directions_bus_rounded,
                                  bgColor: const Color(0xFF2E5AAC),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Today's Trips",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          '$_todaysTrips',
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'Trips',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black45,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          Container(
                            height: 36,
                            width: 1,
                            color: Colors.black12,
                          ),

                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 14.0),
                              child: Row(
                                children: [
                                  _buildStatIcon(
                                    icon: Icons.payments_rounded,
                                    bgColor: const Color(0xFFE5A800),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Earnings',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.baseline,
                                        textBaseline: TextBaseline.alphabetic,
                                        children: [
                                          Text(
                                            '₱${_todaysEarnings.toStringAsFixed(0)}',
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Text(
                                            'Today',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black45,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // DAILY OPERATIONS DASHBOARD CARD
                    _buildCardWrapper(
                      onTap: () async {
                        final dynamic result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DailyOperationsScreen(),
                          ),
                        );

                        if (!mounted) return;

                        if (result != null && result is Map) {
                          setState(() {
                            if (result.containsKey('earnings')) {
                              _todaysEarnings = (result['earnings'] as num).toDouble();
                            }
                          });
                        }
                      },
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.local_gas_station_rounded,
                              size: 30,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Daily Operations Dashboard',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Check if your revenue is higher than your gas expense',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 20,
                            color: Color(0xFF2E5AAC),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // LIVE TRIP MAP CARD
                    _buildCardWrapper(
                      onTap: () {},
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3F2FD),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.pin_drop_rounded,
                              size: 30,
                              color: Color(0xFF0288D1),
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Live Trip Map',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Enables real-time GPS tracking of vehicles, allowing users to view the current location.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 20,
                            color: Color(0xFF2E5AAC),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // CENTERED FLOATING START TRIP BUTTON
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: RawMaterialButton(
          onPressed: () async {
            // 1. Instantly set status to Online
            setState(() {
              _selectedStatus = 'Online';
            });

            // 2. Open StartTripScreen & wait until driver ends trip
            final dynamic result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StartTripScreen(
                  driverName: widget.driverName,
                  driverId: widget.driverId,
                  plateNumber: widget.plateNumber,
                  routeName: widget.routeName,
                ),
              ),
            );

            if (!mounted) return;

            // 3. Set status back based on return data (e.g. back to Offline when End Trip is tapped)
            if (result != null && result is Map && result.containsKey('status')) {
              setState(() {
                _selectedStatus = result['status'] as String;
              });
            }
          },
          shape: const CircleBorder(),
          elevation: 0,
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.directions_bus_filled_rounded,
                size: 32,
                color: Color(0xFF2E5AAC),
              ),
              SizedBox(height: 2),
              Text(
                'Start Trip',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardWrapper({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildStatIcon({required IconData icon, required Color bgColor}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  Widget _buildMapCircleBtn(IconData icon) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 4,
          ),
        ],
      ),
      child: Icon(icon, size: 18, color: Colors.black87),
    );
  }
}