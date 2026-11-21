import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const StarlightRemoteApp());
}

enum IrProtocol { necMsb, rc5, rca, samsung, sony }

class IrTestItem {
  final String title;
  final IrProtocol protocol;
  final int value1; // NEC/Samsung: 32-bit code | RC5/RCA/Sony: address
  final int value2; // RC5/RCA/Sony: command

  const IrTestItem(this.title, this.protocol, this.value1, [this.value2 = 0]);

  String get shortTag {
    switch (protocol) {
      case IrProtocol.necMsb:
        return "NEC ${value1.toRadixString(16).toUpperCase().padLeft(8, '0')}";
      case IrProtocol.rc5:
        return "RC5 ${value1.toRadixString(16).toUpperCase().padLeft(2, '0')}/${value2.toRadixString(16).toUpperCase().padLeft(2, '0')}";
      case IrProtocol.rca:
        return "RCA ${value1.toRadixString(16).toUpperCase()}/${value2.toRadixString(16).toUpperCase().padLeft(2, '0')}";
      case IrProtocol.samsung:
        return "SAM ${value1.toRadixString(16).toUpperCase().padLeft(8, '0')}";
      case IrProtocol.sony:
        return "SONY ${value1.toRadixString(16).toUpperCase()}/${value2.toRadixString(16).toUpperCase().padLeft(2, '0')}";
    }
  }
}

class StarlightRemoteApp extends StatelessWidget {
  const StarlightRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Starlight 32 Pro',
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
  bool _rc5Toggle = false;
  String _statusLabel = "جاري فحص مستشعر IR...";
  String _statusDetail = "";

  // إعدادات تبويب الكاشف الشامل
  IrProtocol _scanProtocol = IrProtocol.necMsb;
  int _activePrefix16 = 0x00BF;
  int _activeAddr = 0x00;
  IrTestItem? _lastTestedPower;

  int _rangeIndex = 0; // 0: 00-5F, 1: 60-AF, 2: B0-FF
  final Set<int> _testedCodes = {};
  int? _lastScannedCode;

  // أشهر 34 كود تشغيل (POWER) بجميع البروتوكولات المستخدمة في ستارلايت 32 بوصة
  final List<IrTestItem> _powerTests = const [
    // 1. بروتوكولات RC5 و RCA و Sony (شائعة جداً في لوحات Vestel و Android Smart)
    IrTestItem("1. RC5 فيستل", IrProtocol.rc5, 0x00, 0x0C),
    IrTestItem("2. RC5 بديل", IrProtocol.rc5, 0x00, 0x3D),
    IrTestItem("3. RCA / TCL", IrProtocol.rca, 0x0F, 0x2A),
    IrTestItem("4. RCA بديل", IrProtocol.rca, 0x0F, 0xD5),

    // 2. بروتوكول NEC MSB (الترتيب القياسي لأغلب لوحات ستارلايت الصينية والسمارت)
    IrTestItem("5. MStar 1", IrProtocol.necMsb, 0x00BF0DF2),
    IrTestItem("6. MStar 2", IrProtocol.necMsb, 0x00BF00FF),
    IrTestItem("7. MStar 3", IrProtocol.necMsb, 0x00BF40BF),
    IrTestItem("8. MStar 4", IrProtocol.necMsb, 0x00BF01FE),
    IrTestItem("9. MStar 5", IrProtocol.necMsb, 0x00BF10EF),
    IrTestItem("10. MStar 6", IrProtocol.necMsb, 0x00BF08F7),
    IrTestItem("11. TP.MS 1", IrProtocol.necMsb, 0x40BF12ED),
    IrTestItem("12. TP.MS 2", IrProtocol.necMsb, 0x40BF00FF),
    IrTestItem("13. TP.MS 3", IrProtocol.necMsb, 0x40BF48B7),
    IrTestItem("14. TP.V56 1", IrProtocol.necMsb, 0x00FF00FF),
    IrTestItem("15. TP.V56 2", IrProtocol.necMsb, 0x00FF08F7),
    IrTestItem("16. TP.V56 3", IrProtocol.necMsb, 0x00FF0DF2),
    IrTestItem("17. TP.V56 4", IrProtocol.necMsb, 0x00FF01FE),
    IrTestItem("18. TP.V56 5", IrProtocol.necMsb, 0x00FF40BF),
    IrTestItem("19. TP.V56 6", IrProtocol.necMsb, 0x00FF48B7),
    IrTestItem("20. TP.V56 7", IrProtocol.necMsb, 0x00FF10EF),
    IrTestItem("21. TP.V56 8", IrProtocol.necMsb, 0x00FF12ED),
    IrTestItem("22. TP.V56 9", IrProtocol.necMsb, 0x00FF807F),
    IrTestItem("23. LG/Star 1", IrProtocol.necMsb, 0x20DF10EF),
    IrTestItem("24. LG/Star 2", IrProtocol.necMsb, 0x04FB08F7),
    IrTestItem("25. Toshiba", IrProtocol.necMsb, 0x02FD48B7),
    IrTestItem("26. Skyworth 1", IrProtocol.necMsb, 0x08F708F7),
    IrTestItem("27. Skyworth 2", IrProtocol.necMsb, 0x08F700FF),
    IrTestItem("28. Android 1", IrProtocol.necMsb, 0x0E0E0CF3),
    IrTestItem("29. Android 2", IrProtocol.necMsb, 0x707030CF),
    IrTestItem("30. Konka", IrProtocol.necMsb, 0x007F00FF),
    IrTestItem("31. Haier", IrProtocol.necMsb, 0x7F8001FE),
    IrTestItem("32. Swap MStar", IrProtocol.necMsb, 0xBF000DF2),
    IrTestItem("33. Samsung", IrProtocol.samsung, 0xE0E040BF),
    IrTestItem("34. Sony", IrProtocol.sony, 0x01, 0x15),
  ];

