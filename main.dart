import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const StarLedRemoteApp());
}

class StarLedRemoteApp extends StatelessWidget {
  const StarLedRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StarLED HK320DF',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B1120),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: StarLedRemoteScreen(),
      ),
    );
  }
}

class StarLedRemoteScreen extends StatefulWidget {
  const StarLedRemoteScreen({super.key});

  @override
  State<StarLedRemoteScreen> createState() => _StarLedRemoteScreenState();
}

class _StarLedRemoteScreenState extends State<StarLedRemoteScreen>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _irChannel = MethodChannel('starled_ir_channel');

  late final TabController _tabController;
  bool _hasIrEmitter = false;
  String _status = "جاهز - 0xFE01";

  bool _swapAddr = false; // false: 0xFE01 | true: 0x01FE
  bool _isMsb = false; // false: LSB | true: MSB
  int _okCode = 0x21;

  int _rangeIndex = 0; // 0: 00-5F, 1: 60-AF, 2: B0-FF
  final Set<int> _testedCodes = {};
  int? _lastScanned;

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
        _status = hasIr ? "جاهز - StarLED HK320DF" : "مستشعر IR غير متاح";
      });
    } catch (_) {
      setState(() => _status = "خطأ في الاتصال بمستشعر IR");
    }
  }

  String get _addrLabel => _swapAddr ? "0x01FE" : "0xFE01";

  List<int> _buildNecPattern(int addr1, int addr2, int cmd) {
    final int inv = (~cmd) & 0xFF;
    final List<int> bytes = [addr1 & 0xFF, addr2 & 0xFF, cmd & 0xFF, inv];
    final List<int> f = [9000, 4500];

    for (final int b in bytes) {
      if (_isMsb) {
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

  Future<void> _sendKey(String label, int cmd) async {
    HapticFeedback.mediumImpact();
    if (!_hasIrEmitter) return;

    final int a1 = _swapAddr ? 0x01 : 0xFE;
    final int a2 = _swapAddr ? 0xFE : 0x01;
    final String hex = cmd.toRadixString(16).toUpperCase().padLeft(2, '0');

    try {
      await _irChannel.invokeMethod('transmit', {
        'pattern': _buildNecPattern(a1, a2, cmd),
        'frequency': 38000,
      });
      setState(() {
        _status = "أرسل: $label (0x$hex) [${_isMsb ? 'MSB' : 'LSB'}]";
      });
    } catch (_) {
      setState(() => _status = "فشل إرسال الإشارة");
    }
  }

  Widget _btn(String label, int cmd, {Color? color, IconData? icon}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () => _sendKey(label, cmd),
      child: icon != null
          ? Icon(icon, size: 22)
          : Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
    );
  }

  Widget _buildRemoteTab() {
    final String okHex = _okCode.toRadixString(16).toUpperCase().padLeft(2, '0');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _btn("POWER", 0x12, color: Colors.red.shade700, icon: Icons.power_settings_new)),
              const SizedBox(width: 10),
              Expanded(child: _btn("SOURCE", 0x18, color: Colors.indigo.shade700)),
              const SizedBox(width: 10),
              Expanded(child: _btn("MUTE", 0x10, color: Colors.teal.shade700, icon: Icons.volume_off)),
            ],
          ),
          const SizedBox(height: 12),
          for (final row in [
            [("1", 0x01), ("2", 0x02), ("3", 0x03)],
            [("4", 0x04), ("5", 0x05), ("6", 0x06)],
            [("7", 0x07), ("8", 0x08), ("9", 0x09)],
          ]) ...[
            Row(
              children: [
                Expanded(child: _btn(row[0].$1, row[0].$2)),
                const SizedBox(width: 10),
                Expanded(child: _btn(row[1].$1, row[1].$2)),
                const SizedBox(width: 10),
                Expanded(child: _btn(row[2].$1, row[2].$2)),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(child: _btn("MENU", 0x14, color: Colors.blueGrey.shade700)),
              const SizedBox(width: 10),
              Expanded(child: _btn("0", 0x00)),
              const SizedBox(width: 10),
              Expanded(child: _btn("EXIT", 0x1C, color: Colors.blueGrey.shade700)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _btn("VOL +", 0x1A),
                    const SizedBox(height: 10),
                    _btn("VOL -", 0x1E),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    SizedBox(width: 66, child: _btn("UP", 0x19, icon: Icons.keyboard_arrow_up)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 56, child: _btn("RIGHT", 0x40, icon: Icons.keyboard_arrow_right)),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 68,
                          child: _btn("OK\n$okHex", _okCode, color: Colors.blue.shade700),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(width: 56, child: _btn("LEFT", 0x42, icon: Icons.keyboard_arrow_left)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(width: 66, child: _btn("DOWN", 0x1D, icon: Icons.keyboard_arrow_down)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _btn("CH +", 0x1B),
                    const SizedBox(height: 10),
                    _btn("CH -", 0x1F),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScannerTab() {
    final int start = _rangeIndex == 0 ? 0x00 : (_rangeIndex == 1 ? 0x60 : 0xB0);
    final int count = _rangeIndex == 0 ? 96 : 80;

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          const Text(
            "افتح MENU أولاً ثم جرّب الأكواد؛ الكود الذي يعمل كـ OK اضغط عليه مطوّلاً لتثبيته:",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.amberAccent),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rangeIndex == 0 ? Colors.teal.shade700 : const Color(0xFF1E293B),
                  ),
                  onPressed: () => setState(() => _rangeIndex = 0),
                  child: const Text("00 - 5F", style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rangeIndex == 1 ? Colors.teal.shade700 : const Color(0xFF1E293B),
                  ),
                  onPressed: () => setState(() => _rangeIndex = 1),
                  child: const Text("60 - AF", style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rangeIndex == 2 ? Colors.teal.shade700 : const Color(0xFF1E293B),
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
                childAspectRatio: 1.7,
              ),
              itemCount: count,
              itemBuilder: (context, index) {
                final int code = start + index;
                final String hex = code.toRadixString(16).toUpperCase().padLeft(2, '0');
                final bool tested = _testedCodes.contains(code);
                final bool isOk = _okCode == code;
                final bool isLast = _lastScanned == code;

                return GestureDetector(
                  onLongPress: () {
                    setState(() {
                      _okCode = code;
                      _status = "تم تثبيت 0x$hex لزر OK";
                    });
                  },
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isOk
                          ? Colors.green.shade700
                          : (tested ? Colors.deepPurple.shade400 : Colors.indigo.shade700),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      side: isLast
                          ? const BorderSide(color: Colors.amberAccent, width: 2)
                          : BorderSide.none,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      setState(() {
                        _testedCodes.add(code);
                        _lastScanned = code;
                      });
                      _sendKey("فحص", code);
                    },
                    child: Text(hex, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
        title: const Text("StarLED HK320DF", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _isMsb = !_isMsb;
              _status = "الترتيب الآن: ${_isMsb ? 'MSB' : 'LSB'}";
            }),
            child: Text(
              _isMsb ? "MSB" : "LSB",
              style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _swapAddr = !_swapAddr;
              _status = "العنوان الآن: $_addrLabel";
            }),
            child: Text(
              _addrLabel,
              style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.tealAccent,
          labelColor: Colors.tealAccent,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: "الريموت"),
            Tab(text: "كاشف OK (00-FF)"),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF132A2E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.tealAccent),
              ),
              child: Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRemoteTab(),
                  _buildScannerTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
