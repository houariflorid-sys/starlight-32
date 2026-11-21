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
  String _status = "جاري فحص مستشعر IR...";

  // تبديل العنوان بين أشهر عناوين StarLED (AMW 5904)
  final List<List<int>> _addresses = const [
    [0x00, 0xBF],
    [0x00, 0xFF],
    [0x40, 0xBF],
  ];
  int _addrIndex = 0;

  // كود زر OK الحالي (يمكنك تغييره بالضغط المطوّل على أي كود اختبار بالأسفل)
  int _okCode = 0x15;

  // أشهر أكواد زر OK / ENTER البديلة لتلفزيونات StarLED
  final List<int> _okCandidates = const [
    0x0B, 0x15, 0x16, 0x1C, 0x44, 0x05,
    0x14, 0x19, 0x52, 0x0E, 0x1A, 0x0A,
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

  String get _currentAddrHex {
    final a = _addresses[_addrIndex];
    return "${a[0].toRadixString(16).toUpperCase().padLeft(2, '0')}${a[1].toRadixString(16).toUpperCase().padLeft(2, '0')}";
  }

  void _toggleAddressCode() {
    setState(() {
      _addrIndex = (_addrIndex + 1) % _addresses.length;
      _status = "تم تغيير العنوان إلى: 0x$_currentAddrHex";
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

    final a = _addresses[_addrIndex];
    final hex = cmd.toRadixString(16).toUpperCase().padLeft(2, '0');
    try {
      await _irChannel.invokeMethod('transmit', {
        'pattern': _buildNecPattern(a[0], a[1], cmd),
        'frequency': 38000,
      });
      setState(() => _status = "$label (0x$_currentAddrHex / 0x$hex)");
    } catch (_) {
      setState(() => _status = "فشل إرسال الإشارة");
    }
  }

  Widget _btn(String label, int cmd, {Color? color, IconData? icon}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () => _sendKey(label, cmd),
      child: icon != null
          ? Icon(icon, size: 24)
          : Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final okHex = _okCode.toRadixString(16).toUpperCase().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(
        title: const Text("StarLED HK320DF", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _toggleAddressCode,
            child: Text(
              _currentAddrHex,
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF132A2E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.tealAccent),
                ),
                child: Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _btn("POWER", 0x0D, color: Colors.red.shade700, icon: Icons.power_settings_new)),
                  const SizedBox(width: 10),
                  Expanded(child: _btn("SOURCE", 0x12, color: Colors.indigo.shade700)),
                  const SizedBox(width: 10),
                  Expanded(child: _btn("MUTE", 0x10, color: Colors.orange.shade800, icon: Icons.volume_off)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _btn("VOL +", 0x18, color: Colors.teal.shade700),
                        const SizedBox(height: 8),
                        _btn("VOL -", 0x19, color: Colors.teal.shade900),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _btn("CH +", 0x1A, color: Colors.blueGrey.shade700),
                        const SizedBox(height: 8),
                        _btn("CH -", 0x1B, color: Colors.blueGrey.shade900),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // أسهم التنقل وزر OK
              Column(
                children: [
                  SizedBox(width: 90, child: _btn("UP", 0x01, icon: Icons.keyboard_arrow_up)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 85, child: _btn("RIGHT", 0x04, icon: Icons.keyboard_arrow_right)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 90,
                        child: _btn("OK ($okHex)", _okCode, color: Colors.green.shade700),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(width: 85, child: _btn("LEFT", 0x03, icon: Icons.keyboard_arrow_left)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(width: 90, child: _btn("DOWN", 0x02, icon: Icons.keyboard_arrow_down)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _btn("MENU", 0x14, color: Colors.deepPurple.shade700)),
                  const SizedBox(width: 10),
                  Expanded(child: _btn("EXIT", 0x1F, color: Colors.brown.shade700)),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                "اختبار أكواد زر OK (اضغط للتجربة، واضغط مطوّلاً لتثبيته على زر OK):",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.amberAccent),
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
                        _status = "تم تثبيت الكود 0x$hex لزر OK";
                      });
                    },
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected ? Colors.green.shade700 : const Color(0xFF1E293B),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(64, 40),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => _sendKey("تجربة OK", code),
                      child: Text(hex, style: const TextStyle(fontWeight: FontWeight.bold)),
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
