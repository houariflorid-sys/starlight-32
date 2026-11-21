import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// بيانات مشروع Supabase (إذا ظهر 401 استبدل المفتاح بمفتاح Legacy anon الذي يبدأ بـ eyJ)
const String supabaseUrl = 'https://djorlzsranhyakftukww.supabase.co';
const String supabaseKey = 'sb_publishable_ZMGgDXFtySTeVt_d5XRhYg_dTuSmdku';

void main() {
  runApp(const FamilyTrackerApp());
}

class FamilyMember {
  final String phone;
  final String name;
  final double lat;
  final double lng;
  final DateTime? updatedAt;

  FamilyMember({
    required this.phone,
    required this.name,
    required this.lat,
    required this.lng,
    required this.updatedAt,
  });

  String get formattedTime {
    if (updatedAt == null) return 'غير معروف';
    final local = updatedAt!.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
    if (diff.inHours < 24) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day}/${local.month} - ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class ChatMessage {
  final int id;
  final String senderName;
  final String senderPhone;
  final String text;
  final DateTime? createdAt;

  ChatMessage({
    required this.id,
    required this.senderName,
    required this.senderPhone,
    required this.text,
    required this.createdAt,
  });

  String get formattedTime {
    if (createdAt == null) return '';
    final local = createdAt!.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class FamilyTrackerApp extends StatelessWidget {
  const FamilyTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تتبع العائلة',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B1120),
        colorScheme: ColorScheme.dark(
          primary: Colors.tealAccent.shade400,
          secondary: Colors.indigoAccent,
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // قناة صلاحية مشرف الجهاز (Device Admin)
  static const MethodChannel _adminChannel =
      MethodChannel('family_device_admin_channel');
  bool _isAdminActive = false;
  bool _skipNextAutoLock = false;

  // نظام قفل التطبيق برمز PIN
  String _savedPin = '';
  bool _isLocked = false;
  final _unlockPinCtrl = TextEditingController();
  String _lockError = '';

  // إخفاء الرمز العائلي بنجوم
  bool _obscureMyCode = true;
  bool _obscureSearchCode = true;

  // حقول تبويب "مشاركة موقعي"
  final _myNameCtrl = TextEditingController();
  final _myPhoneCtrl = TextEditingController();
  final _myCodeCtrl = TextEditingController();
  bool _isBackgroundSharing = false;
  bool _batterySaverMode = true; // التتبع عند الحركة فقط (كل 50 متر)
  bool _isSending = false;
  StreamSubscription<Position>? _positionSub;
  DateTime? _lastUploadTime;
  String _shareStatus = "أدخل بياناتك وفعّل التتبع المستمر في الخلفية";

  // حقول تبويب "خريطة العائلة"
  final _familyCodeSearchCtrl = TextEditingController();
  bool _isLoadingFamily = false;
  bool _isAutoRefresh = false;
  Timer? _refreshTimer;
  String _mapStatus = "أدخل الرمز العائلي لعرض جميع الهواتف على الخريطة";

  List<FamilyMember> _members = [];
  FamilyMember? _selectedMember;
  final MapController _mapController = MapController();
  bool _mapReady = false;

  // حقول تبويب "الدردشة ومكالمة الفيديو"
  final _chatMsgCtrl = TextEditingController();
  final _chatScrollCtrl = ScrollController();
  List<ChatMessage> _messages = [];
  bool _isLoadingChat = false;
  bool _isSendingMsg = false;
  String _chatStatus = "";
  Timer? _chatTimer;

  String get _activeFamilyCode {
    final myCode = _myCodeCtrl.text.trim();
    if (myCode.isNotEmpty) return myCode;
    return _familyCodeSearchCtrl.text.trim();
  }

  Map<String, String> _supabaseHeaders({bool isWrite = false, bool merge = false}) {
    final headers = <String, String>{
      'apikey': supabaseKey,
    };
    if (supabaseKey.startsWith('eyJ')) {
      headers['Authorization'] = 'Bearer $supabaseKey';
    }
    if (isWrite) {
      headers['Content-Type'] = 'application/json';
      if (merge) {
        headers['Prefer'] = 'resolution=merge-duplicates';
      }
    }
    return headers;
  }

  String _extractServerError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['message'] != null) {
        return "خطأ ${response.statusCode}: ${decoded['message']}";
      }
    } catch (_) {}
    return "خطأ في الخادم: ${response.statusCode}";
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedData();
    _checkAdminStatus();
    _chatTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!_isLocked && _activeFamilyCode.isNotEmpty) {
        _fetchMessages(silent: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _refreshTimer?.cancel();
    _chatTimer?.cancel();
    _unlockPinCtrl.dispose();
    _myNameCtrl.dispose();
    _myPhoneCtrl.dispose();
    _myCodeCtrl.dispose();
    _familyCodeSearchCtrl.dispose();
    _chatMsgCtrl.dispose();
    _chatScrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (_skipNextAutoLock) return;
      if (_savedPin.isNotEmpty) {
        setState(() {
          _isLocked = true;
          _unlockPinCtrl.clear();
          _lockError = '';
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      _skipNextAutoLock = false;
      _checkAdminStatus();
    }
  }

  Future<void> _checkAdminStatus() async {
    try {
      final bool active =
          await _adminChannel.invokeMethod<bool>('isAdminActive') ?? false;
      if (!mounted) return;
      setState(() => _isAdminActive = active);
    } catch (_) {}
  }

  Future<void> _toggleUninstallProtection() async {
    if (!_isAdminActive) {
      try {
        _skipNextAutoLock = true;
        await _adminChannel.invokeMethod('enableAdmin');
      } catch (e) {
        _skipNextAutoLock = false;
        if (!mounted) return;
        setState(() => _shareStatus = "تعذر فتح نافذة مشرف الجهاز");
      }
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text(
              'إيقاف الحماية من إلغاء التثبيت',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'بعد إيقاف صلاحية مشرف الجهاز، ستتمكن من حذف التطبيق بشكل طبيعي من الهاتف. هل تريد المتابعة؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('تراجع'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('إيقاف الحماية'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      try {
        await _adminChannel.invokeMethod('disableAdmin');
        await Future.delayed(const Duration(milliseconds: 400));
        await _checkAdminStatus();
      } catch (_) {}
    }
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final pin = prefs.getString('app_pin') ?? '';
    setState(() {
      _savedPin = pin;
      _isLocked = pin.isNotEmpty;
      _batterySaverMode = prefs.getBool('battery_saver_mode') ?? true;
      _myNameCtrl.text = prefs.getString('my_name') ?? '';
      _myPhoneCtrl.text = prefs.getString('my_phone') ?? '';
      _myCodeCtrl.text = prefs.getString('my_code') ?? '';
      _familyCodeSearchCtrl.text =
          prefs.getString('search_family_code') ?? _myCodeCtrl.text;
    });
    if (_activeFamilyCode.isNotEmpty) {
      _fetchMessages(silent: true);
    }
  }

  Future<void> _saveMyData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('my_name', _myNameCtrl.text.trim());
    await prefs.setString('my_phone', _myPhoneCtrl.text.trim());
    await prefs.setString('my_code', _myCodeCtrl.text.trim());
    await prefs.setBool('battery_saver_mode', _batterySaverMode);
  }

  Future<void> _saveSearchCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'search_family_code',
      _familyCodeSearchCtrl.text.trim(),
    );
  }

  void _attemptUnlock() {
    if (_unlockPinCtrl.text.trim() == _savedPin) {
      setState(() {
        _isLocked = false;
        _unlockPinCtrl.clear();
        _lockError = '';
      });
    } else {
      setState(() {
        _lockError = 'رمز القفل غير صحيح';
        _unlockPinCtrl.clear();
      });
    }
  }

  Future<void> _showPinSettingsDialog() async {
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String dialogError = '';

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: const Color(0xFF1E293B),
                title: Text(
                  _savedPin.isEmpty
                      ? 'تعيين رمز قفل للتطبيق'
                      : 'تغيير رمز القفل (PIN)',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: pinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'أدخل رمزاً سرياً (4 أرقام أو أكثر)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: confirmCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'تأكيد الرمز السري',
                      ),
                    ),
                    if (dialogError.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        dialogError,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                      ),
                    ],
                  ],
                ),
                actions: [
                  if (_savedPin.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('app_pin');
                        if (!mounted) return;
                        setState(() {
                          _savedPin = '';
                          _isLocked = false;
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text(
                        'إلغاء القفل',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إغلاق'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final p1 = pinCtrl.text.trim();
                      final p2 = confirmCtrl.text.trim();
                      if (p1.length < 4) {
                        setDialogState(
                          () => dialogError = 'يجب أن يتكون الرمز من 4 أرقام على الأقل',
                        );
                        return;
                      }
                      if (p1 != p2) {
                        setDialogState(() => dialogError = 'الرمزان غير متطابقين');
                        return;
                      }
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('app_pin', p1);
                      if (!mounted) return;
                      setState(() => _savedPin = p1);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('حفظ القفل'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    pinCtrl.dispose();
    confirmCtrl.dispose();
  }

  Future<bool> _ensurePermissions({bool forBackground = false}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _shareStatus = "يرجى تفعيل خدمة الموقع (GPS) في الهاتف");
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _shareStatus = "تم رفض إذن الوصول للموقع");
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _shareStatus = "إذن الموقع محظور، فعّله من إعدادات التطبيق");
      return false;
    }

    if (forBackground) {
      await Permission.notification.request();
      if (await Permission.locationAlways.isDenied) {
        await Permission.locationAlways.request();
      }
    }

    return true;
  }

  Future<void> _uploadPosition(Position position) async {
    final name = _myNameCtrl.text.trim();
    final phone = _myPhoneCtrl.text.trim().replaceAll(' ', '');
    final code = _myCodeCtrl.text.trim();

    if (name.isEmpty || phone.isEmpty || code.isEmpty) return;

    try {
      final uri = Uri.parse(
        '$supabaseUrl/rest/v1/family_locations?on_conflict=phone_number',
      );

      final response = await http.post(
        uri,
        headers: _supabaseHeaders(isWrite: true, merge: true),
        body: jsonEncode({
          'phone_number': phone,
          'display_name': name,
          'family_code': code,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );

      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        _lastUploadTime = DateTime.now();
        final now = TimeOfDay.now();
        final timeStr =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        setState(() {
          _shareStatus =
              "تم التحديث بنجاح ($timeStr)\n${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}";
        });
      } else {
        setState(() => _shareStatus = _extractServerError(response));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _shareStatus = "تعذر الإرسال، تحقق من اتصال الإنترنت");
    }
  }

  Future<void> _sendMyLocationOnce() async {
    if (_myNameCtrl.text.trim().isEmpty ||
        _myPhoneCtrl.text.trim().isEmpty ||
        _myCodeCtrl.text.trim().isEmpty) {
      setState(() => _shareStatus = "يرجى ملء الاسم ورقم الهاتف والرمز العائلي");
      return;
    }

    await _saveMyData();
    if (!await _ensurePermissions(forBackground: false)) return;

    setState(() {
      _isSending = true;
      _shareStatus = "جاري التقاط إحداثيات GPS...";
    });

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await _uploadPosition(position);
    } catch (e) {
      if (mounted) {
        setState(() => _shareStatus = "تعذر التقاط الموقع، تأكد من تفعيل GPS");
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _toggleBackgroundSharing(bool enable) async {
    if (!enable) {
      await _positionSub?.cancel();
      _positionSub = null;
      setState(() {
        _isBackgroundSharing = false;
        _shareStatus = "تم إيقاف التتبع في الخلفية";
      });
      return;
    }

    if (_myNameCtrl.text.trim().isEmpty ||
        _myPhoneCtrl.text.trim().isEmpty ||
        _myCodeCtrl.text.trim().isEmpty) {
      setState(() => _shareStatus = "يرجى ملء الاسم ورقم الهاتف والرمز العائلي أولاً");
      return;
    }

    await _saveMyData();
    if (!await _ensurePermissions(forBackground: true)) return;

    await _positionSub?.cancel();
    _lastUploadTime = null;

    // وضع توفير البطارية: يرسل الموقع فقط عند التحرك 50 متر | الوضع الدقيق: كل 20 ثانية
    final LocationSettings locationSettings = AndroidSettings(
      accuracy: _batterySaverMode
          ? LocationAccuracy.medium
          : LocationAccuracy.high,
      distanceFilter: _batterySaverMode ? 50 : 0,
      intervalDuration: _batterySaverMode
          ? const Duration(seconds: 60)
          : const Duration(seconds: 20),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: 'تتبع العائلة نشط',
        notificationText: _batterySaverMode
            ? 'وضع توفير البطارية: يتم التحديث عند الحركة فقط (كل 50 متر)'
            : 'الوضع الدقيق: يتم تحديث الموقع باستمرار',
        enableWakeLock: !_batterySaverMode,
        setOngoing: true,
      ),
    );

    setState(() {
      _isBackgroundSharing = true;
      _shareStatus = _batterySaverMode
          ? "التتبع نشط (وضع توفير البطارية: عند الحركة فقط كل 50 متر)"
          : "التتبع الدقيق نشط (تحديث مستمر كل 20 ثانية)";
    });

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        final now = DateTime.now();
        final minGap = _batterySaverMode ? 45 : 18;
        if (_lastUploadTime == null ||
            now.difference(_lastUploadTime!).inSeconds >= minGap) {
          _uploadPosition(position);
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _isBackgroundSharing = false;
          _shareStatus = "توقف التتبع الخلفي، تأكد من صلاحية الموقع طوال الوقت";
        });
      },
    );
  }

  Future<void> _fetchAllFamily({bool moveCamera = true}) async {
    final code = _familyCodeSearchCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _mapStatus = "يرجى إدخال الرمز العائلي السري");
      return;
    }

    await _saveSearchCode();
    setState(() {
      _isLoadingFamily = true;
      _mapStatus = "جاري جلب مواقع أفراد العائلة...";
    });

    try {
      final uri = Uri.parse(
        '$supabaseUrl/rest/v1/family_locations'
        '?family_code=eq.${Uri.encodeQueryComponent(code)}'
        '&select=*&order=updated_at.desc',
      );

      final response = await http.get(
        uri,
        headers: _supabaseHeaders(isWrite: false),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (data.isEmpty) {
          setState(() {
            _members = [];
            _selectedMember = null;
            _mapStatus = "لا توجد هواتف مسجلة بهذا الرمز العائلي";
          });
        } else {
          final parsed = data.map((raw) {
            final item = raw as Map<String, dynamic>;
            return FamilyMember(
              phone: item['phone_number']?.toString() ?? '',
              name: item['display_name']?.toString() ?? 'بدون اسم',
              lat: (item['latitude'] as num).toDouble(),
              lng: (item['longitude'] as num).toDouble(),
              updatedAt: DateTime.tryParse(item['updated_at']?.toString() ?? ''),
            );
          }).toList();

          FamilyMember target = parsed.first;
          if (_selectedMember != null) {
            for (final m in parsed) {
              if (m.phone == _selectedMember!.phone) {
                target = m;
                break;
              }
            }
          }

          setState(() {
            _members = parsed;
            _selectedMember = target;
            _mapStatus = "تم العثور على ${parsed.length} هاتف في العائلة";
          });

          if (moveCamera && _mapReady) {
            _mapController.move(LatLng(target.lat, target.lng), 15.0);
          }
        }
      } else {
        setState(() => _mapStatus = _extractServerError(response));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _mapStatus = "تعذر الاتصال بالخادم، تحقق من الإنترنت");
    } finally {
      if (mounted) setState(() => _isLoadingFamily = false);
    }
  }

  // ===== دوال الدردشة ومكالمة الفيديو =====

  Future<void> _fetchMessages({bool silent = false}) async {
    final code = _activeFamilyCode;
    if (code.isEmpty) {
      if (!silent) {
        setState(() => _chatStatus = "أدخل الرمز العائلي في تبويب مشاركة موقعي أو الخريطة أولاً");
      }
      return;
    }

    if (!silent) setState(() => _isLoadingChat = true);

    try {
      final uri = Uri.parse(
        '$supabaseUrl/rest/v1/family_messages'
        '?family_code=eq.${Uri.encodeQueryComponent(code)}'
        '&select=*&order=created_at.asc&limit=80',
      );

      final response = await http.get(
        uri,
        headers: _supabaseHeaders(isWrite: false),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final parsed = data.map((raw) {
          final item = raw as Map<String, dynamic>;
          return ChatMessage(
            id: (item['id'] as num?)?.toInt() ?? 0,
            senderName: item['sender_name']?.toString() ?? 'عضو',
            senderPhone: item['sender_phone']?.toString() ?? '',
            text: item['message_text']?.toString() ?? '',
            createdAt: DateTime.tryParse(item['created_at']?.toString() ?? ''),
          );
        }).toList();

        final bool hasNew = parsed.length != _messages.length;
        setState(() {
          _messages = parsed;
          _chatStatus = "";
        });

        if (hasNew && _chatScrollCtrl.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_chatScrollCtrl.hasClients) {
              _chatScrollCtrl.jumpTo(_chatScrollCtrl.position.maxScrollExtent);
            }
          });
        }
      } else if (!silent) {
        setState(() => _chatStatus = _extractServerError(response));
      }
    } catch (_) {
      if (!silent && mounted) {
        setState(() => _chatStatus = "تعذر تحميل الرسائل، تحقق من الإنترنت");
      }
    } finally {
      if (!silent && mounted) setState(() => _isLoadingChat = false);
    }
  }

  Future<void> _sendChatMessage({String? customText}) async {
    final text = (customText ?? _chatMsgCtrl.text).trim();
    final code = _activeFamilyCode;
    final name = _myNameCtrl.text.trim().isEmpty ? 'فرد من العائلة' : _myNameCtrl.text.trim();
    final phone = _myPhoneCtrl.text.trim().replaceAll(' ', '');

    if (text.isEmpty) return;
    if (code.isEmpty) {
      setState(() => _chatStatus = "يرجى إدخال الرمز العائلي أولاً");
      return;
    }

    setState(() => _isSendingMsg = true);
    try {
      final uri = Uri.parse('$supabaseUrl/rest/v1/family_messages');
      final response = await http.post(
        uri,
        headers: _supabaseHeaders(isWrite: true, merge: false),
        body: jsonEncode({
          'family_code': code,
          'sender_name': name,
          'sender_phone': phone,
          'message_text': text,
        }),
      );

      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (customText == null) _chatMsgCtrl.clear();
        await _fetchMessages(silent: true);
      } else {
        setState(() => _chatStatus = _extractServerError(response));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _chatStatus = "تعذر إرسال الرسالة، تحقق من الإنترنت");
      }
    } finally {
      if (mounted) setState(() => _isSendingMsg = false);
    }
  }

  Future<void> _startVideoCall() async {
    final code = _activeFamilyCode;
    if (code.isEmpty) {
      setState(() => _chatStatus = "يرجى إدخال الرمز العائلي أولاً لإنشاء غرفة فيديو خاصة");
      return;
    }

    // توليد اسم غرفة آمن وفريد من الرمز العائلي السري
    final safeRoom = base64Url
        .encode(utf8.encode('fam_$code'))
        .replaceAll('=', '')
        .replaceAll('-', '')
        .replaceAll('_', '');
    final roomUrl = 'https://meet.jit.si/FamilyRoom$safeRoom';

    final name = _myNameCtrl.text.trim().isEmpty ? 'أحد أفراد العائلة' : _myNameCtrl.text.trim();
    await _sendChatMessage(
      customText: "📹 بدأ $name مكالمة فيديو عائلية الآن — اضغط زر (مكالمة فيديو) بالأعلى للانضمام",
    );

    _skipNextAutoLock = true;
    await launchUrl(
      Uri.parse(roomUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  void _selectMember(FamilyMember member) {
    setState(() => _selectedMember = member);
    if (_mapReady) {
      _mapController.move(LatLng(member.lat, member.lng), 16.0);
    }
  }

  void _toggleAutoRefresh(bool value) {
    setState(() => _isAutoRefresh = value);
    _refreshTimer?.cancel();
    if (value) {
      _fetchAllFamily(moveCamera: true);
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _fetchAllFamily(moveCamera: false),
      );
    }
  }

  Future<void> _openSelectedInGoogleMaps() async {
    final m = _selectedMember;
    if (m == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${m.lat},${m.lng}',
    );
    _skipNextAutoLock = true;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  InputDecoration _inputStyle(
    String label,
    IconData icon, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.tealAccent),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF1E293B),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _buildLockScreen() {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 72, color: Colors.tealAccent),
                const SizedBox(height: 16),
                const Text(
                  'تطبيق تتبع العائلة مقفل',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'أدخل رمز القفل (PIN) لفتح التطبيق أو تعديل إعدادات التتبع',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _unlockPinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, letterSpacing: 6),
                  onSubmitted: (_) => _attemptUnlock(),
                  decoration: _inputStyle('رمز القفل السري (PIN)', Icons.vpn_key),
                ),
                if (_lockError.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _lockError,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _attemptUnlock,
                    icon: const Icon(Icons.lock_open),
                    label: const Text(
                      'فتح التطبيق',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatTab() {
    final myPhone = _myPhoneCtrl.text.trim().replaceAll(' ', '');
    final myName = _myNameCtrl.text.trim();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _startVideoCall,
                  icon: const Icon(Icons.videocam),
                  label: const Text(
                    "بدء / انضمام لمكالمة فيديو عائلية",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: "تحديث الرسائل",
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  padding: const EdgeInsets.all(12),
                ),
                onPressed: _isLoadingChat ? null : () => _fetchMessages(silent: false),
                icon: const Icon(Icons.refresh, color: Colors.tealAccent),
              ),
            ],
          ),
        ),
        if (_chatStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              _chatStatus,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
            ),
          ),
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Text(
                    "لا توجد رسائل بعد.\nابدأ الدردشة مع عائلتك هنا!",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isMe = (myPhone.isNotEmpty && msg.senderPhone == myPhone) ||
                        (myName.isNotEmpty && msg.senderName == myName);
                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.78,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? const Color(0xFF0F4C5C)
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isMe
                                ? Colors.tealAccent.withValues(alpha: 0.4)
                                : Colors.white12,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  msg.senderName,
                                  style: const TextStyle(
                                    color: Colors.amberAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  msg.formattedTime,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              msg.text,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatMsgCtrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendChatMessage(),
                    decoration: InputDecoration(
                      hintText: "اكتب رسالة للعائلة...",
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.teal.shade700,
                  child: IconButton(
                    onPressed: _isSendingMsg ? null : () => _sendChatMessage(),
                    icon: _isSendingMsg
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShareTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _isBackgroundSharing
                  ? const Color(0xFF0E3A2F)
                  : const Color(0xFF132A2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isBackgroundSharing
                    ? Colors.greenAccent
                    : Colors.tealAccent,
              ),
            ),
            child: Text(
              _shareStatus,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _isBackgroundSharing
                    ? Colors.greenAccent
                    : Colors.tealAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _myNameCtrl,
            enabled: !_isBackgroundSharing,
            decoration: _inputStyle("اسم صاحب الهاتف (مثلاً: معتز)", Icons.person),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _myPhoneCtrl,
            enabled: !_isBackgroundSharing,
            keyboardType: TextInputType.phone,
            decoration: _inputStyle("رقم هذا الهاتف (مثلاً: 0661xxxxxx)", Icons.phone),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _myCodeCtrl,
            enabled: !_isBackgroundSharing,
            obscureText: _obscureMyCode,
            decoration: _inputStyle(
              "الرمز العائلي السري (نفسه لكل العائلة)",
              Icons.lock,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureMyCode ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white70,
                ),
                onPressed: () =>
                    setState(() => _obscureMyCode = !_obscureMyCode),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            tileColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text(
              "وضع توفير البطارية (التتبع عند الحركة فقط)",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: const Text(
              "ينام الـ GPS عند ثبات الهاتف ويُحدّث الموقع تلقائياً كل 50 متر حركة",
              style: TextStyle(fontSize: 12),
            ),
            value: _batterySaverMode,
            onChanged: _isBackgroundSharing
                ? null
                : (val) async {
                    setState(() => _batterySaverMode = val);
                    await _saveMyData();
                  },
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            tileColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text(
              "تفعيل التتبع المستمر (حتى والشاشة مغلقة)",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: const Text(
              "يعمل عبر خدمة خلفية رسمية بإشعار ظاهر في الشريط العلوي",
              style: TextStyle(fontSize: 12),
            ),
            value: _isBackgroundSharing,
            onChanged: _toggleBackgroundSharing,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.tealAccent,
              side: const BorderSide(color: Colors.tealAccent),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _showPinSettingsDialog,
            icon: Icon(_savedPin.isEmpty ? Icons.lock_open : Icons.verified_user),
            label: Text(
              _savedPin.isEmpty
                  ? "تفعيل قفل التطبيق برمز سري (PIN)"
                  : "القفل مفعّل (اضغط لتغيير رمز PIN)",
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  _isAdminActive ? Colors.greenAccent : Colors.lightBlueAccent,
              side: BorderSide(
                color: _isAdminActive
                    ? Colors.greenAccent
                    : Colors.lightBlueAccent,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _toggleUninstallProtection,
            icon: Icon(
              _isAdminActive ? Icons.shield : Icons.admin_panel_settings,
            ),
            label: Text(
              _isAdminActive
                  ? "الحماية من إلغاء التثبيت مفعّلة (اضغط للإيقاف)"
                  : "تفعيل الحماية من إلغاء التثبيت (مشرف الجهاز)",
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.amberAccent,
              side: const BorderSide(color: Colors.amberAccent),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => openAppSettings(),
            icon: const Icon(Icons.settings),
            label: const Text("فتح إعدادات التطبيق (لضبط الموقع والبطارية)"),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSending ? null : _sendMyLocationOnce,
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.my_location),
              label: const Text(
                "إرسال موقعي الآن مرة واحدة",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFamilyMapTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _familyCodeSearchCtrl,
                      obscureText: _obscureSearchCode,
                      decoration: _inputStyle(
                        "الرمز العائلي السري",
                        Icons.family_restroom,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureSearchCode
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white70,
                          ),
                          onPressed: () => setState(
                            () => _obscureSearchCode = !_obscureSearchCode,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isLoadingFamily
                          ? null
                          : () => _fetchAllFamily(moveCamera: true),
                      icon: const Icon(Icons.refresh),
                      label: const Text("عرض الكل", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _mapStatus,
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
                    ),
                  ),
                  FilterChip(
                    label: const Text("تحديث تلقائي"),
                    selected: _isAutoRefresh,
                    selectedColor: Colors.teal.shade700,
                    onSelected: _toggleAutoRefresh,
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _members.isEmpty || _selectedMember == null
              ? const Center(
                  child: Text(
                    "ستظهر جميع هواتف العائلة معاً هنا بعد إدخال الرمز",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: LatLng(
                          _selectedMember!.lat,
                          _selectedMember!.lng,
                        ),
                        initialZoom: 15.0,
                        onMapReady: () => _mapReady = true,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.family.tracker',
                        ),
                        MarkerLayer(
                          markers: _members.map((member) {
                            final isSelected =
                                _selectedMember?.phone == member.phone;
                            return Marker(
                              point: LatLng(member.lat, member.lng),
                              width: 130,
                              height: 80,
                              child: GestureDetector(
                                onTap: () => _selectMember(member),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.amber.shade800
                                            : Colors.black87,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.tealAccent,
                                        ),
                                      ),
                                      child: Text(
                                        member.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.location_pin,
                                      color: isSelected
                                          ? Colors.redAccent
                                          : Colors.tealAccent,
                                      size: isSelected ? 44 : 36,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    Positioned(
                      bottom: 12,
                      left: 10,
                      right: 10,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 62,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _members.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final m = _members[index];
                                final isSelected =
                                    _selectedMember?.phone == m.phone;
                                return GestureDetector(
                                  onTap: () => _selectMember(m),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.indigo.shade700
                                          : const Color(0xFF0F172A),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.amberAccent
                                            : Colors.white24,
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          m.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          m.formattedTime,
                                          style: const TextStyle(
                                            color: Colors.tealAccent,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _openSelectedInGoogleMaps,
                              icon: const Icon(Icons.directions),
                              label: Text(
                                "فتح مسار (${_selectedMember!.name}) في خرائط جوجل",
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocked) {
      return _buildLockScreen();
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("تتبع العائلة", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: _savedPin.isEmpty ? 'تعيين رمز قفل' : 'قفل التطبيق الآن',
              icon: Icon(
                _savedPin.isEmpty ? Icons.lock_open : Icons.lock,
                color: _savedPin.isEmpty ? Colors.white70 : Colors.tealAccent,
              ),
              onPressed: () {
                if (_savedPin.isEmpty) {
                  _showPinSettingsDialog();
                } else {
                  setState(() {
                    _isLocked = true;
                    _unlockPinCtrl.clear();
                    _lockError = '';
                  });
                }
              },
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.tealAccent,
            labelColor: Colors.tealAccent,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.map_outlined), text: "الخريطة"),
              Tab(icon: Icon(Icons.chat_bubble_outline), text: "الدردشة"),
              Tab(icon: Icon(Icons.my_location), text: "موقعي"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildFamilyMapTab(),
            _buildChatTab(),
            _buildShareTab(),
          ],
        ),
      ),
    );
  }
}
