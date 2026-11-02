import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../core/money.dart';
import '../data/backup.dart';
import '../data/ledger.dart';
import '../data/security.dart';
import 'components.dart';
import 'controller.dart';
import 'remittance.dart';

const kindLabels={
  'deposit':'জমা','adjustment':'ব্যালেন্স সংশোধন','expense':'ব্যক্তিগত খরচ',
  'withdrawal':'উত্তোলন','transfer':'অভ্যন্তরীণ স্থানান্তর','bd_remittance':'বাংলাদেশে পাঠানো',
  'pk_remittance':'পাকিস্তানে পাঠানো','agent_payment':'এজেন্টকে পরিশোধ',
  'agent_refund':'এজেন্টের অগ্রিম ফেরত','cycle_close':'এজেন্ট চক্র নিষ্পত্তি',
  'obligation_open':'সাধারণ দেনা/পাওনা','obligation_settlement':'দেনা/পাওনা নিষ্পত্তি',
  'period_close':'হিসাব বন্ধ','repatriation':'দেশে মূলধন ফেরত','reversal':'লেনদেন বাতিল',
};

class AmarHisab extends StatefulWidget {
  final Ledger ledger;
  final AppSecurity security;
  const AmarHisab({super.key,required this.ledger,required this.security});
  @override
  State<AmarHisab> createState()=>_AmarHisabState();
}
class _AmarHisabState extends State<AmarHisab> {
  ThemeMode mode=ThemeMode.system;
  @override
  void initState(){super.initState();loadTheme();}
  Future<void> loadTheme() async {
    final saved=await widget.ledger.setting('theme');
    if(mounted){ setState(()=>mode=ThemeMode.values.firstWhere((v)=>v.name==saved,orElse:()=>ThemeMode.system)); }
  }
  ThemeData theme(Brightness brightness) {
    final dark=brightness==Brightness.dark;
    final colors=ColorScheme.fromSeed(seedColor:Colors.grey,brightness:brightness).copyWith(
      primary:dark?Colors.white:const Color(0xff191919),
      onPrimary:dark?Colors.black:Colors.white,
      surface:dark?const Color(0xff202020):Colors.white);
    return ThemeData(useMaterial3:true,brightness:brightness,colorScheme:colors,
      fontFamily:'NotoSerifBengali',scaffoldBackgroundColor:dark?const Color(0xff111111):const Color(0xfff5f4f0),
      inputDecorationTheme:InputDecorationTheme(border:OutlineInputBorder(borderRadius:BorderRadius.circular(14)),
        enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(14),borderSide:BorderSide(color:dark?Colors.white70:Colors.black87))),
      filledButtonTheme:FilledButtonThemeData(style:FilledButton.styleFrom(padding:const EdgeInsets.symmetric(horizontal:20,vertical:15))),
      segmentedButtonTheme:SegmentedButtonThemeData(style:ButtonStyle(
        backgroundColor:WidgetStateProperty.resolveWith((states)=>states.contains(WidgetState.selected)?const Color(0xff191919):colors.surface),
        foregroundColor:WidgetStateProperty.resolveWith((states)=>states.contains(WidgetState.selected)?Colors.white:colors.onSurface),
        side:WidgetStatePropertyAll(BorderSide(color:dark?Colors.white70:Colors.black87)))),
      appBarTheme:const AppBarTheme(backgroundColor:Colors.transparent,scrolledUnderElevation:0));
  }
  @override
  Widget build(BuildContext context)=>MaterialApp(title:'আমার হিসাব',debugShowCheckedModeBanner:false,
    theme:theme(Brightness.light),darkTheme:theme(Brightness.dark),themeMode:mode,
    builder:(context,child)=>PrivacyGate(security:widget.security,child:child??const SizedBox.shrink()),
    home:Home(ledger:widget.ledger,security:widget.security,mode:mode,onTheme:(v) async {
      await widget.ledger.setSetting('theme',v.name);if(mounted){ setState(()=>mode=v); }
    }));
}

