import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const Starlight24App());
}

enum NecOrder { msb, lsb }

class TvPowerTest {
  final String title;
  final NecOrder order;
  final int addr1;
  final int addr2;
  final int cmd;

  const TvPowerTest(
    this.title,
    this.order,
    this.addr1,
    this.addr2,
    this.cmd,
  );

  String get addrHex =>
      "${addr1.toRadixString(16).toUpperCase().padLeft(2, '0')}${addr2.toRadixString(16).toUpperCase().padLeft(2, '0')}";

  String get cmdHex => cmd.toRadixString(16).toUpperCase().padLeft(2, '0');

  String get tag =>
      "${order == NecOrder.msb ? 'MSB' : 'LSB'} $addrHex / $cmdHex";
}

class Starlight24App extends StatelessWidget {
  const Starlight24App({super.key});

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
        child: Starlight24Screen(),
      ),
    );
  }
}

class Starlight24Screen extends StatefulWidget {
  const Starlight24Screen({super.key});

  @override
  State<Starlight24Screen> createState() => _Starlight24ScreenState();
}

class _Starlight24ScreenState extends State<Starlight24Screen>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _irChannel = MethodChannel('starlight_ir_channel');

  late final TabController _tabController;
  bool _hasIrEmitter = false;
  String _statusLabel = "جاري فحص مستشعر IR...";
  String _statusDetail = "";

  // إعدادات تبويب الكاشف الشامل (00 - FF)
  NecOrder _scanOrder = NecOrder.msb;
  int _activeAddr1 = 0x00;
  int _activeAddr2 = 0xFD;
  TvPowerTest? _lastTested;

  int _rangeIndex = 0; // 0: 00-5F, 1: 60-AF, 2: B0-FF
  final Set<int> _testedCodes = {};
  int? _lastScannedCode;

  // 36 كود تشغيل مخصّص لبوردات SL-24D2200 (TP.V56 / TP.VST59 / CV512L / CV3663)
  final List<TvPowerTest> _powerTests = const [
    // عناوين اللوحات الصينية الإضافية (MSB)
    TvPowerTest("1. لوحة 00FD-1", NecOrder.msb, 0x00, 0xFD, 0x00),
    TvPowerTest("2. لوحة 00FD-2", NecOrder.msb, 0x00, 0xFD, 0x08),
    TvPowerTest("3. لوحة 00FD-3", NecOrder.msb, 0x00, 0xFD, 0x40),
    TvPowerTest("4. لوحة 00FD-4", NecOrder.msb, 0x00, 0xFD, 0x80),
    TvPowerTest("5. لوحة 4040-1", NecOrder.msb, 0x40, 0x40, 0x00),
    TvPowerTest("6. لوحة 4040-2", NecOrder.msb, 0x40, 0x40, 0x01),
    TvPowerTest("7. لوحة 4040-3", NecOrder.msb, 0x40, 0x40, 0x10),
    TvPowerTest("8. لوحة FE01-1", NecOrder.msb, 0xFE, 0x01, 0x00),
    TvPowerTest("9. لوحة FE01-2", NecOrder.msb, 0xFE, 0x01, 0x08),
    TvPowerTest("10. لوحة FE01-3", NecOrder.msb, 0xFE, 0x01, 0x40),
    TvPowerTest("11. لوحة F708-1", NecOrder.msb, 0xF7, 0x08, 0x00),
    TvPowerTest("12. لوحة F708-2", NecOrder.msb, 0xF7, 0x08, 0x08),
    TvPowerTest("13. لوحة 10EF-1", NecOrder.msb, 0x10, 0xEF, 0x00),
    TvPowerTest("14. لوحة 10EF-2", NecOrder.msb, 0x10, 0xEF, 0x08),
    TvPowerTest("15. لوحة 10EF-3", NecOrder.msb, 0x10, 0xEF, 0x10),
    TvPowerTest("16. لوحة DF20-1", NecOrder.msb, 0xDF, 0x20, 0x00),
    TvPowerTest("17. لوحة DF20-2", NecOrder.msb, 0xDF, 0x20, 0x10),
    TvPowerTest("18. لوحة E01F-1", NecOrder.msb, 0xE0, 0x1F, 0x00),
    TvPowerTest("19. لوحة E01F-2", NecOrder.msb, 0xE0, 0x1F, 0x40),
    TvPowerTest("20. لوحة 007F-1", NecOrder.msb, 0x00, 0x7F, 0x00),
    TvPowerTest("21. لوحة 007F-2", NecOrder.msb, 0x00, 0x7F, 0x0D),

    // نفس العناوين بترتيب LSB (للبوردات المعكوسة)
    TvPowerTest("22. 00FD LSB-1", NecOrder.lsb, 0x00, 0xFD, 0x00),
    TvPowerTest("23. 00FD LSB-2", NecOrder.lsb, 0x00, 0xFD, 0x08),
    TvPowerTest("24. 00FD LSB-3", NecOrder.lsb, 0x00, 0xFD, 0x40),
    TvPowerTest("25. 4040 LSB-1", NecOrder.lsb, 0x40, 0x40, 0x00),
    TvPowerTest("26. 4040 LSB-2", NecOrder.lsb, 0x40, 0x40, 0x10),
    TvPowerTest("27. FE01 LSB-1", NecOrder.lsb, 0xFE, 0x01, 0x00),
    TvPowerTest("28. FE01 LSB-2", NecOrder.lsb, 0xFE, 0x01, 0x08),
    TvPowerTest("29. F708 LSB-1", NecOrder.lsb, 0xF7, 0x08, 0x00),
    TvPowerTest("30. F708 LSB-2", NecOrder.lsb, 0xF7, 0x08, 0x08),
    TvPowerTest("31. 10EF LSB-1", NecOrder.lsb, 0x10, 0xEF, 0x00),
    TvPowerTest("32. 10EF LSB-2", NecOrder.lsb, 0x10, 0xEF, 0x10),
    TvPowerTest("33. DF20 LSB", NecOrder.lsb, 0xDF, 0x20, 0x10),
    TvPowerTest("34. E01F LSB", NecOrder.lsb, 0xE0, 0x1F, 0x40),
    TvPowerTest("35. CV512 1", NecOrder.lsb, 0x00, 0xFF, 0x48),
    TvPowerTest("36. CV512 2", NecOrder.lsb, 0x00, 0xBF, 0x40),
  ];

  final List<List<int>> _scanAddresses = const [
    [0x00, 0xFD],
    [0x40, 0x40],
    [0xFE, 0x01],
    [0xF7, 0x08],
    [0x10, 0xEF],
    [0xDF, 0x20],
    [0xE0, 0x1F],
    [0x00, 0x7F],
    [0x00, 0xBF],
    [0x00, 0xFF],
    [0x40, 0xBF],
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
            ? "جاهز - وجّه الهاتف نحو تلفاز SL-24D2200"
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

  List<int> _buildNecSignal(NecOrder order, int a1, int a2, int cmd) {
    final int inv = (~cmd) & 0xFF;
    final List<int> bytes = [a1 & 0xFF, a2 & 0xFF, cmd & 0xFF, inv];
    final List<int> f = [9000, 4500];

    for (final int b in bytes) {
      if (order == NecOrder.msb) {
        for (int i = 7; i >= 0; i--) {
          f.add(560);
          f.add(((b >> i) & 1) == 1 ? 1690 : 560);
        }
      } else {
        for (int i = 0; i < 8; i++) {
          f.add(560);
          f.add(((b >> i) & 1) == 1 ? 1690 : 560);
        }
      }
    }
    f.add(560);
    return [...f, 40000, 9000, 2250, 560];
  }

  Future<void> _sendPowerTest(TvPowerTest item) async {
    HapticFeedback.mediumImpact();
    if (!_hasIrEmitter) return;

    try {
      await _irChannel.invokeMethod('transmit', {
        'pattern': _buildNecSignal(item.order, item.addr1, item.addr2, item.cmd),
        'frequency': 38000,
      });
      setState(() {
        _lastTested = item;
        _statusLabel = item.title;
        _statusDetail = item.tag;
      });
    } catch (e) {
      setState(() {
        _statusLabel = "فشل الإرسال";
        _statusDetail = "";
      });
    }
  }

  void _lockAndScan(TvPowerTest item) {
    setState(() {
      _scanOrder = item.order;
      _activeAddr1 = item.addr1;
      _activeAddr2 = item.addr2;
      _testedCodes.clear();
      _lastScannedCode = null;
      _statusLabel = "تم اعتماد العنوان للفحص";
      _statusDetail = item.tag;
    });
    _tabController.animateTo(1);
  }

  Future<void> _sendScanCode(int cmd) async {
    HapticFeedback.mediumImpact();
    if (!_hasIrEmitter) return;

    final String addrHex =
        "${_activeAddr1.toRadixString(16).toUpperCase().padLeft(2, '0')}${_activeAddr2.toRadixString(16).toUpperCase().padLeft(2, '0')}";
    final String cmdHex = cmd.toRadixString(16).toUpperCase().padLeft(2, '0');

    try {
      await _irChannel.invokeMethod('transmit', {
        'pattern': _buildNecSignal(_scanOrder, _activeAddr1, _activeAddr2, cmd),
        'frequency': 38000,
      });
      setState(() {
        _testedCodes.add(cmd);
        _lastScannedCode = cmd;
        _statusLabel =
            "فحص ${_scanOrder == NecOrder.msb ? 'MSB' : 'LSB'} 0x$addrHex";
        _statusDetail = "CMD: 0x$cmdHex";
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
      padding: const EdgeInsets.all(10.0),
      child: Column(
        children: [
          const Text(
            "جرّب الأزرار من 1 إلى 36 نحو التلفاز؛ أول زر يطفئ أو يشغّل الشاشة اضغط الزر الأخضر أسفله:",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.35,
              ),
              itemCount: _powerTests.length,
              itemBuilder: (context, index) {
                final item = _powerTests[index];
                final isLast = _lastTested == item;
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isLast ? Colors.red.shade700 : const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          item.tag,
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
          if (_lastTested != null) ...[
            const SizedBox(height: 8),
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
                onPressed: () => _lockAndScan(_lastTested!),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                  "استجاب لـ (${_lastTested!.title})؟ افحص بقية الأزرار",
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
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text("NEC MSB")),
                  selected: _scanOrder == NecOrder.msb,
                  selectedColor: Colors.teal.shade700,
                  onSelected: (_) => setState(() {
                    _scanOrder = NecOrder.msb;
                    _testedCodes.clear();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text("NEC LSB")),
                  selected: _scanOrder == NecOrder.lsb,
                  selectedColor: Colors.teal.shade700,
                  onSelected: (_) => setState(() {
                    _scanOrder = NecOrder.lsb;
                    _testedCodes.clear();
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _scanAddresses.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final pair = _scanAddresses[index];
                final hex =
                    "${pair[0].toRadixString(16).toUpperCase().padLeft(2, '0')}${pair[1].toRadixString(16).toUpperCase().padLeft(2, '0')}";
                final selected =
                    _activeAddr1 == pair[0] && _activeAddr2 == pair[1];
                return ChoiceChip(
                  label: Text(hex, style: const TextStyle(fontSize: 11)),
                  selected: selected,
                  selectedColor: Colors.indigo.shade700,
                  onSelected: (_) => setState(() {
                    _activeAddr1 = pair[0];
                    _activeAddr2 = pair[1];
                    _testedCodes.clear();
                  }),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rangeIndex == 0
                        ? Colors.teal.shade700
                        : const Color(0xFF1E293B),
                  ),
                  onPressed: () => setState(() => _rangeIndex = 0),
                  child: const Text("00 - 5F", style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rangeIndex == 1
                        ? Colors.teal.shade700
                        : const Color(0xFF1E293B),
                  ),
                  onPressed: () => setState(() => _rangeIndex = 1),
                  child: const Text("60 - AF", style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rangeIndex == 2
                        ? Colors.teal.shade700
                        : const Color(0xFF1E293B),
                  ),
                  onPressed: () => setState(() => _rangeIndex = 2),
                  child: const Text("B0 - FF", style: TextStyle(fontSize: 12)),
                ),
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
                childAspectRatio: 1.75,
              ),
              itemCount: count,
              itemBuilder: (context, index) {
                final int code = start + index;
                final String hex =
                    code.toRadixString(16).toUpperCase().padLeft(2, '0');
                final bool tested = _testedCodes.contains(code);
                final bool isLast = _lastScannedCode == code;

                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tested
                        ? Colors.deepPurple.shade400
                        : Colors.indigo.shade700,
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
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
          "Starlight SL-24D2200",
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
            Tab(text: "1. كاشف SL-24D2200"),
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
                          fontSize: 12,
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
