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

class _StarLedRemoteScreenState extends State<StarLedRemoteScreen> {
  static const MethodChannel _irChannel = MethodChannel('starled_ir_channel');

  bool _hasIrEmitter = false;
  String _status = "جاهز - 0xFE01";

  // التبديل بين 0xFE01 (الافتراضي) و 0x01FE
  bool _swapAddr = false;

  // كود زر OK الحالي (اضغط مطوّلاً على أي كود اختبار بالأسفل لتثبيته)
  int _okCode = 0x21;

  // أشهر أكواد OK البديلة لعنوان 0xFE01
  final List<int> _okCandidates = const [
    0x21, 0x15, 0x16, 0x17, 0x0B, 0x0D, 0x0E, 0x0F,
    0x11, 0x13, 0x20, 0x41, 0x44, 0x45, 0x52, 0x5C,
  ];

  @override
  void initState() {
    super.initState();
    _checkIrSensor();
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

  void _toggleAddressCode() {
    setState(() {
      _swapAddr = !_swapAddr;
      _status = "تم التبديل إلى: $_addrLabel";
    });
  }

  List<int> _buildNecPattern(int addr1, int addr2, int cmd) {
    final List<int> f = [9000, 4500];
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
    return [...f, 40000, 9000, 2250, 560];
  }

  Future<void> _sendKey(String label, int cmd) async {
    HapticFeedback.mediumImpact();
    if (!_hasIrEmitter) return;

    final int a1 = _swapAddr ? 0x01 : 0xFE;
    final int a2 = _swapAddr ? 0xFE : 0x01;
    final String hex = cmd.toRadixString(16).toUpperCase();

    try {
      await _irChannel.invokeMethod('transmit', {
        'pattern': _buildNecPattern(a1, a2, cmd),
        'frequency': 38000,
      });
      setState(() => _status = "أرسل: $label (0x$hex)");
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

  @override
  Widget build(BuildContext context) {
    final String okHex = _okCode.toRadixString(16).toUpperCase().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(
        title: const Text("StarLED HK320DF", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          TextButton.icon(
            onPressed: _toggleAddressCode,
            icon: const Icon(Icons.swap_horiz, color: Colors.amberAccent, size: 18),
            label: Text(
              _addrLabel,
              style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF132A2E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.tealAccent),
                ),
                child: Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              const SizedBox(height: 12),
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
              // لوحة الأرقام 1 - 9 و 0 و MENU و EXIT
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
              // VOL و CH والأسهم و OK
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
                              child: _btn("OK", _okCode, color: Colors.blue.shade700),
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
              const SizedBox(height: 18),
              Text(
                "اختبار أكواد زر OK (الحالي: 0x$okHex) — اضغط للتجربة، واضغط مطوّلاً لتثبيته:",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.amberAccent),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: _okCandidates.map((code) {
                  final hex = code.toRadixString(16).toUpperCase().padLeft(2, '0');
                  final isSelected = _okCode == code;
                  return GestureDetector(
                    onLongPress: () {
                      setState(() {
                        _okCode = code;
                        _status = "تم تثبيت 0x$hex لزر OK";
                      });
                    },
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected ? Colors.blue.shade700 : const Color(0xFF1E293B),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(58, 38),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => _sendKey("OK_TEST", code),
                      child: Text(hex, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
