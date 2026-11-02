import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'ledger.dart';

class VerifiedBackup {
  final String snapshot;
  final String path;
  final DateTime verifiedAt;
  VerifiedBackup._(this.snapshot,this.path,this.verifiedAt);
}

class BackupService {
  static const maxBytes=50*1024*1024;
  final cipher=AesGcm.with256bits();
  final derivation=Pbkdf2(macAlgorithm:Hmac.sha256(),iterations:210000,bits:256);

  Future<SecretKey> _key(String password,List<int> salt) async {
    if(password.length<10) { throw const LedgerException('কমপক্ষে ১০ অক্ষরের ব্যাকআপ পাসওয়ার্ড দিন'); }
    return derivation.deriveKey(secretKey:SecretKey(utf8.encode(password)),nonce:salt);
  }
  Future<List<int>> encrypt(Map<String,Object?> document,String password) async {
    final salt=SecretKeyData.random(length:16).bytes;
    final box=await cipher.encrypt(utf8.encode(jsonEncode(document)),
      secretKey:await _key(password,salt),aad:utf8.encode('amar-hisab-backup-v1'));
    return utf8.encode(jsonEncode({'format':'amar-hisab-encrypted','version':1,
      'kdf':'PBKDF2-HMAC-SHA256-210000','salt':base64Encode(salt),
      'nonce':base64Encode(box.nonce),'ciphertext':base64Encode(box.cipherText),
      'mac':base64Encode(box.mac.bytes)}));
  }
  Future<Map<String,Object?>> decrypt(List<int> bytes,String password) async {
    if(bytes.length>maxBytes) { throw const LedgerException('ব্যাকআপ অনেক বড়'); }
    try {
      final envelope=jsonDecode(utf8.decode(bytes)) as Map;
      if(envelope['format']!='amar-hisab-encrypted'||envelope['version']!=1||
          envelope['kdf']!='PBKDF2-HMAC-SHA256-210000') {
        throw const LedgerException('অজানা ব্যাকআপ ফরম্যাট; পুরোনো ডেটা মুছবেন না');
      }
      final salt=base64Decode(envelope['salt'] as String);
      final nonce=base64Decode(envelope['nonce'] as String);
      final mac=base64Decode(envelope['mac'] as String);
      if(salt.length!=16||nonce.length!=12||mac.length!=16) { throw const FormatException(); }
      final box=SecretBox(base64Decode(envelope['ciphertext'] as String),nonce:nonce,mac:Mac(mac));
      final clear=await cipher.decrypt(box,secretKey:await _key(password,salt),aad:utf8.encode('amar-hisab-backup-v1'));
      final data=Map<String,Object?>.from(jsonDecode(utf8.decode(clear)) as Map);
      if(data['format']!='amar-hisab-fresh'||data['version']!=1) { throw const FormatException(); }
      return data;
    } on LedgerException {rethrow;} catch (_) {
      throw const LedgerException('পাসওয়ার্ড ভুল অথবা ব্যাকআপ ক্ষতিগ্রস্ত');
    }
  }
  Future<VerifiedBackup> verifyFile(String path,String password,Map<String,Object?> snapshot) async {
    final file=File(path);
    if(await file.length()>maxBytes) { throw const LedgerException('ব্যাকআপ অনেক বড়'); }
    final restored=await decrypt(await file.readAsBytes(),password);
    final canonical=jsonEncode(snapshot);
    if(jsonEncode(restored)!=canonical) { throw const LedgerException('ব্যাকআপ যাচাই ব্যর্থ'); }
    return VerifiedBackup._(canonical,path,DateTime.now().toUtc());
  }
  Future<void> restoreFile(Ledger ledger,String path,String password) async {
    final file=File(path);
    if(await file.length()>maxBytes) { throw const LedgerException('ব্যাকআপ অনেক বড়'); }
    await ledger.restore(await decrypt(await file.readAsBytes(),password));
  }
}
