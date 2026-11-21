import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const StarlightRemoteApp());
}

class IrTestItem {
  final String title;
  final int addr1;
  final int addr2;
  final int cmd;
  final bool isSamsung;

  const IrTestItem(
    this.title,
    this.addr1,
    this.addr2,
    this.cmd, {
    this.isSamsung = false,
  });

  String get addrHex =>
      "${addr1.toRadixString(16).toUpperCase().padLeft(2, '0')}${addr2.toRadixString(16).toUpperCase().padLeft(2, '0')}";

  String get cmdHex =>
      cmd.toRadixString(16).toUpperCase().padLeft(2, '0');
}

class StarlightRemoteApp extends StatelessWidget {
  const StarlightRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Starlight 32 Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B1120),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: StarlightFinderScreen(),
      ),
    );
  }
}

class StarlightFinderScreen extends StatefulWidget {
  const StarlightFinderScreen({super.key});

  @override
  State<StarlightFinderScreen> createState() => _StarlightFinderScreenState();
}

class _StarlightFinderScreenState extends State<StarlightFinderScreen>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _irChannel = MethodChannel('starlight_ir_channel');

  late final TabController _tabController;
  bool _hasIrEmitter = false;
  String _statusLabel = "جاري فحص مستشعر IR...";
  String _statusDetail = "";

  // العنوان المعتمد حالياً في تبويب كاشف الأكواد
  int _activeAddr1 = 0x00;
  int _activeAddr2 = 0xBF;
  bool _activeIsSamsung = false;
  IrTestItem? _lastTestedPower;

  int _rangeIndex = 0; // 0: 00-5F, 1: 60-AF, 2: B0-FF
  final Set<int> _testedCodes = {};
  int? _lastScannedCode;

  // أشهر 24 كود تشغيل (POWER) لبوردات تلفزيون ستارلايت 32 بوصة
  final List<IrTestItem> _starlightPowerTests = const [
    IrTestItem("ستارلايت 1", 0x00, 0xBF, 0x0D),
    IrTestItem("ستارلايت 2", 0x00, 0xBF, 0x00),
    IrTestItem("ستارلايت 3", 0x00, 0xBF, 0x01),
    IrTestItem("ستارلايت 4", 0x00, 0xBF, 0x10),
    IrTestItem("ستارلايت 5", 0x00, 0xFF, 0x08),
    IrTestItem("ستارلايت 6", 0x00, 0xFF, 0x01),
    IrTestItem("ستارلايت 7", 0x00, 0xFF, 0x0D),
    IrTestItem("ستارلايت 8", 0x00, 0xFF, 0x40),
    IrTestItem("ستارلايت 9", 0x00, 0xFF, 0x10),
    IrTestItem("ستارلايت 10", 0x40, 0xBF, 0x12),
    IrTestItem("ستارلايت 11", 0x40, 0xBF, 0x01),
    IrTestItem("ستارلايت 12", 0x04, 0xFB, 0x08),
    IrTestItem("ستارلايت 13", 0x08, 0xF7, 0x08),
    IrTestItem("ستارلايت 14", 0x08, 0xF7, 0x00),
    IrTestItem("ستارلايت 15", 0x02, 0xFD, 0x01),
    IrTestItem("ستارلايت 16", 0x02, 0xFD, 0x40),
    IrTestItem("ستارلايت 17", 0xBD, 0x02, 0x01),
    IrTestItem("ستارلايت 18", 0xBF, 0x00, 0x0D),
    IrTestItem("ستارلايت 19", 0x7F, 0x80, 0x01),
    IrTestItem("ستارلايت 20", 0x80, 0x7F, 0x01),
    IrTestItem("ستارلايت 21", 0x20, 0xDF, 0x10),
    IrTestItem("ستارلايت 22", 0x20, 0xDF, 0x48),
    IrTestItem("ستارلايت 23", 0x01, 0xFE, 0x00),
    IrTestItem("ستارلايت 24", 0x07, 0x07, 0x02, isSamsung: true),
  ];

  // قائمة العناوين السريعة للتبديل اليدوي داخل الكاشف
  final List<List<int>> _commonAddresses = const [
    [0x00, 0xBF],
    [0x00, 0xFF],
    [0x40, 0xBF],
    [0x04, 0xFB],
    [0x08, 0xF7],
    [0x02, 0xFD],
    [0xBD, 0x02],
    [0xBF, 0x00],
    [0x7F, 0x80],
    [0x80, 0x7F],
    [0x20, 0xDF],
    [0x01, 0xFE],
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkIrSensor();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkIrSensor() async {
    try {
      final bool hasIr = await _irChannel.invokeMethod('hasIrEmitter');
      setState(() {
        _hasIrEmitter = hasIr;
        _statusLabel = hasIr
            ? "جاهز - وجّه الهاتف نحو تلفاز ستارلايت 32\""
            : "مستشعر IR غير متاح";
        _statusDetail = "";
      });
    } catch (e) {
      setState(() {
        _statusLabel = "خطأ في المستشعر";
        _statusDetail = "";
      });
    }
  }

  List<int> _buildSignal(int addr1, int addr2, int cmd, {bool isSamsung = false}) {
    final List<int> f = isSamsung ? [4500, 4500] : [9000, 4500];
    for (int i = 0; i < 8; i++) {
      f.add(560);
      f.add(((addr1 >> i) & 1) == 1 ? 1690 : 560);
    }
    for (int i = 0; i < 8; i++) {
      f.add(560);
      f.add(((addr2 >> i) & 1) == 1 ? 1690 : 560);
    }
    final int inv = (~cmd) & 0xFF;
    for (int i = 0; i < 8; i++) {
      f.add(560);
      f.add(((cmd >> i) & 1) == 1 ? 1690 : 560);
    }
    for (int i = 0; i < 8; i++) {
      f.add(560);
      f.add(((inv >> i) & 1) == 1 ? 1690 : 560);
    }
    f.add(560);
    if (isSamsung) return f;
    return [...f, 40000, 9000, 2250, 560];
  }

  String get _activeAddrHex =>
      "${_activeAddr1.toRadixString(16).toUpperCase().padLeft(2, '0')}${_activeAddr2.toRadixString(16).toUpperCase().padLeft(2, '0')}";

  Future<void> _sendPowerTest(IrTestItem item) async {
    HapticFeedback.mediumImpact();
    if (!_hasIrEmitter) return;

    try {
      await _irChannel.invokeMethod('transmit', {
        'pattern': _buildSignal(
          item.addr1,
          item.addr2,
          item.cmd,
          isSamsung: item.isSamsung,
        ),
        'frequency': 38000,
      });
      setState(() {
        _lastTestedPower = item;
        _statusLabel = item.title;
        _statusDetail = "ADDR: 0x${item.addrHex}  |  CMD: 0x${item.cmdHex}";
      });
    } catch (e) {
      setState(() {
        _statusLabel = "فشل الإرسال";
        _statusDetail = "";
      });
    }
  }

  void _lockAddressAndScan(IrTestItem item) {
    setState(() {
      _activeAddr1 = item.addr1;
      _activeAddr2 = item.addr2;
      _activeIsSamsung = item.isSamsung;
      _testedCodes.clear();
      _lastScannedCode = null;
      _statusLabel = "تم اعتماد العنوان";
      _statusDetail = "0x${item.addrHex}";
    });
    _tabController.animateTo(1);
  }

  Future<void> _sendScanCode(int cmd) async {
    HapticFeedback.mediumImpact();
    if (!_hasIrEmitter) return;

    final String cmdHex = cmd.toRadixString(16).toUpperCase().padLeft(2, '0');
    try {
      await _irChannel.invokeMethod('transmit', {
        'pattern': _buildSignal(
          _activeAddr1,
          _activeAddr2,
          cmd,
          isSamsung: _activeIsSamsung,
        ),
        'frequency': 38000,
      });
      setState(() {
        _testedCodes.add(cmd);
        _lastScannedCode = cmd;
        _statusLabel = "فحص 0x$_activeAddrHex";
        _statusDetail = "0x$cmdHex";
      });
    } catch (e) {
      setState(() {
        _statusLabel = "فشل الإرسال";
        _statusDetail = "";
      });
    }
  }

  Widget _buildQuickPowerTab() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          const Text(
            "جرّب الأزرار بالترتيب نحو التلفاز؛ أول زر يطفئ أو يشغّل الشاشة سجّل اسمه واضغط الزر الأخضر بالأسفل:",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.45,
              ),
              itemCount: _starlightPowerTests.length,
              itemBuilder: (context, index) {
                final item = _starlightPowerTests[index];
                final isLast = _lastTestedPower == item;
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isLast ? Colors.red.shade700 : const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    side: isLast
                        ? const BorderSide(color: Colors.amberAccent, width: 2)
                        : BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => _sendPowerTest(item),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          "${item.addrHex} / ${item.cmdHex}",
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.tealAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_lastTestedPower != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _lockAddressAndScan(_lastTestedPower!),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                  "استجاب التلفاز لـ (${_lastTestedPower!.title})؟ افحص بقية الأزرار",
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFullScannerTab() {
    final int start = _rangeIndex == 0 ? 0x00 : (_rangeIndex == 1 ? 0x60 : 0xB0);
    final int count = _rangeIndex == 0 ? 96 : 80;

    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        children: [
          // شريط اختيار العنوان
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _commonAddresses.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final pair = _commonAddresses[index];
                final hex =
                    "${pair[0].toRadixString(16).toUpperCase().padLeft(2, '0')}${pair[1].toRadixString(16).toUpperCase().padLeft(2, '0')}";
                final selected =
                    !_activeIsSamsung && _activeAddr1 == pair[0] && _activeAddr2 == pair[1];
                return ChoiceChip(
                  label: Text(hex, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  selected: selected,
                  selectedColor: Colors.teal.shade700,
                  onSelected: (_) {
                    setState(() {
                      _activeAddr1 = pair[0];
                      _activeAddr2 = pair[1];
                      _activeIsSamsung = false;
                      _testedCodes.clear();
                      _lastScannedCode = null;
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _rangeIndex == 0 ? Colors.teal.shade700 : const Color(0xFF1E293B),
                  ),
                  onPressed: () => setState(() => _rangeIndex = 0),
                  child: const Text("00 - 5F", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _rangeIndex == 1 ? Colors.teal.shade700 : const Color(0xFF1E293B),
                  ),
                  onPressed: () => setState(() => _rangeIndex = 1),
                  child: const Text("60 - AF", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _rangeIndex == 2 ? Colors.teal.shade700 : const Color(0xFF1E293B),
                  ),
                  onPressed: () => setState(() => _rangeIndex = 2),
                  child: const Text("B0 - FF", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: "تصفير الألوان",
                style: IconButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
                onPressed: () => setState(() {
                  _testedCodes.clear();
                  _lastScannedCode = null;
                }),
                icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.7,
              ),
              itemCount: count,
              itemBuilder: (context, index) {
                final int code = start + index;
                final String hex = code.toRadixString(16).toUpperCase().padLeft(2, '0');
                final bool tested = _testedCodes.contains(code);
                final bool isLast = _lastScannedCode == code;

                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        tested ? Colors.deepPurple.shade400 : Colors.indigo.shade700,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    side: isLast
                        ? const BorderSide(color: Colors.amberAccent, width: 2)
                        : BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _sendScanCode(code),
                  child: Text(
                    hex,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Starlight 32 Remote",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E293B),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.tealAccent,
          labelColor: Colors.tealAccent,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: "1. كاشف ستارلايت"),
            Tab(text: "2. كاشف الأزرار"),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF132A2E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.tealAccent),
              ),
              child: Column(
                children: [
                  Text(
                    _statusLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.tealAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_statusDetail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        _statusDetail,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildQuickPowerTab(),
                  _buildFullScannerTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
