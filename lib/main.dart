import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'data/ledger.dart';
import 'data/security.dart';
import 'features/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final ledger=await Ledger.open(p.join(await getDatabasesPath(),'amar_hisab_fresh.db'));
    runApp(AmarHisab(ledger:ledger,security:AppSecurity()));
  } catch(_,stack) {
    // No exception payload: SQL driver messages may contain financial values.
    debugPrint('Amar Hisab startup failed\n$stack');
    runApp(const MaterialApp(home:Scaffold(body:SafeArea(child:Padding(
      padding:EdgeInsets.all(28),child:Center(child:Text(
        'হিসাব খোলা যায়নি।\nডেটা মুছবেন না বা অ্যাপ আনইনস্টল করবেন না।\nআপনার ব্যাকআপ সংরক্ষণ করুন এবং সহায়তা নিন।',
        textAlign:TextAlign.center)))))));
  }
}
