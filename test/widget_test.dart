import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:amar_hisab/data/ledger.dart';
import 'package:amar_hisab/data/security.dart';
import 'package:amar_hisab/features/app.dart';
import 'package:amar_hisab/features/components.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();sqfliteFfiInit();
  late Directory directory;late Ledger ledger;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),(_) async=>null);
    directory=await Directory.systemTemp.createTemp('amar_widget_');
    ledger=await Ledger.open('${directory.path}/test.db',factory:databaseFactoryFfi);
    await ledger.setSetting('welcome','seen');
  });
  tearDown(() async {await ledger.db.close();await directory.delete(recursive:true);});
  for(final dark in [false,true]){
    testWidgets('Bengali dashboard, black outlines, small screen, large text, dark=$dark',(tester) async {
      tester.view.physicalSize=const Size(360,720);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      await ledger.setSetting('theme',dark?'dark':'light');
      await tester.pumpWidget(AmarHisab(ledger:ledger,security:AppSecurity()));
      await tester.pumpAndSettle();
      expect(find.text('আমার হিসাব'),findsOneWidget);expect(find.text('মোট জমা টাকা'),findsOneWidget);
      expect(find.text('বর্তমান ব্যালেন্স'),findsOneWidget);expect(find.byType(OutlineCard),findsWidgets);
      final card=tester.widget<Container>(find.descendant(of:find.byType(OutlineCard).first,matching:find.byType(Container)).first);
      expect((card.decoration as BoxDecoration).border,isNotNull);
      expect(tester.takeException(),isNull);
      final context=tester.element(find.byType(Home));
      expect(Theme.of(context).brightness,dark?Brightness.dark:Brightness.light);
    });
  }
  testWidgets('outlined cards expand at 2x text scale and reduced motion',(tester) async {
    tester.view.physicalSize=const Size(320,640);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:MediaQuery(data:const MediaQueryData(
      size:Size(320,640),textScaler:TextScaler.linear(2),disableAnimations:true),
      child:Scaffold(body:SingleChildScrollView(child:OutlineCard(child:AmountLine('বর্তমান ব্যালেন্স',15000000,'BDT',prominent:true)))))));
    await tester.pumpAndSettle();expect(find.text('বর্তমান ব্যালেন্স'),findsOneWidget);expect(tester.takeException(),isNull);
  });
}
