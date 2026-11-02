import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'ledger.dart';

class AppSecurity {
  final FlutterSecureStorage storage;
  AppSecurity({this.storage=const FlutterSecureStorage()});
  Future<bool> get enabled async => await storage.read(key:'pin_record')!=null;
  Future<void> configure(String pin) async {
    if(!RegExp(r'^\d{6,12}$').hasMatch(pin)) { throw const LedgerException('৬–১২ সংখ্যার PIN দিন'); }
    final salt=SecretKeyData.random(length:16).bytes;
    final key=await Pbkdf2(macAlgorithm:Hmac.sha256(),iterations:210000,bits:256)
      .deriveKey(secretKey:SecretKey(utf8.encode(pin)),nonce:salt);
    await storage.write(key:'pin_record',value:jsonEncode({'version':1,
      'salt':base64Encode(salt),'hash':base64Encode(await key.extractBytes())}));
    await storage.delete(key:'pin_attempts');
    await storage.delete(key:'pin_locked_until');
  }
  Future<bool> check(String pin) async {
    final until=DateTime.tryParse(await storage.read(key:'pin_locked_until')??'');
    if(until!=null&&DateTime.now().toUtc().isBefore(until)) {
      throw const LedgerException('অনেকবার ভুল PIN। কিছুক্ষণ পরে চেষ্টা করুন');
    }
    final stored=await storage.read(key:'pin_record');
    if(stored==null) { return false; }
    final record=jsonDecode(stored) as Map;
    final hash=record['hash'] as String,salt=record['salt'] as String;
    final key=await Pbkdf2(macAlgorithm:Hmac.sha256(),iterations:210000,bits:256)
      .deriveKey(secretKey:SecretKey(utf8.encode(pin)),nonce:base64Decode(salt));
    final bytes=await key.extractBytes(), expected=base64Decode(hash);
    var diff=bytes.length^expected.length;
    for(var i=0;i<bytes.length&&i<expected.length;i++) {diff|=bytes[i]^expected[i];}
    if(diff==0) {
      await storage.delete(key:'pin_attempts');
      await storage.delete(key:'pin_locked_until'); return true;
    }
    final attempts=int.tryParse(await storage.read(key:'pin_attempts')??'0')??0;
    await storage.write(key:'pin_attempts',value:'${attempts+1}');
    if(attempts+1>=5) {
      await storage.write(key:'pin_locked_until',value:DateTime.now().toUtc().add(const Duration(seconds:30)).toIso8601String());
    }
    return false;
  }
  Future<bool> biometric() async {
    try {
      return await LocalAuthentication().authenticate(localizedReason:'আমার হিসাব খুলুন',
        options:const AuthenticationOptions(biometricOnly:true));
    } catch (_) {return false;}
  }
}