class Home extends StatefulWidget {
  final Ledger ledger;
  final AppSecurity security;
  final ThemeMode mode;
  final Future<void> Function(ThemeMode) onTheme;
  const Home({super.key,required this.ledger,required this.security,required this.mode,required this.onTheme});
  @override
  State<Home> createState()=>_HomeState();
}
class _HomeState extends State<Home> with WidgetsBindingObserver {
  late final controller=LedgerController(widget.ledger);
  bool loaded=false,locked=true,lockEnabled=false,unlocking=false;
  String? failure,accountFilter;
  int page=0;
  int? periodFilter;
  String country='BD',search='';
  final backupService=BackupService();
  @override
  void initState(){super.initState();WidgetsBinding.instance.addObserver(this);initialize();}
  Future<void> initialize() async {
    try {
      await controller.refresh(); lockEnabled=await widget.security.enabled;
      if(!mounted){ return; }
      setState((){loaded=true;locked=false;});
      if(!locked){ await initialPrompt(); }
    }catch(_,stack){debugPrint('Initialization failed\n$stack');if(mounted){ setState(()=>failure='হিসাব পড়া যায়নি। ডেটা মুছবেন না।'); }}
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // PrivacyGate protects the complete Navigator, including modal routes.
  }
  @override
  void dispose(){WidgetsBinding.instance.removeObserver(this);controller.dispose();super.dispose();}
  void message(String text){if(mounted){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text))); }}
  Future<bool> run(Future<void> Function() action) async {
    try {
      await controller.mutate(action);
      return true;
    } catch(e,stack) {
      debugPrint('Ledger action failed\n$stack');
      message(e is LedgerException||e is FormatException?e.toString():'কাজটি সম্পন্ন হয়নি। হিসাব আবার যাচাই করুন।');
      return false;
    } finally {
      if(mounted){setState((){});}
    }
  }
  Future<void> initialPrompt() async {
    if(await widget.ledger.setting('welcome')!=null){ return; }
    if(!mounted){ return; }
    await widget.ledger.setSetting('welcome','seen');
    if(!mounted){ return; }
    final restore=await confirm(context,'আমার হিসাবে স্বাগতম','আগের যাচাইকৃত Amar Hisab Fresh এনক্রিপ্টেড ব্যাকআপ পুনরুদ্ধার করবেন? অজানা পুরোনো অ্যাপের ব্যাকআপ এখন সমর্থিত নয়। ফিরলে নতুন খালি হিসাব ব্যবহার করতে পারবেন।');
    if(restore){ await restoreBackup(); }
  }
  Future<bool> authenticate() async {
    if(!await widget.security.enabled){ return true; }
    if(!mounted){ return false; }
    var ok=false;
    await showDialog<void>(context:context,barrierDismissible:false,builder:(context)=>EntryDialog(
      title:'হিসাব খুলুন',action:'PIN যাচাই করুন',fields:const [FieldSpec('pin','আপনার PIN',secret:true,numeric:true)],
      submit:(v,_) async {if(!await widget.security.check(latinDigits(v['pin']!))){ throw const LedgerException('PIN সঠিক নয়'); }ok=true;}));
    return ok;
  }
  Future<void> unlock({bool biometric=false}) async {
    if(unlocking){ return; }
    unlocking=true;
    try {final ok=biometric?await widget.security.biometric():await authenticate();
      if(ok&&mounted){setState(()=>locked=false);await initialPrompt();}}
    finally{unlocking=false;}
  }
  Map<String,String> choices({String? currency,bool banks=false})=>{
    for(final a in controller.accounts.where((a)=>a['kind']=='asset'&&a['role']!='advance'&&a['role']!='receivable'&&
      (currency==null||a['currency']==currency)&&(!banks||a['role']=='bank')))
      a['id'] as String:'${a['name']} · ${money(a['balance'] as int,a['currency'] as String)}',
  };
  Future<void> entry(String title,List<FieldSpec> fields,
      Future<void> Function(Map<String,String>,String?) action,{Map<String,String>? options,String? initial,String? warning}) async {
    await showDialog<bool>(context:context,barrierDismissible:false,builder:(context)=>EntryDialog(
      title:title,fields:fields,choices:options,initialChoice:initial,warning:warning,
      submit:(v,c)=>controller.mutate(()=>action(v,c))));
    if(mounted){ setState((){}); }
  }
  Future<void> deposit({String? account}) async {
    final key=operationKey();
    await entry('টাকা জমা',[const FieldSpec('amount','পরিমাণ',numeric:true),const FieldSpec('note','বিবরণ (ঐচ্ছিক)')],
      (v,c)=>widget.ledger.fund(key,c!,Decimal.parse(v['amount']!).minor(),note:v['note']!),
      options:choices(),initial:account??'bd_bank');
  }
  Future<void> expense({bool withdrawal=false}) async {
    final key=operationKey();
    await entry(withdrawal?'টাকা উত্তোলন':'ব্যক্তিগত খরচ',[
      const FieldSpec('amount','পরিমাণ',numeric:true),const FieldSpec('note','বিভাগ / বিবরণ (ঐচ্ছিক)')],
      (v,c)=>widget.ledger.expense(key,c!,Decimal.parse(v['amount']!).minor(),note:v['note']!,withdrawal:withdrawal),
      options:choices(),initial:country=='BD'?'bd_bank':'principal');
  }
  Future<void> adjustment(Map<String,Object?> a) async {
    final key=operationKey();
    await showDialog<void>(context:context,builder:(context)=>BalanceAdjustment(
      account:a,save:(target,note)=>controller.mutate(()=>widget.ledger.adjust(key,a['id'] as String,target,note:note))));
    if(mounted){ setState((){}); }
  }
  Future<void> agentPayment({bool refund=false}) async {
    final key=operationKey();
    await entry(refund?'অগ্রিম ফেরত নিন':'এজেন্টকে পরিশোধ করুন',[
      const FieldSpec('amount','প্রকৃত AED পরিমাণ',numeric:true)],
      (v,c)=>refund?widget.ledger.refundAgent(key,c!,Decimal.parse(v['amount']!).minor()):
        widget.ledger.payAgent(key,c!,Decimal.parse(v['amount']!).minor()),options:choices(currency:'AED'),initial:'principal',
      warning:refund?'শুধু প্রকৃত ফেরত পাওয়া অর্থ লিখুন।':'নগদ উৎস থেকে একবার কাটবে। পাওনার অতিরিক্ত অংশ এজেন্টের কাছে আপনার অগ্রিম থাকবে।');
  }
  Future<void> transfer() async {
    String? from;
    await entry('স্থানান্তরের উৎস',const [],(v,c) async {from=c;},options:choices());
    if(from==null||!mounted){ return; }
    final a=controller.accounts.firstWhere((a)=>a['id']==from);
    final destinations=choices(currency:a['currency'] as String)..remove(from);
    if(destinations.isEmpty){message('একই মুদ্রার আরেকটি অ্যাকাউন্ট যোগ করুন');return;}
    final key=operationKey();
    await entry('স্থানান্তরের গন্তব্য',const [FieldSpec('amount','পরিমাণ',numeric:true),FieldSpec('note','বিবরণ')],
      (v,c)=>widget.ledger.transfer(key,from!,c!,Decimal.parse(v['amount']!).minor(),note:v['note']!),options:destinations);
  }
  Future<void> repatriate() async {
    final key=operationKey();
    await entry('লাভের নগদ বাংলাদেশে ফেরত',const [FieldSpec('amount','প্রকৃত AED পরিমাণ',numeric:true),
      FieldSpec('rate','BDT / AED রেট',numeric:true)],
      (v,c)=>widget.ledger.repatriate(key,'profit',c!,Decimal.parse(v['amount']!).minor(),v['rate']!),
      options:choices(currency:'BDT',banks:true),warning:'লাভের নগদ থেকে AED কাটবে এবং নির্বাচিত ব্যাংকে প্রকৃত BDT জমা হবে। এটি নতুন আয় নয়।');
  }
  Future<VerifiedBackup?> exportBackup() async {
    VerifiedBackup? receipt;
    await entry('এনক্রিপ্টেড ব্যাকআপ',const [FieldSpec('password','নতুন ব্যাকআপ পাসওয়ার্ড (১০+ অক্ষর)',secret:true),
      FieldSpec('repeat','পাসওয়ার্ড আবার লিখুন',secret:true)],(v,_) async {
      if(v['password']!=v['repeat']){ throw const LedgerException('দুটি পাসওয়ার্ড মিলছে না'); }
      // Reminder is included in the authenticated snapshot and restored with it.
      final previousBackup=await widget.ledger.setting('last_backup');
      await widget.ledger.setSetting('last_backup',DateTime.now().toUtc().toIso8601String());
      try {
      final snapshot=await widget.ledger.db.transaction((tx)=>widget.ledger.export(executor:tx));
      final bytes=await backupService.encrypt(snapshot,v['password']!);
      final path=await FilePicker.platform.saveFile(dialogTitle:'ব্যাকআপ কোথায় রাখবেন?',
        fileName:'amar-hisab-${DateTime.now().millisecondsSinceEpoch}.ahbackup',bytes:Uint8List.fromList(bytes));
      if(path==null){ throw const LedgerException('ব্যাকআপ সংরক্ষণ হয়নি'); }
      receipt=await backupService.verifyFile(path,v['password']!,snapshot);
      } catch(_) {
        if(previousBackup==null) {
          await widget.ledger.db.delete('settings',where:'key=?',whereArgs:['last_backup']);
        } else {await widget.ledger.setSetting('last_backup',previousBackup);}
        rethrow;
      }
    },warning:'পাসওয়ার্ড নিরাপদে রাখুন। হারিয়ে গেলে ব্যাকআপ খোলা যাবে না। ফাইল পুনরায় পড়ে যাচাই করা হবে।');
    if(receipt!=null){ message('এনক্রিপ্টেড ব্যাকআপ সংরক্ষিত ও যাচাইকৃত'); }
    return receipt;
  }
  Future<void> restoreBackup() async {
    final selected=await FilePicker.platform.pickFiles(type:FileType.any);
    final path=selected?.files.single.path;
    if(path==null||!mounted){ return; }
    await entry('ব্যাকআপ পুনরুদ্ধার',const [FieldSpec('password','ব্যাকআপ পাসওয়ার্ড',secret:true)],
      (v,_)=>backupService.restoreFile(widget.ledger,path,v['password']!),
      warning:'শুধু খালি নতুন হিসাবে পুনরুদ্ধার হবে। বর্তমান লেনদেন বা পুরোনো অ্যাপের ডেটা মুছে প্রতিস্থাপন করা হবে না।');
  }
  Future<void> erase(Map<String,Object?> account) async {
    final preview=await widget.ledger.previewDeletion(account['id'] as String);
    if(!mounted){ return; }
    final details='${account['name']}\nলেনদেন: ${bengali('${preview.operations.length}')}\n'
      '${preview.transactions.isEmpty?'': '${preview.transactions.first['occurred']} → ${preview.transactions.last['occurred']}'}\n'
      'ধরন: ${preview.transactions.map((t)=>kindLabels[t['kind']]??t['kind']).toSet().join(', ')}\n'
      'প্রভাবিত অ্যাকাউন্ট ও পরবর্তী ব্যালেন্স:\n${preview.affectedAccounts.where((a)=>!a.startsWith('external_')).map((id){
        final a=controller.accounts.firstWhere((a)=>a['id']==id);
        return '${a['name']}: ${money(preview.projected[id]!,a['currency'] as String)}';}).join('\n')}\n\n'
      'সম্পূর্ণ সংযুক্ত লেনদেন ও সব পোস্টিং মুছে যাবে। পুরোনো বাহ্যিক ব্যাকআপ মুছবে না; পুনরুদ্ধার করলে লেনদেন ফিরে আসতে পারে।';
    if(preview.blockers.isNotEmpty){await confirm(context,'মুছে ফেলা বন্ধ আছে','$details\n\n${preview.blockers.join('\n')}');return;}
    if(preview.operations.isEmpty){message('মোছার মতো লেনদেন নেই');return;}
    if(!await confirm(context,'স্থায়ীভাবে মুছে ফেলার পূর্বরূপ',details)){ return; }
    if(!await authenticate()||!mounted){ return; }
    final backup=await exportBackup();
    if(backup==null||!mounted){ return; }
    final key=operationKey();
    await entry('স্থায়ীভাবে মুছে ফেলুন',const [FieldSpec('confirm','নিশ্চিত করতে DELETE লিখুন')],
      (v,_)=>widget.ledger.deleteAccountTransactions(key,account['id'] as String,confirmation:v['confirm']!,backup:backup),
      warning:'যাচাইকৃত ব্যাকআপ তৈরি হয়েছে। এই কাজ ফেরানো যাবে না।');
  }
  Future<void> closePeriod() async {
    final profit=controller.balance('profit');
    if(!await confirm(context,'হিসাব বন্ধ করুন',
      'ব্যাংক, নগদ ও এজেন্টের হিসাব মিলিয়ে নিয়েছেন?\n'
      'অবশিষ্ট লাভের নগদ ${money(profit,'AED')} মূলধনে স্থানান্তর হবে। মোট নগদ অপরিবর্তিত থাকবে।\n'
      'আগে নথিভুক্ত খরচ আবার লিখবেন না। নগদ হাতে রাখলে মূলধনে যাবে; দেশে পাঠাতে হলে আগে প্রকৃত ফেরত লেনদেন করুন।\n'
      'অপরিশোধিত এজেন্ট পাওনা বহাল থাকবে। বন্ধ হিসাবের লেনদেন আর মুছতে বা বাতিল করতে পারবেন না।')){ return; }
    if(!await authenticate()){ return; }
    if(await run(()=>widget.ledger.closePeriod(operationKey(),reconciled:true))) {
      message('নতুন হিসাব শুরু হয়েছে');
    }
  }
  Future<void> archives() async {
    final periods=await widget.ledger.db.query('periods',where:'ended IS NOT NULL',orderBy:'id DESC');
    if(!mounted){ return; }
    await Navigator.push(context,MaterialPageRoute<void>(builder:(context)=>Scaffold(appBar:AppBar(title:const Text('বন্ধ করা হিসাবসমূহ')),
      body:ListView(padding:const EdgeInsets.all(20),children:[
        if(periods.isEmpty)const Text('এখনও কোনো হিসাব বন্ধ হয়নি'),
        for(final period in periods)OutlineCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('হিসাব ${bengali('${period['id']}')}',style:Theme.of(context).textTheme.titleLarge),
          Text('${period['started']}\n${period['ended']}'),
          AmountLine('অর্জিত লাভ',((jsonDecode(period['summary'] as String) as Map)['totals'] as Map)['profit'] as int,'AED'),
          AmountLine('বিনিময় লাভ',((jsonDecode(period['summary'] as String) as Map)['totals'] as Map)['exchangeProfit'] as int,'AED'),
          AmountLine('সার্ভিস ফি',((jsonDecode(period['summary'] as String) as Map)['totals'] as Map)['fee'] as int,'AED'),
          for(final closing in ((jsonDecode(period['summary'] as String) as Map)['balances'] as List).cast<Map>().where((b)=>!('${b['id']}').startsWith('external_')))
            AmountLine('বন্ধের সময় ${controller.accountName(closing['id'] as String)}',closing['balance'] as int,
              controller.accounts.firstWhere((a)=>a['id']==closing['id'])['currency'] as String),
          TextButton(onPressed:(){Navigator.pop(context);setState((){page=1;accountFilter=null;periodFilter=period['id'] as int;search='';});},child:const Text('লেনদেনের ইতিহাস দেখুন')),
        ])),
      ]))));
  }
  Future<void> more() async {
    await showModalBottomSheet<void>(context:context,showDragHandle:true,isScrollControlled:true,
      builder:(context)=>SafeArea(child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(final item in <(String,Future<void> Function())>[
          ('অভ্যন্তরীণ স্থানান্তর',transfer),('টাকা উত্তোলন',()=>expense(withdrawal:true)),
          ('লাভ বাংলাদেশে ফেরত',repatriate),('এজেন্টকে পরিশোধ',()=>agentPayment()),
          ('এজেন্টের অগ্রিম ফেরত',()=>agentPayment(refund:true)),('হিসাব বন্ধ করুন',closePeriod),
        ])ListTile(title:Text(item.$1),trailing:const Icon(Icons.arrow_forward),onTap:(){Navigator.pop(context);item.$2();}),
      ]))));
  }
  void accountHistory(String id){setState((){accountFilter=id;periodFilter=null;page=1;search='';});}
  Widget dashboard() {
    final banks=controller.accounts.where((a)=>a['role']=='bank'&&a['currency']=='BDT').toList();
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('আপনার অর্থ, আপনার নিয়ন্ত্রণে',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),
      const SizedBox(height:6),const Text('অফলাইনে সুরক্ষিত • প্রতিটি টাকার হিসাব'),const SizedBox(height:24),
      SegmentedButton<String>(segments:const [ButtonSegment(value:'BD',label:Text('বাংলাদেশ')),ButtonSegment(value:'AE',label:Text('সংযুক্ত আরব আমিরাত'))],
        selected:{country},onSelectionChanged:(s)=>setState(()=>country=s.single)),const SizedBox(height:20),
      if(country=='BD')SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        for(final a in banks)SizedBox(width:(MediaQuery.sizeOf(context).width-40).clamp(240.0,440.0),child:Padding(
          padding:const EdgeInsets.only(right:8),child:OutlineCard(black:true,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[Expanded(child:Text(a['name'] as String,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),
              IconButton(tooltip:'ব্যাংকের ব্যালেন্স সংশোধন করুন',onPressed:()=>adjustment(a),icon:const Icon(Icons.edit_outlined))]),
            AmountLine('মোট জমা টাকা',controller.bankTotals[a['id']]?['funding']??0,'BDT'),
            const Divider(color:Colors.white38),
            InkWell(onTap:()=>accountHistory(a['id'] as String),child:AmountLine('বর্তমান ব্যালেন্স',a['balance'] as int,'BDT',prominent:true)),
            AmountLine('রেমিট্যান্সে ব্যবহৃত',controller.bankTotals[a['id']]?['remitted']??0,'BDT'),
            AmountLine('ব্যক্তিগত খরচ',controller.bankTotals[a['id']]?['expense_BDT']??0,'BDT'),
          ])))),
      ])),
      if(country=='AE')OutlineCard(black:true,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('দিরহাম • নগদের অবস্থান',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        InkWell(onTap:()=>accountHistory('principal'),child:AmountLine('মূলধন নগদ',controller.balance('principal'),'AED',prominent:true)),
        const Divider(color:Colors.white38),
        InkWell(onTap:()=>accountHistory('profit'),child:AmountLine('হাতে থাকা লাভ',controller.balance('profit'),'AED')),
        AmountLine('অন্যান্য নগদ',controller.balance('reserve'),'AED'),
        AmountLine('চলতি হিসাবে অর্জিত লাভ',controller.current['profit']??0,'AED'),
      ])),
      Wrap(spacing:10,runSpacing:10,children:[
        FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>RemittanceScreen(controller:controller,
          initialCountry:country=='BD'?'BD':'PK'))).then((_){if(mounted){ setState((){}); }}),icon:const Icon(Icons.north_east),label:const Text('পাঠানো')),
        OutlinedButton.icon(onPressed:()=>deposit(account:country=='BD'?'bd_bank':'principal'),icon:const Icon(Icons.add),label:const Text('জমা')),
        OutlinedButton.icon(onPressed:()=>expense(),icon:const Icon(Icons.south_east),label:const Text('খরচ')),
        OutlinedButton.icon(onPressed:more,icon:const Icon(Icons.more_horiz),label:const Text('আরও')),
      ]),const SizedBox(height:24),
      Row(children:[Expanded(child:Text('সাম্প্রতিক লেনদেন',style:Theme.of(context).textTheme.titleLarge)),TextButton(onPressed:()=>setState(()=>page=1),child:const Text('সব দেখুন'))]),
      if(controller.history.isEmpty)const OutlineCard(child:Text('এখনও কোনো লেনদেন নেই। প্রথমে ব্যাংকের প্রকৃত জমা লিখুন।')),
      for(final row in controller.history.take(4))transactionCard(row),
    ]);
  }
  Widget transactionCard(Map<String,Object?> row) {
    final data=jsonDecode(row['data'] as String) as Map;
    final req=data['request'] as Map,result=(data['result'] as Map?)??{};
    final kind=row['kind'] as String;
    final currency=kind=='bd_remittance'?'BDT':kind=='pk_remittance'?'PKR':
      (controller.accounts.where((a)=>a['id']==(req['account']??req['from']??req['cash']??req['source']??req['destination'])).firstOrNull?['currency'] as String?)??'AED';
    return OutlineCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:Text(kindLabels[kind]??kind,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:17))),
        PopupMenuButton<String>(tooltip:'লেনদেনের বিকল্প',onSelected:(value) async {
          if(value=='receipt') {
            await SharePlus.instance.share(ShareParams(text:'আমার হিসাব\n${kindLabels[kind]}\n${row['occurred']}\n'
              '${req['amount'] is int?money(req['amount'] as int,currency):''}\n'
              '${result['profit'] is int?'লাভ: ${money(result['profit'] as int,'AED')}':''}\nপরিচয়: ${row['id']}'));
          } else if(value=='audit') {
            final postings=await widget.ledger.db.rawQuery('''SELECT a.name,a.currency,p.amount FROM postings p JOIN accounts a ON a.id=p.account_id WHERE p.operation_id=?''',[row['id']]);
            if(!mounted){ return; }
            await confirm(context,'অডিট / রেট স্ন্যাপশট','পরিচয়: ${row['id']}\nসংরক্ষণ: ${row['created']}\n'
              'হিসাব: ${row['period_id']}\nএজেন্ট চক্র: ${row['cycle_id']}\n'
              '${req['bankRate']!=null?'ব্যাংক রেট: ${bengali('${req['bankRate']}')}\nগ্রাহক রেট: ${bengali('${req['customerRate']}')}\n':''}'
              '${postings.map((p)=>'${p['name']}: ${money(p['amount'] as int,p['currency'] as String)}').join('\n')}');
          } else if(await confirm(context,'লেনদেন বাতিল করুন','মূল লেনদেন অডিটে থাকবে এবং বিপরীত পোস্টিং হবে। সংশোধন করতে আগে বাতিল করে নতুন সঠিক লেনদেন লিখুন।')) {
            await run(()=>widget.ledger.reverse(operationKey(),row['id'] as String));
          }
        },itemBuilder:(_)=>const [PopupMenuItem(value:'receipt',child:Text('রসিদ শেয়ার')),PopupMenuItem(value:'audit',child:Text('অডিট দেখুন')),PopupMenuItem(value:'reverse',child:Text('বাতিল / সংশোধন'))]),
      ]),
      Text(bengali((DateTime.tryParse(row['occurred'] as String)?.toLocal().toString()??'').split('.').first),style:const TextStyle(fontSize:12)),
      if(req['amount'] is int)AmountLine('পরিমাণ',req['amount'] as int,currency),
      if(result['difference'] is int)AmountLine('সংশোধনের পার্থক্য',result['difference'] as int,'BDT'),
      if(result['profit'] is int)AmountLine('অর্জিত লাভ',result['profit'] as int,'AED'),
      if(req['bankRate']!=null)Text('ব্যাংক ${bengali('${req['bankRate']}')} • গ্রাহক ${bengali('${req['customerRate']}')}'),
      if((row['note'] as String).isNotEmpty)Text(row['note'] as String),
    ]));
  }
  Widget history() {
    var rows=controller.history;
    if(accountFilter!=null||periodFilter!=null) {
      // The authoritative account query is loaded by HistoryList, never inferred from UI fields.
      return HistoryList(ledger:widget.ledger,account:accountFilter,period:periodFilter,
        name:accountFilter==null?'হিসাব ${bengali('$periodFilter')}':controller.accountName(accountFilter!),
        clear:()=>setState((){accountFilter=null;periodFilter=null;}),card:transactionCard);
    }
    if(search.isNotEmpty){ rows=rows.where((r)=>('${kindLabels[r['kind']]} ${r['note']} ${r['occurred']}').contains(search)).toList(); }
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('লেনদেন',style:Theme.of(context).textTheme.headlineMedium),const SizedBox(height:16),
      TextField(decoration:const InputDecoration(labelText:'ধরন, তারিখ বা বিবরণ খুঁজুন',prefixIcon:Icon(Icons.search)),onChanged:(v)=>setState(()=>search=v)),
      const SizedBox(height:16),DropdownButtonFormField<String>(decoration:const InputDecoration(labelText:'অ্যাকাউন্ট অনুযায়ী দেখুন'),
        items:controller.accounts.map((a)=>DropdownMenuItem(value:a['id'] as String,child:Text(a['name'] as String))).toList(),
        onChanged:(v)=>setState(()=>accountFilter=v)),const SizedBox(height:20),
      if(rows.isEmpty)const Text('কোনো লেনদেন পাওয়া যায়নি'),for(final row in rows)transactionCard(row),
    ]);
  }
  Widget accounts() =>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[Expanded(child:Text('অ্যাকাউন্ট',style:Theme.of(context).textTheme.headlineMedium)),IconButton(tooltip:'নতুন অ্যাকাউন্ট',onPressed:() async {
      await entry('নতুন অ্যাকাউন্ট',const [FieldSpec('name','নাম')],
        (v,c)=>widget.ledger.addAccount(v['name']!,c!.split(':')[0],c.split(':')[1]),options:{
          'BDT:bank':'বাংলাদেশ ব্যাংক • BDT','AED:cash':'দিরহাম নগদ • AED','PKR:cash':'পাকিস্তান নগদ • PKR',
          'AED:receivable':'সাধারণ পাওনা • AED','AED:payable':'সাধারণ দেনা • AED',
          'BDT:receivable':'সাধারণ পাওনা • BDT','BDT:payable':'সাধারণ দেনা • BDT'});
    },icon:const Icon(Icons.add_circle_outline))]),const SizedBox(height:20),
    for(final a in controller.accounts)OutlineCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Row(children:[Expanded(child:Text(a['name'] as String,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),
        if(a['role']=='bank'&&a['currency']=='BDT')IconButton(tooltip:'ব্যাংকের ব্যালেন্স সংশোধন করুন',onPressed:()=>adjustment(a),icon:const Icon(Icons.edit_outlined))]),
      InkWell(onTap:()=>accountHistory(a['id'] as String),child:AmountLine(a['kind']=='liability'?'অপরিশোধিত পাওনা':'বর্তমান ব্যালেন্স',
        a['kind']=='liability'?-(a['balance'] as int):a['balance'] as int,a['currency'] as String,prominent:true)),
      if(a['id']=='agent_payable')...[
        AmountLine('চলতি চক্রে মোট পাওনা',controller.agent['gross']??0,'AED'),
        AmountLine('প্রকৃত পরিশোধ',controller.agent['paid']??0,'AED'),
        AmountLine('ব্যবহৃত অগ্রিম',controller.agent['applied']??0,'AED'),
        AmountLine('অগ্রিম ফেরত',controller.agent['refunds']??0,'AED'),
        AmountLine('এজেন্টের কাছে অগ্রিম',controller.balance('agent_advance'),'AED'),
        AmountLine('নিট অবস্থান (পাওনা বাদে অগ্রিম)',controller.balance('agent_advance')+controller.balance('agent_payable'),'AED'),
        Wrap(spacing:8,children:[OutlinedButton(onPressed:()=>agentPayment(),child:const Text('পরিশোধ')),
          OutlinedButton(onPressed:()=>agentPayment(refund:true),child:const Text('অগ্রিম ফেরত'))]),
        TextButton(onPressed:() async {
          if(await confirm(context,'এজেন্টের সকল হিসাব নিষ্পত্তি করুন','প্রকৃত পাওনা ও অগ্রিম উভয় শূন্য হলেই নতুন চক্র হবে। ইতিহাস থাকবে। আগে পরিশোধ বা অগ্রিম ফেরত নিন।')) {
            await run(()=>widget.ledger.closeCycle(operationKey()));
          }
        },child:const Text('এজেন্টের সকল হিসাব নিষ্পত্তি করুন')),
      ],
      if(['receivable','payable'].contains(a['role']))Wrap(spacing:8,children:[
        for(final settle in [false,true])OutlinedButton(onPressed:() async {
          final key=operationKey();
          await entry(settle?'সাধারণ দেনা/পাওনা নিষ্পত্তি':'সাধারণ দেনা/পাওনা শুরু',const [FieldSpec('amount','প্রকৃত পরিমাণ',numeric:true)],
            (v,c)=>widget.ledger.obligation(key,a['id'] as String,c!,Decimal.parse(v['amount']!).minor(),settle:settle),
            options:choices(currency:a['currency'] as String),warning:'এটি গ্রাহক-বাকির রেমিট্যান্স নয়। নির্বাচিত নগদ উৎসে প্রকৃত চলাচল হবে।');
        },child:Text(settle?'নিষ্পত্তি':'শুরু')),
      ]),
      const Divider(),TextButton.icon(onPressed:()=>erase(a),icon:Icon(Icons.delete_forever_outlined,color:Theme.of(context).colorScheme.error),
        label:Text('সকল লেনদেন স্থায়ীভাবে মুছে ফেলুন',style:TextStyle(color:Theme.of(context).colorScheme.error))),
    ])),
  ]);
  Widget settings()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Text('সেটিংস',style:Theme.of(context).textTheme.headlineMedium),const SizedBox(height:20),
    OutlineCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('আপনার পছন্দ',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:16),
      DropdownButtonFormField<ThemeMode>(initialValue:widget.mode,decoration:const InputDecoration(labelText:'থিম'),
        items:const [DropdownMenuItem(value:ThemeMode.system,child:Text('ডিভাইস অনুযায়ী')),DropdownMenuItem(value:ThemeMode.light,child:Text('সাদা')),DropdownMenuItem(value:ThemeMode.dark,child:Text('কালো'))],
        onChanged:(v){if(v!=null){ widget.onTheme(v); }}),
      TextButton.icon(icon:const Icon(Icons.lock_outline),label:Text(lockEnabled?'PIN পরিবর্তন করুন':'PIN সুরক্ষা চালু করুন'),onPressed:() async {
        if(!await authenticate()||!mounted){ return; }
        await entry('PIN সুরক্ষা',const [FieldSpec('pin','নতুন PIN (৬–১২ সংখ্যা)',secret:true,numeric:true),FieldSpec('repeat','PIN আবার লিখুন',secret:true,numeric:true)],(v,_) async {
          if(v['pin']!=v['repeat']){ throw const LedgerException('PIN মিলছে না'); }
          await widget.security.configure(latinDigits(v['pin']!));lockEnabled=true;
        },warning:'PIN ভুলে গেলে খোলা যাবে না। আগে এনক্রিপ্টেড ব্যাকআপ রাখুন।');
      }),
    ])),
    OutlineCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('ব্যাকআপ ও নিরাপত্তা',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      FutureBuilder<String?>(future:widget.ledger.setting('last_backup'),builder:(_,s){
        final last=DateTime.tryParse(s.data??'');
        final due=last==null||DateTime.now().toUtc().difference(last).inDays>=7;
        return Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(due?'ব্যাকআপের সময় হয়েছে • প্রতি ৭ দিনে ব্যাকআপ রাখুন':'শেষ ব্যাকআপ: ${bengali(last.toLocal().toString().split('.').first)}'));
      }),
      FilledButton.icon(onPressed:exportBackup,icon:const Icon(Icons.save_alt),label:const Text('এনক্রিপ্টেড ব্যাকআপ তৈরি করুন')),
      TextButton(onPressed:restoreBackup,child:const Text('ব্যাকআপ পুনরুদ্ধার করুন')),
      const Text('Google Drive স্বয়ংক্রিয় ব্যাকআপ বা স্বয়ংক্রিয় আপডেট নেই। নিজের নিরাপদ স্থানে ব্যাকআপ রাখুন।'),
    ])),
    OutlineCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      FilledButton(onPressed:closePeriod,child:const Text('হিসাব বন্ধ করুন')),
      TextButton(onPressed:archives,child:const Text('বন্ধ করা হিসাবসমূহ')),
      const Text('Amar Hisab Fresh • ০.১.০\nপুরোনো অ্যাপের ব্যাকআপ ফরম্যাট যাচাই করা হয়নি। পুরোনো অ্যাপ আনইনস্টল বা ডেটা মুছবেন না।'),
    ])),
  ]);
  @override
  Widget build(BuildContext context) {
    if(failure!=null){ return Scaffold(body:SafeArea(child:Center(child:Text(failure!)))); }
    if(!loaded){ return const Scaffold(body:Center(child:CircularProgressIndicator())); }
    if(locked){ return Scaffold(body:SafeArea(child:Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.lock_outline,size:48),const SizedBox(height:20),const Text('আমার হিসাব',style:TextStyle(fontSize:30,fontWeight:FontWeight.bold)),
      const SizedBox(height:24),FilledButton(onPressed:()=>unlock(),child:const Text('PIN দিয়ে খুলুন')),
      TextButton(onPressed:()=>unlock(biometric:true),child:const Text('আঙুলের ছাপ দিয়ে খুলুন')),
    ]))))); }
    final reduced=MediaQuery.disableAnimationsOf(context);
    return ListenableBuilder(listenable:controller,builder:(context,_)=>Scaffold(
      appBar:AppBar(title:const Text('আমার হিসাব',style:TextStyle(fontWeight:FontWeight.w800)),
        actions:[const Padding(padding:EdgeInsets.only(right:18),child:Tooltip(message:'ডেটা এই ডিভাইসে থাকে',child:Icon(Icons.cloud_off_outlined)))]),
      body:SafeArea(child:AbsorbPointer(absorbing:controller.busy,child:AnimatedSwitcher(
        duration:Duration(milliseconds:reduced?0:220),child:SingleChildScrollView(key:ValueKey(page),padding:const EdgeInsets.fromLTRB(20,12,20,24),
          child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:680),child:switch(page){
            0=>dashboard(),1=>history(),2=>accounts(),3=>Reports(ledger:widget.ledger),_=>settings(),
          })))))),
      bottomNavigationBar:SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(12,4,12,10),child:OutlineCard(
        padding:const EdgeInsets.all(6),child:Row(children:[
          for(final tab in <(IconData,String)>[(Icons.home_outlined,'হোম'),(Icons.receipt_long_outlined,'লেনদেন'),
            (Icons.account_balance_wallet_outlined,'অ্যাকাউন্ট'),(Icons.bar_chart_outlined,'রিপোর্ট'),(Icons.tune,'সেটিংস')])
            Expanded(child:InkWell(borderRadius:BorderRadius.circular(18),onTap:()=>setState(()=>page=[Icons.home_outlined,Icons.receipt_long_outlined,
              Icons.account_balance_wallet_outlined,Icons.bar_chart_outlined,Icons.tune].indexOf(tab.$1)),
              child:Builder(builder:(context){final selected=page==[Icons.home_outlined,Icons.receipt_long_outlined,
                Icons.account_balance_wallet_outlined,Icons.bar_chart_outlined,Icons.tune].indexOf(tab.$1);
                return Container(padding:const EdgeInsets.symmetric(vertical:10,horizontal:2),decoration:BoxDecoration(
                  color:selected?Theme.of(context).colorScheme.primary:null,borderRadius:BorderRadius.circular(18)),child:Column(mainAxisSize:MainAxisSize.min,children:[
                    Icon(tab.$1,color:selected?Theme.of(context).colorScheme.onPrimary:null),const SizedBox(height:5),
                    Text(tab.$2,textAlign:TextAlign.center,style:TextStyle(fontSize:10,color:selected?Theme.of(context).colorScheme.onPrimary:null)),
                  ]));}))),
        ])))),
    ));
  }
}

