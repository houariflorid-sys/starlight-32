import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const StarlightD2200App());
}

class NecCodeItem {
  final String title;
  final int code32;
  const NecCodeItem(this.title, this.code32);

  String get hex => code32.toRadixString(16).toUpperCase().padLeft(8, '0');
  int get prefix16 => (code32 >> 16) & 0xFFFF;
}

class StarlightD2200App extends StatelessWidget {
  const StarlightD2200App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Starlight SL-24D2200',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B1120),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: StarlightD2200Screen(),
      ),
    );
  }
}

class StarlightD2200Screen extends StatefulWidget {
  const StarlightD2200Screen({super.key});

  @override
  State<StarlightD2200Screen> createState() => _StarlightD2200ScreenState();
}

class _StarlightD2200ScreenState extends State<StarlightD2200Screen>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _irChannel = MethodChannel('starlight_ir_channel');

  late final TabController _tabController;
  bool _hasIrEmitter = false;
  String _statusLabel = "جاري فحص مستشعر IR...";
  String _statusDetail = "";

  // الفحص التلقائي
  Timer? _autoTimer;
  bool _isAutoScanning = false;
  int _autoIndex = 0;

  // العنوان المعتمد في تبويب كاشف الأزرار
  int _activePrefix16 = 0x807F;
  NecCodeItem? _lastTestedPower;
  int _rangeIndex = 0;
  final Set<int> _testedCodes = {};
  int? _lastScannedCode;

  // 36 كود تشغيل مخصصة للوحات Starlight SL-24D2200 الصينية
  final List<NecCodeItem> _d2200PowerCodes = const [
    NecCodeItem("1. 807F-A", 0x807F00FF),
    NecCodeItem("2. 807F-B", 0x807F02FD),
    NecCodeItem("3. 807F-C", 0x807F12ED),
    NecCodeItem("4. 807F-D", 0x807F10EF),
    NecCodeItem("5. 807F-E", 0x807F807F),
    NecCodeItem("6. 807F-F", 0x807F48B7),
    NecCodeItem("7. 807F-G", 0x807F0DF2),
    NecCodeItem("8. 807F-H", 0x807F01FE),
    NecCodeItem("9. FF00-A", 0xFF0000FF),
    NecCodeItem("10. FF00-B", 0xFF0008F7),
    NecCodeItem("11. FF00-C", 0xFF000DF2),
    NecCodeItem("12. FF00-D", 0xFF0040BF),
    NecCodeItem("13. FE01-A", 0xFE0100FF),
    NecCodeItem("14. FE01-B", 0xFE0140BF),
    NecCodeItem("15. FE01-C", 0xFE0108F7),
    NecCodeItem("16. FD02-A", 0xFD0248B7),
    NecCodeItem("17. FD02-B", 0xFD0201FE),
    NecCodeItem("18. FB04-A", 0xFB0408F7),
    NecCodeItem("19. F708-A", 0xF70808F7),
    NecCodeItem("20. EF10-A", 0xEF1000FF),
    NecCodeItem("21. DF20-A", 0xDF2010EF),
    NecCodeItem("22. DF20-B", 0xDF2048B7),
    NecCodeItem("23. BF40-A", 0xBF4012ED),
    NecCodeItem("24. 007F-A", 0x007F08F7),
    NecCodeItem("25. 007F-B", 0x007F40BF),
    NecCodeItem("26. 007F-C", 0x007F10EF),
    NecCodeItem("27. 007F-D", 0x007F12ED),
    NecCodeItem("28. 4040-A", 0x404000FF),
    NecCodeItem
