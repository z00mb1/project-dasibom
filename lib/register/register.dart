import 'package:flutter/material.dart';

import 'register_form_tab.dart';
import 'register_status_tab.dart';

class RegisterPage extends StatefulWidget {
  final int initialTabIndex;

  const RegisterPage({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  late int _selectedTabIndex;

  final GlobalKey<RegisterStatusTabState> _statusTabKey =
      GlobalKey<RegisterStatusTabState>();

  @override
  void initState() {
    super.initState();
    _selectedTabIndex = widget.initialTabIndex;

    if (_selectedTabIndex == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _statusTabKey.currentState?.refresh();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFEF9),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildCustomTabBar(),
            Expanded(
              child: _selectedTabIndex == 0
                  ? RegisterFormTab(
                      onSuccess: () {
                        setState(() {
                          _selectedTabIndex = 1;
                        });

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _statusTabKey.currentState?.refresh();
                        });
                      },
                    )
                  : RegisterStatusTab(
                      key: _statusTabKey,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.arrow_back_ios_new,
              size: 28,
              color: Colors.black,
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
            child: Image.asset(
              'assets/images/dasibom_logo.png',
              height: 40,
              errorBuilder: (_, __, ___) => const Text(
                '다시봄',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 28),
        ],
      ),
    );
  }

  Widget _buildCustomTabBar() {
    return Row(
      children: [
        _buildTabItem(title: '인적사항 작성', index: 0),
        _buildTabItem(title: '등록 현황', index: 1),
      ],
    );
  }

  Widget _buildTabItem({
    required String title,
    required int index,
  }) {
    final bool isActive = _selectedTabIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTabIndex = index;
          });

          if (index == 1) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _statusTabKey.currentState?.refresh();
            });
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? Colors.black87 : Colors.grey.shade300,
                width: isActive ? 2.0 : 1.0,
              ),
            ),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? Colors.black87 : Colors.grey.shade400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}