class BalanceAdjustment extends StatefulWidget {
  final Map<String,Object?> account;
  final Future<void> Function(int,String) save;
  const BalanceAdjustment({super.key,required this.account,required this.save});
  @override
  State<BalanceAdjustment> createState()=>_BalanceAdjustmentState();
}
class _BalanceAdjustmentState extends State<BalanceAdjustment> {
  late final target=TextEditingController(text:'${(widget.account['balance'] as int)~/100}.${((widget.account['balance'] as int)%100).toString().padLeft(2,'0')}');
  final note=TextEditingController();
  bool busy=false;
  String? error;
  @override
  void dispose(){target.dispose();note.dispose();super.dispose();}
  @override
  Widget build(BuildContext context) {
    int? difference;try{difference=Decimal.parse(target.text).minor()-(widget.account['balance'] as int);}catch(_){}
    return PopScope(canPop:!busy,child:AlertDialog(title:const Text('ব্যাংকের ব্যালেন্স সংশোধন করুন'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(widget.account['name'] as String),AmountLine('প্রকৃত বর্তমান ব্যালেন্স',widget.account['balance'] as int,'BDT'),
        TextField(controller:target,onChanged:(_)=>setState((){}),enabled:!busy,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'সঠিক লক্ষ্য ব্যালেন্স')),
        if(difference!=null)AmountLine('সংশোধনের পার্থক্য',difference,'BDT'),
        TextField(controller:note,enabled:!busy,decoration:const InputDecoration(labelText:'কারণ (ঐচ্ছিক)')),
        const SizedBox(height:12),const Text('অডিটে সংশোধন থাকবে। মোট জমা, লাভ বা খরচ বাড়বে না।'),
        if(error!=null)Text(error!),
      ])),actions:[TextButton(onPressed:busy?null:()=>Navigator.pop(context),child:const Text('ফিরে যান')),
        FilledButton(onPressed:busy?null:() async {
          setState(()=>busy=true);
          try{await widget.save(Decimal.parse(target.text).minor(),note.text);if(context.mounted){ Navigator.pop(context); }}
          catch(e){if(mounted){ setState((){busy=false;error=e.toString();}); }}
        },child:const Text('নিশ্চিত ও সংরক্ষণ'))]));
  }
}

