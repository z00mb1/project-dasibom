import 'package:flutter/material.dart';
import 'report_form_tab.dart';
import 'report_status_tab.dart';

class ReportPage extends StatefulWidget {
  final int initialTabIndex;

  const ReportPage({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _statusTabKey = GlobalKey<ReportStatusTabState>();

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );

    _tabController.addListener(() {
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        _statusTabKey.currentState?.refresh();
      }
    });

    if (widget.initialTabIndex == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _statusTabKey.currentState?.refresh();
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
          child: Image.asset("assets/images/dasibom_logo.png", height: 35,
            errorBuilder: (context, error, stackTrace) => const Text("다시봄", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.black,
          indicatorWeight: 2,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey.shade400,
          labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: "실종 신고"),
            Tab(text: "신고 현황"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ReportFormTab(
            onSuccess: () {
              _tabController.animateTo(1);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _statusTabKey.currentState?.refresh();
              });
            },
          ),
          ReportStatusTab(key: _statusTabKey),
        ],
      ),
    );
  }
}