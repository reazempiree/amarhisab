import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../core/money.dart';
import 'schema.dart';
import 'backup.dart';

String operationKey() {
  final random = Random.secure();
  return List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2,'0')).join();
}

class LedgerException implements Exception {
  final String message;
  const LedgerException(this.message);
  @override
  String toString() => message;
}

class DeletionPreview {
  final String accountId;
  final List<String> operations;
  final List<Map<String, Object?>> transactions;
  final Map<String, int> projected;
  final List<String> affectedAccounts;
  final List<String> blockers;
  const DeletionPreview(this.accountId, this.operations, this.transactions,
      this.projected, this.affectedAccounts, this.blockers);
}

class Ledger {
  final Database db;
  Ledger(this.db);

  static Future<Ledger> open(String path, {DatabaseFactory? factory}) async {
    final database = await (factory ?? databaseFactory).openDatabase(path,
      options: OpenDatabaseOptions(version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys=ON');
          await db.execute('PRAGMA secure_delete=ON');
        }, onCreate: createSchema,
        onUpgrade: (_, old, next) async {
          throw LedgerException('অসমর্থিত ডেটাবেস আপগ্রেড: $old → $next');
        }));
    final ledger = Ledger(database);
    await ledger.integrity();
    return ledger;
  }

  Future<List<Map<String, Object?>>> accounts() => db.rawQuery('''
    SELECT a.*, COALESCE(SUM(p.amount),0) balance FROM accounts a
    LEFT JOIN postings p ON p.account_id=a.id
    WHERE a.kind!='external' GROUP BY a.id ORDER BY a.rowid''');

  Future<int> balance(String account, [DatabaseExecutor? executor]) async {
    final rows = await (executor ?? db).rawQuery(
      'SELECT COALESCE(SUM(amount),0) n FROM postings WHERE account_id=?', [account]);
    return rows.single['n'] as int;
  }

  Future<List<Map<String, Object?>>> history({String? account,int? period}) async {
    final where=<String>[],args=<Object?>[];
    if(account=='agent_payable'||account=='agent_advance') {
      where.add("(o.kind IN ('pk_remittance','agent_payment','agent_refund','cycle_close') OR EXISTS (SELECT 1 FROM postings p WHERE p.operation_id=o.id AND p.account_id IN ('agent_payable','agent_advance')))");
    } else if(account!=null) {
      where.add('EXISTS (SELECT 1 FROM postings p WHERE p.operation_id=o.id AND p.account_id=?)');args.add(account);
    }
    if(period!=null){where.add('o.period_id=?');args.add(period);}
    return db.rawQuery("SELECT o.* FROM operations o ${where.isEmpty?'':'WHERE ${where.join(' AND ')}'} ORDER BY o.occurred DESC,o.sequence DESC",args);
  }

  Future<String?> setting(String key) async {
    final rows = await db.query('settings', where:'key=?', whereArgs:[key]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }
  Future<void> setSetting(String key, String value) async {
    await db.insert('settings', {'key':key,'value':value}, conflictAlgorithm:ConflictAlgorithm.replace);
  }

  Future<void> addAccount(String name, String currency, String role) async {
    if (name.trim().isEmpty || !['AED','BDT','PKR'].contains(currency) ||
        !['bank','cash','receivable','payable'].contains(role)) {
      throw const LedgerException('অ্যাকাউন্টের তথ্য সঠিক নয়');
    }
    await db.insert('accounts', {'id':operationKey(),'name':name.trim(),
      'currency':currency,'kind':role=='payable'?'liability':'asset','role':role});
  }

  Future<void> _perform(String key, String kind, Map<String,Object?> request,
      Future<Map<String,Object?>> Function(Transaction tx, int period, int cycle) action) async {
    if (key.isEmpty) { throw const LedgerException('অপারেশন পরিচয় অনুপস্থিত'); }
    await db.transaction((tx) async {
      final previous = await tx.query('operations',where:'id=?',whereArgs:[key]);
      if (previous.isNotEmpty) {
        final old = jsonDecode(previous.single['data'] as String) as Map;
        if (previous.single['kind'] != kind || jsonEncode(old['request']) != jsonEncode(request)) {
          throw const LedgerException('অপারেশন পরিচয় ইতিমধ্যে ব্যবহৃত');
        }
        return;
      }
      if ((await tx.query('deletion_events',where:'operation_key=?',whereArgs:[key])).isNotEmpty) {
        throw const LedgerException('মুছে ফেলার পরিচয় পুনরায় ব্যবহার করা যাবে না');
      }
      final period = (await tx.query('periods',where:'ended IS NULL')).single['id'] as int;
      final cycle = (await tx.query('cycles',where:'ended IS NULL')).single['id'] as int;
      final now = DateTime.now().toUtc().toIso8601String();
      final sequence=(await tx.rawQuery('SELECT COALESCE(MAX(sequence),0)+1 n FROM operations')).single['n'] as int;
      await tx.insert('operations', {'id':key,'sequence':sequence,'kind':kind,'occurred':request['date']??now,
        'created':now,'period_id':period,'cycle_id':cycle,'note':request['note']??'',
        'data':jsonEncode({'request':request})});
      final result = await action(tx,period,cycle);
      await tx.update('operations',{'data':jsonEncode({'request':request,'result':result})},where:'id=?',whereArgs:[key]);
      await _validate(tx);
    });
  }

  Future<Map<String,Object?>> _account(DatabaseExecutor tx, String id) async {
    final rows = await tx.query('accounts',where:'id=?',whereArgs:[id]);
    if (rows.isEmpty) { throw const LedgerException('অ্যাকাউন্ট পাওয়া যায়নি'); }
    return rows.single;
  }
  Future<void> _post(DatabaseExecutor tx, String key, String account, int amount) async {
    if (amount == 0) { return; }
    if (amount.abs() > 9007199254740991) { throw const LedgerException('পরিমাণ অনেক বড়'); }
    await tx.insert('postings', {'operation_id':key,'account_id':account,'amount':amount});
  }
  Future<void> _asset(DatabaseExecutor tx, String id, {String? currency}) async {
    final a = await _account(tx,id);
    if (a['kind'] != 'asset' || !['bank','principal','profit','cash'].contains(a['role']) || (currency != null && a['currency'] != currency)) {
      throw const LedgerException('সঠিক নগদ বা ব্যাংক অ্যাকাউন্ট বেছে নিন');
    }
  }
  void _positive(int amount) {
    if (amount <= 0) { throw const LedgerException('পরিমাণ শূন্যের বেশি হতে হবে'); }
  }
  Future<void> _dependencies(DatabaseExecutor tx, String key, int cycle) async {
    final rows = await tx.query('operations',columns:['id'],
      where:"cycle_id=? AND id!=? AND kind IN ('pk_remittance','agent_payment','agent_refund')",
      whereArgs:[cycle,key]);
    for (final row in rows) {
      await tx.insert('dependencies',{'operation_id':key,'requires_id':row['id']});
    }
  }

  Future<void> fund(String key, String account, int amount, {String note='', String? date}) {
    return _perform(key,'deposit',{'account':account,'amount':amount,'note':note,'date':date},(tx,_,__) async {
      _positive(amount); await _asset(tx,account);
      final a=await _account(tx,account);
      await _post(tx,key,account,amount);
      await _post(tx,key,'external_${a['currency']}',-amount);
      return {};
    });
  }

  Future<void> adjust(String key, String bank, int target, {String note=''}) {
    return _perform(key,'adjustment',{'account':bank,'target':target,'note':note},(tx,_,__) async {
      final a=await _account(tx,bank);
      if (a['role']!='bank' || a['currency']!='BDT' || target<0) {
        throw const LedgerException('বাংলাদেশ ব্যাংকের সঠিক ব্যালেন্স লিখুন');
      }
      final before=await balance(bank,tx), delta=target-await balance(bank,tx);
      if (delta==0) { throw const LedgerException('ব্যালেন্স অপরিবর্তিত'); }
      await _post(tx,key,bank,delta); await _post(tx,key,'external_BDT',-delta);
      return {'before':before,'difference':delta,'target':target};
    });
  }

  Future<void> expense(String key,String account,int amount,{String note='',String? date,bool withdrawal=false}) {
    return _perform(key,withdrawal?'withdrawal':'expense',{'account':account,'amount':amount,'note':note,'date':date},(tx,_,__) async {
      _positive(amount); await _asset(tx,account);
      final a=await _account(tx,account);
      await _post(tx,key,account,-amount); await _post(tx,key,'external_${a['currency']}',amount);
      return {};
    });
  }

  Future<void> transfer(String key,String from,String to,int amount,{String note=''}) {
    return _perform(key,'transfer',{'from':from,'to':to,'amount':amount,'note':note},(tx,_,__) async {
      _positive(amount); await _asset(tx,from); await _asset(tx,to);
      if (from==to || (await _account(tx,from))['currency'] != (await _account(tx,to))['currency']) {
        throw const LedgerException('একই মুদ্রার আলাদা অ্যাকাউন্ট বেছে নিন');
      }
      await _post(tx,key,from,-amount); await _post(tx,key,to,amount);
      return {};
    });
  }

  Future<void> remittance(String key,{required String country,required int amount,
      required String bankRate,required String customerRate,required int fee,
      String bank='bd_bank', int? agentCommission}) {
    return _perform(key,country=='BD'?'bd_remittance':'pk_remittance',
      {'country':country,'amount':amount,'bankRate':bankRate,'customerRate':customerRate,
        'fee':fee,'bank':bank,'agentCommission':agentCommission},(tx,_,cycle) async {
      if (!['BD','PK'].contains(country)) { throw const LedgerException('দেশ সঠিক নয়'); }
      if (country=='BD' && agentCommission!=null && agentCommission!=0) {
        throw const LedgerException('বাংলাদেশ রেমিট্যান্সে এজেন্ট কমিশন নেই');
      }
      if (country=='PK' && agentCommission==null) {
        throw const LedgerException('প্রথমে এজেন্ট কমিশনের নিয়ম নিশ্চিত করুন');
      }
      var advanceApplied=0;
      final q=RemittanceQuote(amount:amount,bankRate:bankRate,customerRate:customerRate,
        fee:fee,agentCommission:agentCommission??0);
      if (country=='BD') {
        await _asset(tx,bank,currency:'BDT');
        await _post(tx,key,bank,-amount); await _post(tx,key,'external_BDT',amount);
      } else {
        await _dependencies(tx,key,cycle);
        final owed=q.principal+(agentCommission??0);
        final advance=await balance('agent_advance',tx);
        final applied=min(advance,owed); advanceApplied=applied;
        await _post(tx,key,'agent_advance',-applied);
        await _post(tx,key,'agent_payable',-(owed-applied));
      }
      await _post(tx,key,'principal',q.principal+(agentCommission??0));
      await _post(tx,key,'profit',q.profit);
      await _post(tx,key,'external_AED',country=='BD'?-q.collected:-q.profit);
      for (final entry in {'bankRate':bankRate,'customerRate':customerRate,'fee':'${fee ~/ 100}.${(fee % 100).toString().padLeft(2, '0')}'}.entries) {
        await tx.insert('settings',{'key':'${country}_${entry.key}','value':entry.value},conflictAlgorithm:ConflictAlgorithm.replace);
      }
      return {'principal':q.principal,'customer':q.customer,'exchangeProfit':q.exchangeProfit,
        'fee':q.fee,'agentCommission':agentCommission??0,'profit':q.profit,'collected':q.collected,'advanceApplied':advanceApplied};
    });
  }

  Future<void> payAgent(String key,String source,int amount) {
    return _perform(key,'agent_payment',{'source':source,'amount':amount},(tx,_,cycle) async {
      _positive(amount); await _asset(tx,source,currency:'AED');
      if (source=='agent_advance') { throw const LedgerException('নগদ উৎস বেছে নিন'); }
      await _dependencies(tx,key,cycle);
      final payable=-(await balance('agent_payable',tx));
      final paid=min(payable,amount);
      await _post(tx,key,source,-amount); await _post(tx,key,'agent_payable',paid);
      await _post(tx,key,'agent_advance',amount-paid);
      return {'paidPayable':paid,'advanceAdded':amount-paid};
    });
  }

  Future<void> refundAgent(String key,String destination,int amount) {
    return _perform(key,'agent_refund',{'destination':destination,'amount':amount},(tx,_,cycle) async {
      _positive(amount); await _asset(tx,destination,currency:'AED');
      if (destination=='agent_advance') { throw const LedgerException('নগদ গন্তব্য বেছে নিন'); }
      await _dependencies(tx,key,cycle);
      await _post(tx,key,'agent_advance',-amount); await _post(tx,key,destination,amount);
      return {};
    });
  }


  Future<Map<String,int>> agentSummary() async {
    final cycle=(await db.query('cycles',where:'ended IS NULL')).single['id'];
    final rows=await db.query('operations',where:'cycle_id=?',whereArgs:[cycle]);
    final values=<String,int>{'gross':0,'paid':0,'applied':0,'refunds':0};
    void add(Map<String,Object?> row,int sign) {
      final data=jsonDecode(row['data'] as String) as Map;
      final result=(data['result'] as Map?)??{};
      final request=data['request'] as Map;
      if(row['kind']=='pk_remittance') {
        values['gross']=values['gross']!+sign*((result['principal'] as int)+(result['agentCommission'] as int));
        values['applied']=values['applied']!+sign*(result['advanceApplied'] as int);
      } else if(row['kind']=='agent_payment') {
        values['paid']=values['paid']!+sign*(request['amount'] as int);
      } else if(row['kind']=='agent_refund') {
        values['refunds']=values['refunds']!+sign*(request['amount'] as int);
      }
    }
    for(final row in rows) {
      if(row['kind']=='reversal') {
        add((await db.query('operations',where:'id=?',whereArgs:[row['reverses']])).single,-1);
      } else {add(row,1);}
    }
    values['payable']=-(await balance('agent_payable'));
    values['advance']=await balance('agent_advance');
    return values;
  }

  /// General lending/borrowing is separate from completed customer remittances.
  Future<void> obligation(String key,String obligation,String cash,int amount,{required bool settle}) {
    return _perform(key,settle?'obligation_settlement':'obligation_open',
      {'obligation':obligation,'cash':cash,'amount':amount,'settle':settle},(tx,_,__) async {
      _positive(amount);await _asset(tx,cash);
      final account=await _account(tx,obligation),source=await _account(tx,cash);
      if(!['receivable','payable'].contains(account['role'])||account['currency']!=source['currency']) {
        throw const LedgerException('একই মুদ্রার সাধারণ দেনা/পাওনা ও নগদ বেছে নিন');
      }
      final lending=account['role']=='receivable';
      final delta=(lending?1:-1)*(settle?-amount:amount);
      await _post(tx,key,obligation,delta);await _post(tx,key,cash,-delta);
      return {};
    });
  }

  Future<void> closeCycle(String key) {
    return _perform(key,'cycle_close',{},(tx,_,cycle) async {
      if (await balance('agent_payable',tx)!=0 || await balance('agent_advance',tx)!=0) {
        throw const LedgerException('প্রকৃত পাওনা পরিশোধ বা অগ্রিম ফেরত নিন; তারপর নতুন চক্র শুরু করুন');
      }
      await _dependencies(tx,key,cycle);
      final now=DateTime.now().toUtc().toIso8601String();
      await tx.update('cycles',{'ended':now},where:'id=?',whereArgs:[cycle]);
      await tx.insert('cycles',{'started':now});
      return {};
    });
  }

  Future<void> repatriate(String key,String source,String bank,int aed,String rate) {
    return _perform(key,'repatriation',{'source':source,'bank':bank,'amount':aed,'rate':rate},(tx,_,__) async {
      _positive(aed); await _asset(tx,source,currency:'AED'); await _asset(tx,bank,currency:'BDT');
      final parsed=Decimal.parse(rate);
      if (!parsed.positive) { throw const LedgerException('সঠিক রেট লিখুন'); }
      final bdt=parsed.multiplyMinor(aed); _positive(bdt);
      await _post(tx,key,source,-aed); await _post(tx,key,'external_AED',aed);
      await _post(tx,key,bank,bdt); await _post(tx,key,'external_BDT',-bdt);
      return {'bdt':bdt};
    });
  }

  Future<void> closePeriod(String key,{required bool reconciled}) {
    return _perform(key,'period_close',{'reconciled':reconciled},(tx,period,_) async {
      if (!reconciled) { throw const LedgerException('নগদ ও ব্যাংক মিলিয়ে নিশ্চিত করুন'); }
      final cash=await balance('profit',tx);
      await _post(tx,key,'profit',-cash); await _post(tx,key,'principal',cash);
      final summary=await _summary(tx,period:period);
      final balances=await tx.rawQuery('''SELECT a.id,COALESCE(SUM(p.amount),0) balance
        FROM accounts a LEFT JOIN postings p ON a.id=p.account_id GROUP BY a.id''');
      final now=DateTime.now().toUtc().toIso8601String();
      await tx.update('periods',{'ended':now,'summary':jsonEncode({'totals':summary,'balances':balances,'transferredProfit':cash})},where:'id=?',whereArgs:[period]);
      await tx.insert('periods',{'started':now});
      return {'transferredProfit':cash};
    });
  }

  Future<void> reverse(String key,String original) {
    return _perform(key,'reversal',{'original':original},(tx,_,__) async {
      final rows=await tx.rawQuery('''SELECT o.*,p.ended FROM operations o
        JOIN periods p ON p.id=o.period_id WHERE o.id=?''',[original]);
      if (rows.isEmpty || rows.single['ended']!=null ||
          ['period_close','cycle_close','reversal'].contains(rows.single['kind'])) {
        throw const LedgerException('এই লেনদেন বাতিল করা যাবে না; বন্ধ হিসাব অপরিবর্তনীয়');
      }
      final children=await tx.query('dependencies',where:'requires_id=?',whereArgs:[original]);
      if (children.isNotEmpty) { throw const LedgerException('পরবর্তী এজেন্ট লেনদেন আগে নিষ্পত্তি করুন'); }
      await tx.update('operations',{'reverses':original},where:'id=?',whereArgs:[key]);
      final postings=await tx.query('postings',where:'operation_id=?',whereArgs:[original]);
      for (final p in postings) {
        await _post(tx,key,p['account_id'] as String,-(p['amount'] as int));
      }
      await tx.insert('dependencies',{'operation_id':key,'requires_id':original});
      return {'reversed':original};
    });
  }

  Future<Map<String,int>> summary({String? account,DateTime? from,DateTime? until,bool current=false}) async {
    int? period;
    if (current) { period=(await db.query('periods',where:'ended IS NULL')).single['id'] as int; }
    return _summary(db,account:account,from:from,until:until,period:period);
  }
  Future<Map<String,int>> _summary(DatabaseExecutor tx,{String? account,DateTime? from,DateTime? until,int? period}) async {
    final where=<String>[], args=<Object?>[];
    if (period!=null) {where.add('o.period_id=?');args.add(period);}
    if (from!=null) {where.add('o.occurred>=?');args.add(from.toUtc().toIso8601String());}
    if (until!=null) {where.add('o.occurred<?');args.add(until.toUtc().toIso8601String());}
    if (account!=null) {where.add('EXISTS (SELECT 1 FROM postings p WHERE p.operation_id=o.id AND p.account_id=?)');args.add(account);}
    final rows=await tx.rawQuery('SELECT o.* FROM operations o ${where.isEmpty?'':'WHERE ${where.join(' AND ')}'}',args);
    final totals=<String,int>{'funding':0,'remitted':0,'profit':0,'exchangeProfit':0,'fee':0,'agentCommission':0};
    // Reversals affect report metrics in their own period/date; original snapshots stay intact.
    Future<void> accumulate(Map<String,Object?> row,int sign) async {
      final data=jsonDecode(row['data'] as String) as Map;
      final request=data['request'] as Map;
      final result=(data['result'] as Map?)??{};
      final kind=row['kind'];
      if (kind=='deposit' && account!=null && request['account']==account) {
        totals['funding']=totals['funding']!+sign*(request['amount'] as int);
      }
      if (kind=='bd_remittance') { totals['remitted']=totals['remitted']!+sign*(request['amount'] as int); }
      if (kind=='bd_remittance' || kind=='pk_remittance') {
        for (final k in ['profit','exchangeProfit','fee','agentCommission']) {
          totals[k]=totals[k]!+sign*((result[k] as int?)??0);
        }
      }
      if (kind=='expense' || kind=='withdrawal') {
        final a=await _account(tx,request['account'] as String);
        final k='${kind}_${a['currency']}';
        totals[k]=(totals[k]??0)+sign*(request['amount'] as int);
      }
    }
    for (final row in rows) {
      if (row['kind']=='reversal') {
        final original=await tx.query('operations',where:'id=?',whereArgs:[row['reverses']]);
        await accumulate(original.single,-1);
      } else {
        await accumulate(row,1);
      }
    }
    return totals;
  }

  Future<DeletionPreview> previewDeletion(String account, [DatabaseExecutor? executor]) async {
    final tx=executor??db;
    final selected=await _account(tx,account);
    if (selected['kind']=='external') { throw const LedgerException('বহিঃহিসাব মোছা যাবে না'); }
    final agent=account=='agent_payable'||account=='agent_advance';
    final condition=agent
      ? "o.kind='cycle_close' OR EXISTS (SELECT 1 FROM postings q WHERE q.operation_id=o.id AND q.account_id IN ('agent_payable','agent_advance'))"
      : 'EXISTS (SELECT 1 FROM postings q WHERE q.operation_id=o.id AND q.account_id=?)';
    final rows=await tx.rawQuery('''SELECT o.*,p.ended FROM operations o
      JOIN periods p ON p.id=o.period_id WHERE $condition ORDER BY o.occurred''',agent?[]:[account]);
    final ids=rows.map((r)=>r['id'] as String).toList();
    final idSet=ids.toSet(), blockers=<String>[];
    if (rows.any((r)=>r['ended']!=null)) { blockers.add('বন্ধ হিসাবের লেনদেন রয়েছে। নতুন চক্র চালু করলেও বন্ধ হিসাব মোছা যাবে না।'); }
    final dependencies=await tx.query('dependencies');
    if (dependencies.any((d)=>idSet.contains(d['requires_id'])&&!idSet.contains(d['operation_id']))) {
      blockers.add('অন্য অ্যাকাউন্টের পরবর্তী এজেন্ট নিষ্পত্তি বা বাতিল নির্ভর করছে। নির্ভরশীল খোলা লেনদেন আগে সমাধান করুন।');
    }
    final balances=await tx.rawQuery('''SELECT a.id,a.kind,COALESCE(SUM(p.amount),0) balance
      FROM accounts a LEFT JOIN postings p ON p.account_id=a.id GROUP BY a.id''');
    final projected={for(final a in balances) a['id'] as String:a['balance'] as int};
    final affected=<String>{};
    final postings=await tx.query('postings');
    for(final p in postings) {
      if (idSet.contains(p['operation_id'])) {
        final id=p['account_id'] as String; affected.add(id);
        projected[id]=projected[id]!-(p['amount'] as int);
      }
    }
    for(final a in balances) {
      final value=projected[a['id']]!;
      if ((a['kind']=='asset'&&value<0)||(a['kind']=='liability'&&value>0)) {
        blockers.add('${a['id']}: অবশিষ্ট লেনদেনের ব্যালেন্স অসঙ্গত হবে');
      }
    }
    final historical=await tx.rawQuery('''WITH movements AS (
      SELECT a.id,a.kind,o.sequence seq,SUM(p.amount) delta FROM postings p
      JOIN operations o ON o.id=p.operation_id JOIN accounts a ON a.id=p.account_id
      WHERE NOT ($condition)
      GROUP BY a.id,o.sequence), running AS (
      SELECT id,kind,SUM(delta) OVER(PARTITION BY id ORDER BY seq) n FROM movements)
      SELECT id FROM running WHERE (kind='asset' AND n<0) OR (kind='liability' AND n>0) LIMIT 1''',agent?[]:[account]);
    if(historical.isNotEmpty) { blockers.add('অবশিষ্ট পুরোনো লেনদেনে তহবিলের ঘাটতি হবে। সংশ্লিষ্ট পরবর্তী লেনদেন আগে সমাধান করুন।'); }
    return DeletionPreview(account,ids,rows,projected,affected.toList(),blockers);
  }

  /// Caller must pass a capability from BackupService after a real file write,
  /// authenticated decryption, validation and fingerprint comparison.
  Future<void> deleteAccountTransactions(String key,String account,
      {required String confirmation,required VerifiedBackup backup}) async {
    if (confirmation!='DELETE') {
      throw const LedgerException('যাচাইকৃত বর্তমান এনক্রিপ্টেড ব্যাকআপ এবং DELETE প্রয়োজন');
    }
    await db.transaction((tx) async {
      if ((await tx.query('deletion_events',where:'operation_key=?',whereArgs:[key])).isNotEmpty) { return; }
      // Compare the complete state again inside the write lock, protecting the backup gate from races.
      if (jsonEncode(await export(executor:tx))!=backup.snapshot) {
        throw const LedgerException('ব্যাকআপের পরে হিসাব পরিবর্তিত হয়েছে; আবার ব্যাকআপ করুন');
      }
      final preview=await previewDeletion(account,tx);
      if (preview.blockers.isNotEmpty) { throw LedgerException(preview.blockers.join('\n')); }
      for(final id in preview.operations) {
        await tx.delete('dependencies',where:'operation_id=?',whereArgs:[id]);
      }
      // Reversal references must be cleared only for rows being permanently removed.
      for(final id in preview.operations) {
        await tx.update('operations',{'reverses':null},where:'id=?',whereArgs:[id]);
      }
      for(final id in preview.operations) {
        await tx.delete('operations',where:'id=?',whereArgs:[id]);
      }
      await _validate(tx);
      await tx.insert('deletion_events',{'operation_key':key,
        'occurred':DateTime.now().toUtc().toIso8601String(),'count':preview.operations.length});
    });
    await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    await db.execute('VACUUM');
  }

  static const tables=['accounts','periods','cycles','operations','postings','dependencies','settings','deletion_events'];
  Future<Map<String,Object?>> export({DatabaseExecutor? executor}) async {
    final tx=executor??db;
    final result=<String,Object?>{'format':'amar-hisab-fresh','version':schemaVersion};
    for(final table in tables) {
      result[table]=await tx.query(table,orderBy:table=='operations'?'sequence':'rowid');
    }
    return result;
  }

  Future<void> restore(Map<String,Object?> document) async {
    if(document['format']!='amar-hisab-fresh'||document['version']!=schemaVersion) {
      throw const LedgerException('এই ব্যাকআপের ফরম্যাট সমর্থিত নয়; পুরোনো ব্যাকআপ অপরিবর্তিত রাখুন');
    }
    await db.transaction((tx) async {
      // Only restore into a pristine installation; replacing live records is a separate migration task.
      if ((await tx.query('operations',limit:1)).isNotEmpty ||
          (await tx.query('deletion_events',limit:1)).isNotEmpty) {
        throw const LedgerException('পুনরুদ্ধারের জন্য নতুন খালি হিসাব প্রয়োজন; বর্তমান ডেটা মুছবেন না');
      }
      for(final table in tables.reversed) {await tx.delete(table);}
      // Defer self references until the transaction has inserted all rows.
      await tx.execute('PRAGMA defer_foreign_keys=ON');
      for(final table in tables) {
        final rows=document[table];
        if (rows is! List) { throw const LedgerException('ব্যাকআপ অসম্পূর্ণ'); }
        for(final row in rows) {await tx.insert(table,Map<String,Object?>.from(row as Map));}
      }
      if ((await tx.query('periods',where:'ended IS NULL')).length!=1 ||
          (await tx.query('cycles',where:'ended IS NULL')).length!=1) {
        throw const LedgerException('ব্যাকআপে খোলা হিসাব সঠিক নয়');
      }
      final expected={for(final a in initialAccounts) a['id']:a};
      for(final id in expected.keys) {
        final a=await _account(tx,id as String);
        if(a['currency']!=expected[id]!['currency']||a['kind']!=expected[id]!['kind']||a['role']!=expected[id]!['role']) {
          throw const LedgerException('ব্যাকআপের মূল অ্যাকাউন্ট পরিবর্তিত');
        }
      }
      await _validate(tx);
      if((await tx.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) { throw const LedgerException('ব্যাকআপে সংযোগ ত্রুটি'); }
    });
  }

  Future<void> integrity() async {
    final result=await db.rawQuery('PRAGMA integrity_check');
    if(result.single.values.single!='ok' || (await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw const LedgerException('ডেটাবেস যাচাই ব্যর্থ। ডেটা মুছবেন না; ব্যাকআপ সংরক্ষণ করুন।');
    }
    await _validate(db);
  }

  Future<void> _validate(DatabaseExecutor tx) async {
    final unbalanced=await tx.rawQuery('''SELECT p.operation_id,a.currency,SUM(p.amount) n
      FROM postings p JOIN accounts a ON a.id=p.account_id
      GROUP BY p.operation_id,a.currency HAVING n!=0''');
    if(unbalanced.isNotEmpty) { throw const LedgerException('লেনদেনের দুই দিক সমান নয়'); }
    final invalid=await tx.rawQuery('''SELECT a.id,a.kind,SUM(p.amount) n FROM accounts a
      JOIN postings p ON p.account_id=a.id GROUP BY a.id
      HAVING (a.kind='asset' AND n<0) OR (a.kind='liability' AND n>0) OR ABS(n)>9007199254740991''');
    if(invalid.isNotEmpty) { throw const LedgerException('পর্যাপ্ত ব্যালেন্স নেই অথবা অবৈধ পাওনা'); }
    final historical=await tx.rawQuery('''WITH movements AS (
      SELECT a.id,a.kind,o.sequence seq,SUM(p.amount) delta FROM postings p
      JOIN operations o ON o.id=p.operation_id JOIN accounts a ON a.id=p.account_id
      GROUP BY a.id,o.sequence), running AS (
      SELECT id,kind,SUM(delta) OVER(PARTITION BY id ORDER BY seq) n FROM movements)
      SELECT id FROM running WHERE (kind='asset' AND n<0) OR (kind='liability' AND n>0) LIMIT 1''');
    if(historical.isNotEmpty) { throw const LedgerException('পুরোনো লেনদেনের তহবিল অসঙ্গত'); }
    final remittances=await tx.query('operations',where:"kind IN ('bd_remittance','pk_remittance')");
    for(final op in remittances) {
      final payload=jsonDecode(op['data'] as String) as Map;
      final r=payload['request'] as Map, result=payload['result'] as Map;
      final isBd=op['kind']=='bd_remittance';
      final commission=(r['agentCommission'] as int?)??0;
      if(!isBd&&r['agentCommission']==null || isBd&&commission!=0) {
        throw const LedgerException('কমিশন স্ন্যাপশট সঠিক নয়');
      }
      final q=RemittanceQuote(amount:r['amount'] as int,bankRate:r['bankRate'] as String,
        customerRate:r['customerRate'] as String,fee:r['fee'] as int,agentCommission:commission);
      for(final metric in <String,int>{'principal':q.principal,'customer':q.customer,
          'exchangeProfit':q.exchangeProfit,'fee':q.fee,'profit':q.profit,
          'collected':q.collected,'agentCommission':commission}.entries) {
        if(result[metric.key]!=metric.value) { throw const LedgerException('রেমিট্যান্সের হিসাব স্ন্যাপশট সঠিক নয়'); }
      }
      final expected=<String,int>{'principal':q.principal+commission,'profit':q.profit};
      if(isBd) {
        expected[r['bank'] as String]=-(r['amount'] as int);
        expected['external_BDT']=r['amount'] as int;expected['external_AED']=-q.collected;
      } else {
        final applied=result['advanceApplied'] as int;
        if(applied<0||applied>q.principal+commission){ throw const LedgerException('অগ্রিম স্ন্যাপশট সঠিক নয়'); }
        expected['agent_advance']=-applied;expected['agent_payable']=-(q.principal+commission-applied);
        expected['external_AED']=-q.profit;
      }
      expected.removeWhere((_,value)=>value==0);
      final actualRows=await tx.rawQuery('SELECT account_id,SUM(amount) amount FROM postings WHERE operation_id=? GROUP BY account_id',[op['id']]);
      final actual={for(final p in actualRows)p['account_id'] as String:p['amount'] as int};
      if(actual.length!=expected.length||expected.entries.any((e)=>actual[e.key]!=e.value)) {
        throw const LedgerException('রেমিট্যান্সের পোস্টিং সঠিক নয়');
      }
    }
  }
}