class HistoryList extends StatefulWidget {
  final Ledger ledger;
  final String? account;
  final int? period;
  final String name;
  final VoidCallback clear;
  final Widget Function(Map<String,Object?>) card;
  const HistoryList({super.key,required this.ledger,this.account,this.period,required this.name,required this.clear,required this.card});
  @override
  State<HistoryList> createState()=>_HistoryListState();
}
class _HistoryListState extends State<HistoryList> {
  @override
  Widget build(BuildContext context)=>FutureBuilder<List<Map<String,Object?>>>(
    future:widget.ledger.history(account:widget.account,period:widget.period),builder:(context,s)=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text(widget.name,style:Theme.of(context).textTheme.headlineSmall),TextButton(onPressed:widget.clear,child:const Text('সব লেনদেন দেখুন')),
      if(s.hasError)const Text('ইতিহাস পড়া যায়নি') else if(!s.hasData)const CircularProgressIndicator()
      else if(s.data!.isEmpty)const Text('কোনো লেনদেন নেই') else for(final row in s.data!)widget.card(row),
    ]));
}

class Reports extends StatefulWidget {
  final Ledger ledger;
  const Reports({super.key,required this.ledger});
  @override
  State<Reports> createState()=>_ReportsState();
}
class _ReportsState extends State<Reports> {
  String range='month';DateTimeRange? custom;
  String? account;
  Future<Map<String,int>> load() async {
    final now=DateTime.now(),today=DateTime(DateTime.now().year,DateTime.now().month,DateTime.now().day);
    final from=switch(range){'today'=>today,'week'=>today.subtract(Duration(days:today.weekday-1)),
      'month'=>DateTime(now.year,now.month,1),'custom'=>custom?.start,_=>null};
    final until=range=='custom'?custom?.end.add(const Duration(days:1)):null;
    return widget.ledger.summary(account:account,from:from,until:until,current:range=='current');
  }
  @override
  Widget build(BuildContext context)=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Text('রিপোর্ট',style:Theme.of(context).textTheme.headlineMedium),const SizedBox(height:16),
    DropdownButtonFormField<String>(initialValue:range,decoration:const InputDecoration(labelText:'সময়সীমা'),items:const [
      DropdownMenuItem(value:'today',child:Text('আজ')),DropdownMenuItem(value:'week',child:Text('এই সপ্তাহ')),
      DropdownMenuItem(value:'month',child:Text('এই মাস')),DropdownMenuItem(value:'current',child:Text('চলতি হিসাব')),
      DropdownMenuItem(value:'all',child:Text('সকল হিসাব')),DropdownMenuItem(value:'custom',child:Text('নিজস্ব তারিখ'))],
      onChanged:(v) async {
        if(v=='custom') {
          final selected=await showDateRangePicker(context:context,firstDate:DateTime(2000),lastDate:DateTime.now(),initialDateRange:custom);
          if(selected==null){ return; }custom=selected;
        }
        if(mounted){ setState(()=>range=v!); }
      }),const SizedBox(height:16),
    FutureBuilder<List<Map<String,Object?>>>(future:widget.ledger.accounts(),builder:(context,s)=>DropdownButtonFormField<String>(
      initialValue:account??'',decoration:const InputDecoration(labelText:'উৎস / অ্যাকাউন্ট'),items:[const DropdownMenuItem(value:'',child:Text('সব উৎস')),
        for(final a in s.data??<Map<String,Object?>>[])DropdownMenuItem(value:a['id'] as String,child:Text(a['name'] as String))],
      onChanged:(v)=>setState(()=>account=v==''?null:v))),const SizedBox(height:20),
    FutureBuilder<Map<String,int>>(future:load(),builder:(context,s){
      if(s.hasError){ return const Text('রিপোর্ট পড়া যায়নি'); }
      if(!s.hasData){ return const Center(child:CircularProgressIndicator()); }
      final totals=s.data!;
      return OutlineCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        AmountLine('বিনিময় লাভ (এজেন্ট কমিশনের আগে)',totals['exchangeProfit']??0,'AED'),
        AmountLine('সার্ভিস ফি',totals['fee']??0,'AED'),AmountLine('এজেন্ট কমিশন (নিজের আয় নয়)',totals['agentCommission']??0,'AED'),
        const Divider(),AmountLine('নিজের অর্জিত লাভ',totals['profit']??0,'AED',prominent:true),
        for(final currency in ['BDT','AED','PKR'])AmountLine('ব্যক্তিগত খরচ',totals['expense_$currency']??0,currency),
        for(final currency in ['BDT','AED','PKR'])AmountLine('উত্তোলন',totals['withdrawal_$currency']??0,currency),
        const Text('এটি অর্জিত আয়ের রিপোর্ট। হাতে থাকা নগদ জানতে অ্যাকাউন্ট দেখুন। মুদ্রাগুলো আলাদাভাবে দেখানো হয়েছে।'),
      ]));
    }),
  ]);
}