  final List<int> _necPrefixes = const [
    0x00BF,
    0x40BF,
    0x00FF,
    0x20DF,
    0x04FB,
    0x02FD,
    0x08F7,
    0x0E0E,
    0x7070,
    0x007F,
    0x7F80,
    0xBF00,
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
            ? "جاهز - جرّب الأزرار بالترتيب نحو تلفاز ستارلايت"
            : "مستشعر IR غير متاح في هذا الهاتف";
        _statusDetail = "";
      });
    } catch (e) {
      setState(() {
        _statusLabel = "خطأ في الاتصال بمستشعر IR";
        _statusDetail = "";
      });
    }
  }

  // NEC MSB-first (38 kHz)
  List<int> _buildNecMsbSignal(int code32) {
    final List<int> f = [9000, 4500];
    for (int i = 31; i >= 0; i--) {
      f.add(560);
      f.add(((code32 >> i) & 1) == 1 ? 1690 : 560);
    }
    f.add(560);
    return [...f, 40000, 9000, 2250, 560];
  }

  // Samsung32 MSB-first (38 kHz)
  List<int> _buildSamsungSignal(int code32) {
    final List<int> f = [4500, 4500];
    for (int i = 31; i >= 0; i--) {
      f.add(560);
      f.add(((code32 >> i) & 1) == 1 ? 1690 : 560);
    }
    f.add(560);
    return [...f, 45000, ...f];
  }

  // RC5 Manchester (36 kHz)
  List<int> _buildRc5Signal(int address, int command, bool toggle) {
    final int s2 = command < 64 ? 1 : 0;
    final int data = (1 << 13) |
        (s2 << 12) |
        ((toggle ? 1 : 0) << 11) |
        ((address & 0x1F) << 6) |
        (command & 0x3F);

    final List<bool> levels = [];
    for (int i = 13; i >= 0; i--) {
      final int bit = (data >> i) & 1;
      if (bit == 1) {
        levels.add(false);
        levels.add(true);
      } else {
        levels.add(true);
        levels.add(false);
      }
    }
    while (levels.isNotEmpty && !levels.first) {
      levels.removeAt(0);
    }

    final List<int> pattern = [];
    bool current = true;
    int count = 0;
    for (final bool lvl in levels) {
      if (lvl == current) {
        count++;
      } else {
        pattern.add(count * 889);
        current = lvl;
        count = 1;
      }
    }
    if (count > 0) pattern.add(count * 889);

    if (pattern.length.isOdd) {
      return [...pattern, 89000, ...pattern];
    } else {
      final copy = List<int>.from(pattern);
      copy[copy.length - 1] += 89000;
      return [...copy, ...pattern];
    }
  }

  // RCA / TCL (38 kHz)
  List<int> _buildRcaSignal(int addr4, int cmd8) {
    final int data24 = ((addr4 & 0xF) << 20) |
        ((cmd8 & 0xFF) << 12) |
        (((~addr4) & 0xF) << 8) |
        ((~cmd8) & 0xFF);
    final List<int> f = [4000, 4000];
    for (int i = 23; i >= 0; i--) {
      f.add(500);
      f.add(((data24 >> i) & 1) == 1 ? 2000 : 1000);
    }
    f.add(500);
    return [...f, 8000, ...f];
  }

  // Sony SIRC 12-bit (40 kHz)
  List<int> _buildSonySignal(int addr5, int cmd7) {
    final List<int> f = [2400, 600];
    for (int i = 0; i < 7; i++) {
      f.add(((cmd7 >> i) & 1) == 1 ? 1200 : 600);
      f.add(600);
    }
    for (int i = 0; i < 5; i++) {
      f.add(((addr5 >> i) & 1) == 1 ? 1200 : 600);
      f.add(600);
    }
    final List<int> frameWithGap = List<int>.from(f);
    frameWithGap[frameWithGap.length - 1] = 25000;
    return [...frameWithGap, ...frameWithGap, ...f];
  }

  Future<void> _transmitProtocol(
    IrProtocol protocol,
    int v1,
    int v2,
    String label,
    String detail,
  ) async {
    HapticFeedback.mediumImpact();
    if (!_hasIrEmitter) return;

    late List<int> pattern;
    int freq = 38000;

    switch (protocol) {
      case IrProtocol.necMsb:
        pattern = _buildNecMsbSignal(v1);
        freq = 38000;
        break;
      case IrProtocol.samsung:
        pattern = _buildSamsungSignal(v1);
        freq = 38000;
        break;
      case IrProtocol.rc5:
        _rc5Toggle = !_rc5Toggle;
        pattern = _buildRc5Signal(v1, v2, _rc5Toggle);
        freq = 36000;
        break;
      case IrProtocol.rca:
        pattern = _buildRcaSignal(v1, v2);
        freq = 38000;
        break;
      case IrProtocol.sony:
        pattern = _buildSonySignal(v1, v2);
        freq = 40000;
        break;
    }

    try {
      await _irChannel.invokeMethod('transmit', {
        'pattern': pattern,
        'frequency': freq,
      });
      setState(() {
        _statusLabel = label;
        _statusDetail = detail;
      });
    } catch (e) {
      setState(() {
        _statusLabel = "فشل الإرسال";
        _statusDetail = "";
      });
    }
  }

  Future<void> _sendPowerTest(IrTestItem item) async {
    setState(() => _lastTestedPower = item);
    await _transmitProtocol(
      item.protocol,
      item.value1,
      item.value2,
      item.title,
      item.shortTag,
    );
  }

  void _lockAndScan(IrTestItem item) {
    setState(() {
      _scanProtocol = item.protocol;
      if (item.protocol == IrProtocol.necMsb ||
          item.protocol == IrProtocol.samsung) {
        _activePrefix16 = (item.value1 >> 16) & 0xFFFF;
      } else {
        _activeAddr = item.value1;
      }
      _testedCodes.clear();
      _lastScannedCode = null;
      _statusLabel = "تم قفل البروتوكول للفحص";
      _statusDetail = item.shortTag;
    });
    _tabController.animateTo(1);
  }

  Future<void> _sendScanCode(int cmd) async {
    final String cmdHex = cmd.toRadixString(16).toUpperCase().padLeft(2, '0');
    setState(() {
      _testedCodes.add(cmd);
      _lastScannedCode = cmd;
    });

    if (_scanProtocol == IrProtocol.necMsb ||
        _scanProtocol == IrProtocol.samsung) {
      final int code32 =
          ((_activePrefix16 & 0xFFFF) << 16) | ((cmd & 0xFF) << 8) | ((~cmd) & 0xFF);
      final String prefHex =
          _activePrefix16.toRadixString(16).toUpperCase().padLeft(4, '0');
      await _transmitProtocol(
        _scanProtocol,
        code32,
        0,
        "فحص 0x$prefHex",
        "0x${code32.toRadixString(16).toUpperCase().padLeft(8, '0')} (CMD: 0x$cmdHex)",
      );
    } else {
      await _transmitProtocol(
        _scanProtocol,
        _activeAddr,
        cmd,
        "فحص ${_scanProtocol.name.toUpperCase()}",
        "ADDR: 0x${_activeAddr.toRadixString(16).toUpperCase()} | CMD: 0x$cmdHex",
      );
    }
  }

  Widget _buildQuickPowerTab() {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        children: [
          const Text(
            "جرّب الأزرار من 1 إلى 34 نحو التلفاز؛ أول زر يطفئ أو يشغّل الشاشة اضغط الزر الأخضر أسفله لحفظ البروتوكول:",
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
                final isLast = _lastTestedPower == item;
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
                          item.shortTag,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                onPressed: () => _lockAndScan(_lastTestedPower!),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                  "استجاب لـ (${_lastTestedPower!.title})؟ افحص بقية الأزرار",
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
    final bool isRc5 = _scanProtocol == IrProtocol.rc5;
    final int start =
        isRc5 ? 0x00 : (_rangeIndex == 0 ? 0x00 : (_rangeIndex == 1 ? 0x60 : 0xB0));
    final int count = isRc5 ? 128 : (_rangeIndex == 0 ? 96 : 80);

    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        children: [
          // اختيار البروتوكول
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text("NEC MSB")),
                  selected: _scanProtocol == IrProtocol.necMsb,
                  selectedColor: Colors.teal.shade700,
                  onSelected: (_) => setState(() {
                    _scanProtocol = IrProtocol.necMsb;
                    _testedCodes.clear();
                  }),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text("RC5")),
                  selected: _scanProtocol == IrProtocol.rc5,
                  selectedColor: Colors.teal.shade700,
                  onSelected: (_) => setState(() {
                    _scanProtocol = IrProtocol.rc5;
                    _activeAddr = 0x00;
                    _testedCodes.clear();
                  }),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ChoiceChip(
                  label: const Center(child: Text("RCA/TCL")),
                  selected: _scanProtocol == IrProtocol.rca,
                  selectedColor: Colors.teal.shade700,
                  onSelected: (_) => setState(() {
                    _scanProtocol = IrProtocol.rca;
                    _activeAddr = 0x0F;
                    _testedCodes.clear();
                  }),
                ),
              ),
            ],
          ),
          if (_scanProtocol == IrProtocol.necMsb) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _necPrefixes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final int pref = _necPrefixes[index];
                  final String hex =
                      pref.toRadixString(16).toUpperCase().padLeft(4, '0');
                  return ChoiceChip(
                    label: Text(hex, style: const TextStyle(fontSize: 11)),
                    selected: _activePrefix16 == pref,
                    selectedColor: Colors.indigo.shade700,
                    onSelected: (_) => setState(() {
                      _activePrefix16 = pref;
                      _testedCodes.clear();
                    }),
                  );
                },
              ),
            ),
          ],
          if (!isRc5) ...[
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
          ],
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
          "Starlight 32 Pro",
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
            Tab(text: "1. كاشف البروتوكولات"),
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