/// Covers the complete Navigator so modal routes cannot expose financial data
/// while the app is locked. PIN/biometric prompts never share financial rows.
class PrivacyGate extends StatefulWidget {
  final AppSecurity security;
  final Widget child;
  const PrivacyGate({super.key,required this.security,required this.child});
  @override
  State<PrivacyGate> createState()=>_PrivacyGateState();
}
class _PrivacyGateState extends State<PrivacyGate> with WidgetsBindingObserver {
  bool initialized=false,locked=true,busy=false;
  String? error;
  final pin=TextEditingController();
  @override
  void initState(){super.initState();WidgetsBinding.instance.addObserver(this);check();}
  Future<void> check() async {
    try {
      final enabled=await widget.security.enabled;
      if(mounted){ setState((){initialized=true;locked=enabled;}); }
    }catch(_){if(mounted){ setState((){initialized=true;locked=true;error='নিরাপত্তা তথ্য পড়া যায়নি। ডেটা মুছবেন না।';}); }}
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if(state==AppLifecycleState.paused&&!busy) {
      // Obscure immediately, then resolve whether a configured PIN is required.
      setState(()=>locked=true);check();
    }
  }
  Future<void> unlock(bool biometric) async {
    if(busy){ return; }setState((){busy=true;error=null;});
    try {
      final ok=biometric?await widget.security.biometric():await widget.security.check(latinDigits(pin.text));
      if(mounted){ setState((){locked=!ok;if(!ok){ error='পরিচয় যাচাই হয়নি'; }}); }
      if(ok){ pin.clear(); }
    }catch(e){if(mounted){ setState(()=>error=e is LedgerException?e.message:'পরিচয় যাচাই করা যায়নি'); }}
    finally{if(mounted){ setState(()=>busy=false); }}
  }
  @override
  void dispose(){WidgetsBinding.instance.removeObserver(this);pin.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>Stack(children:[
    ExcludeSemantics(excluding:locked||!initialized,child:IgnorePointer(ignoring:locked||!initialized,child:widget.child)),
    if(locked||!initialized)Positioned.fill(child:Material(color:Theme.of(context).scaffoldBackgroundColor,
      child:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(28),child:ConstrainedBox(
        constraints:const BoxConstraints(maxWidth:420),child:!initialized?const Center(child:CircularProgressIndicator()):
        Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          const Icon(Icons.lock_outline,size:48),const SizedBox(height:20),
          const Text('আমার হিসাব',textAlign:TextAlign.center,style:TextStyle(fontSize:30,fontWeight:FontWeight.bold)),
          const SizedBox(height:24),TextField(controller:pin,obscureText:true,enabled:!busy,
            keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'আপনার PIN'),onSubmitted:(_)=>unlock(false)),
          const SizedBox(height:16),FilledButton(onPressed:busy?null:()=>unlock(false),child:const Text('PIN দিয়ে খুলুন')),
          TextButton(onPressed:busy?null:()=>unlock(true),child:const Text('আঙুলের ছাপ দিয়ে খুলুন')),
          if(error!=null)Text(error!,textAlign:TextAlign.center),
        ]))))))),
  ]);
}
