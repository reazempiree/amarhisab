import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:amar_hisab/data/ledger.dart';
import 'package:amar_hisab/data/backup.dart';

void main(){
  sqfliteFfiInit();
  late Ledger ledger;
  late Directory directory;
  setUp(() async {directory=await Directory.systemTemp.createTemp('amar_test_');
    ledger=await Ledger.open('${directory.path}/ledger.db',factory:databaseFactoryFfi);});
  tearDown(() async {await ledger.db.close();await directory.delete(recursive:true);});
  Future<void> bd(String key,{int amount=3400000})=>ledger.remittance(key,country:'BD',amount:amount,bankRate:'34.50',customerRate:'34',fee:500);
  Future<void> pk(String key,{int amount=15200000,int commission=0})=>ledger.remittance(key,country:'PK',amount:amount,bankRate:'76',customerRate:'75.5',fee:500,agentCommission:commission);
  Future<VerifiedBackup> backup() async {
    final service=BackupService();final snapshot=await ledger.export();
    final file=File('${directory.path}/backup.ahbackup');
    await file.writeAsBytes(await service.encrypt(snapshot,'secure-test-password'),flush:true);
    return service.verifyFile(file.path,'secure-test-password',snapshot);
  }
  test('fresh installation has zero balances and valid schema',() async {
    expect((await ledger.accounts()).length,6);expect(await ledger.balance('bd_bank'),0);await ledger.integrity();
  });
  test('funded remittance saves once, separates principal and profit',() async {
    await ledger.fund('fund','bd_bank',10000000);await bd('send');await bd('send');
    expect(await ledger.balance('bd_bank'),6600000);expect(await ledger.balance('principal'),98551);
    expect(await ledger.balance('profit'),1949);expect((await ledger.history()).length,2);
    final totals=await ledger.summary(account:'bd_bank');expect(totals['funding'],10000000);expect(totals['remitted'],3400000);
    expect(()=>bd('send',amount:100000),throwsA(isA<LedgerException>()));
  });
  test('insufficient funds rolls back all postings and saved defaults',() async {
    final before=jsonEncode(await ledger.export());await expectLater(bd('send'),throwsA(isA<LedgerException>()));
    expect(jsonEncode(await ledger.export()),before);
  });
  test('repeated bank adjustments preserve funding and reverse with audit',() async {
    await ledger.fund('fund','bd_bank',13050000);await ledger.adjust('a1','bd_bank',15000000);
    await ledger.adjust('a2','bd_bank',16000000);expect(await ledger.balance('bd_bank'),16000000);
    expect((await ledger.summary(account:'bd_bank'))['funding'],13050000);
    await ledger.reverse('reverse','a2');expect(await ledger.balance('bd_bank'),15000000);
    await expectLater(ledger.reverse('again','a2'),throwsA(anything));
  });
  test('expenses and transfers do not reduce earned profit',() async {
    await ledger.fund('fund','bd_bank',10000000);await bd('send');
    await ledger.expense('expense','profit',500);await ledger.transfer('move','principal','reserve',10000);
    expect(await ledger.balance('profit'),1449);expect((await ledger.summary())['profit'],1949);
    expect(await ledger.balance('reserve'),10000);
    await expectLater(ledger.transfer('invalid','principal','bd_bank',100),throwsA(isA<LedgerException>()));
  });
  test('agent 2000 payable, 2100 payment, 100 advance applies once',() async {
    await ledger.fund('reserve','reserve',10000);await pk('pk1');
    expect(await ledger.balance('agent_payable'),-200000);
    await ledger.transfer('cash','reserve','principal',10000);
    await ledger.payAgent('pay','principal',210000);await ledger.payAgent('pay','principal',210000);
    expect(await ledger.balance('agent_payable'),0);expect(await ledger.balance('agent_advance'),10000);
    await pk('pk2',amount:3800000);await pk('pk2',amount:3800000);
    expect(await ledger.balance('agent_advance'),0);expect(await ledger.balance('agent_payable'),-40000);
    final relationship=await ledger.previewDeletion('agent_advance');
    expect(relationship.operations,containsAll(['pk1','pay','pk2']));
    expect(relationship.blockers,isEmpty);
    await expectLater(ledger.reverse('blocked','pk1'),throwsA(isA<LedgerException>()));
    await ledger.payAgent('pay2','principal',40000);await ledger.closeCycle('cycle');await ledger.closeCycle('cycle');
    expect((await ledger.db.query('cycles',where:'ended IS NULL')).length,1);
  });
  test('unfunded agent overpayment fails; advance refund and reversal persist',() async {
    await expectLater(ledger.payAgent('no','principal',1),throwsA(isA<LedgerException>()));
    await ledger.fund('fund','reserve',210000);await ledger.payAgent('pay','reserve',210000);
    expect(await ledger.balance('agent_advance'),210000);
    await ledger.refundAgent('refund','reserve',10000);expect(await ledger.balance('agent_advance'),200000);
    await ledger.reverse('undo','refund');expect(await ledger.balance('agent_advance'),210000);
    await expectLater(ledger.closeCycle('close'),throwsA(isA<LedgerException>()));
  });
  test('PK requires an explicit commission rule result',() async {
    await expectLater(ledger.remittance('pk',country:'PK',amount:100000,bankRate:'76',customerRate:'75.5',fee:500),throwsA(isA<LedgerException>()));
  });
  test('closing period moves actual remaining profit, carries agent debt',() async {
    await ledger.fund('fund','bd_bank',10000000);await bd('send');await pk('pk');
    await ledger.expense('spent','profit',500);
    final before=await ledger.balance('principal')+await ledger.balance('profit');
    final earned=(await ledger.summary())['profit'];
    await ledger.closePeriod('close',reconciled:true);await ledger.closePeriod('close',reconciled:true);
    expect(await ledger.balance('profit'),0);expect(await ledger.balance('principal'),before);
    expect((await ledger.summary(current:true))['profit'],0);expect((await ledger.summary())['profit'],earned);
    expect(await ledger.balance('agent_payable'),-200000);
    expect((await ledger.db.query('periods',where:'ended IS NOT NULL')).length,1);
    expect((await ledger.previewDeletion('bd_bank')).blockers,isNotEmpty);
  });
  test('permanent deletion deletes complete transactions across accounts',() async {
    await ledger.fund('fund','bd_bank',10000000);await bd('send');
    await ledger.fund('unrelated','reserve',5000);
    final preview=await ledger.previewDeletion('bd_bank');expect(preview.operations.length,2);
    final receipt=await backup();await ledger.deleteAccountTransactions('erase','bd_bank',confirmation:'DELETE',backup:receipt);
    expect(await ledger.balance('bd_bank'),0);expect(await ledger.balance('principal'),0);expect(await ledger.balance('profit'),0);
    expect(await ledger.balance('reserve'),5000);expect((await ledger.history()).length,1);
    expect((await ledger.db.query('deletion_events')).single['count'],2);await ledger.integrity();
  });
  test('deletion blocks stale backup and invalid confirmation without mutation',() async {
    await ledger.fund('fund','bd_bank',10000000);final receipt=await backup();
    await ledger.fund('later','reserve',1000);final before=jsonEncode(await ledger.export());
    await expectLater(ledger.deleteAccountTransactions('erase','bd_bank',confirmation:'DELETE',backup:receipt),throwsA(isA<LedgerException>()));
    await expectLater(ledger.deleteAccountTransactions('erase','bd_bank',confirmation:'yes',backup:receipt),throwsA(isA<LedgerException>()));
    expect(jsonEncode(await ledger.export()),before);
  });
  test('deletion with dependent spending blocks, leaves whole database intact',() async {
    await ledger.fund('fund','bd_bank',10000000);await bd('send');await ledger.expense('spent','profit',500);
    final before=jsonEncode(await ledger.export()),receipt=await backup();
    expect((await ledger.previewDeletion('bd_bank')).blockers,isNotEmpty);
    await expectLater(ledger.deleteAccountTransactions('erase','bd_bank',confirmation:'DELETE',backup:receipt),throwsA(isA<LedgerException>()));
    expect(jsonEncode(await ledger.export()),before);
  });
  test('encrypted backup round trip, wrong password, tamper, live restore gate',() async {
    await ledger.fund('fund','reserve',300000);await ledger.payAgent('pay','reserve',10000);
    final snapshot=await ledger.export(),service=BackupService();
    final bytes=await service.encrypt(snapshot,'secure-test-password');
    expect(await service.decrypt(bytes,'secure-test-password'),snapshot);
    await expectLater(service.decrypt(bytes,'wrong-test-password'),throwsA(isA<LedgerException>()));
    final envelope=jsonDecode(utf8.decode(bytes)) as Map;envelope['mac']=base64Encode(List.filled(16,0));
    await expectLater(service.decrypt(utf8.encode(jsonEncode(envelope)),'secure-test-password'),throwsA(isA<LedgerException>()));
    final restored=await Ledger.open('${directory.path}/restored.db',factory:databaseFactoryFfi);
    try{await restored.restore(snapshot);expect(await restored.export(),snapshot);await restored.integrity();
      await expectLater(restored.restore(snapshot),throwsA(isA<LedgerException>()));}finally{await restored.db.close();}
    await expectLater(ledger.restore({'format':'legacy'}),throwsA(isA<LedgerException>()));
  });
  test('reopen preserves postings and duplicate protection',() async {
    await ledger.fund('fund','bd_bank',10000000);await bd('send');await ledger.db.close();
    ledger=await Ledger.open('${directory.path}/ledger.db',factory:databaseFactoryFfi);
    await bd('send');expect(await ledger.balance('profit'),1949);await ledger.integrity();
  });
  test('failed restore rolls back a fresh installation',() async {
    final snapshot=await ledger.export();
    final broken=jsonDecode(jsonEncode(snapshot)) as Map<String,Object?>;
    (broken['accounts'] as List).removeAt(0);
    final before=jsonEncode(snapshot);
    await expectLater(ledger.restore(broken),throwsA(anything));expect(jsonEncode(await ledger.export()),before);
  });
  test('historical funding example and every funded expense wallet',() async {
    await ledger.fund('opening','bd_bank',9000000);
    await ledger.fund('deposit','bd_bank',1000000);
    await bd('send',amount:3000000);
    expect(await ledger.balance('bd_bank'),7000000);
    final totals=await ledger.summary(account:'bd_bank');
    expect(totals['funding'],10000000);expect(totals['remitted'],3000000);
    final earned=(await ledger.summary())['profit'];
    await ledger.expense('bd_expense','bd_bank',100);
    await ledger.expense('principal_expense','principal',100);
    await ledger.expense('profit_expense','profit',100);
    expect(await ledger.balance('bd_bank'),6999900);
    expect((await ledger.summary())['profit'],earned);
    expect((await ledger.summary())['expense_BDT'],100);
    expect((await ledger.summary())['expense_AED'],200);
  });
  test('bank-to-bank transfers never create historical funding',() async {
    await ledger.addAccount('দ্বিতীয় ব্যাংক','BDT','bank');
    final other=(await ledger.accounts()).firstWhere((a)=>a['role']=='bank'&&a['id']!='bd_bank')['id'] as String;
    await ledger.fund('opening','bd_bank',10000000);
    await ledger.transfer('move','bd_bank',other,2000000);
    expect(await ledger.balance(other),2000000);
    expect((await ledger.summary(account:'bd_bank'))['funding'],10000000);
    expect((await ledger.summary(account:other))['funding'],0);
  });
  test('partial agent payments and outside-account settlement block deletion',() async {
    await ledger.fund('cash','reserve',300000);await pk('pk');
    await ledger.payAgent('partial','reserve',50000);
    expect(await ledger.balance('agent_payable'),-150000);
    final preview=await ledger.previewDeletion('principal');
    expect(preview.blockers,isNotEmpty);
    final receipt=await backup(),before=jsonEncode(await ledger.export());
    await expectLater(ledger.deleteAccountTransactions('erase','principal',confirmation:'DELETE',backup:receipt),throwsA(isA<LedgerException>()));
    expect(jsonEncode(await ledger.export()),before);
  });
  test('native failure midway through permanent deletion rolls everything back',() async {
    await ledger.fund('fund','bd_bank',10000000);await bd('send');
    final receipt=await backup(),before=jsonEncode(await ledger.export());
    await ledger.db.execute("CREATE TRIGGER fail_deletion BEFORE DELETE ON operations WHEN OLD.id='send' BEGIN SELECT RAISE(ABORT,'injected failure'); END");
    await expectLater(ledger.deleteAccountTransactions('erase','bd_bank',confirmation:'DELETE',backup:receipt),throwsA(anything));
    expect(jsonEncode(await ledger.export()),before);
    expect((await ledger.db.query('deletion_events')),isEmpty);
    await ledger.integrity();
  });
  test('native failure during period close rolls back cash transfer and archive',() async {
    await ledger.fund('fund','bd_bank',10000000);await bd('send');
    final before=jsonEncode(await ledger.export());
    await ledger.db.execute("CREATE TRIGGER fail_period BEFORE INSERT ON periods WHEN EXISTS(SELECT 1 FROM periods WHERE ended IS NOT NULL) BEGIN SELECT RAISE(ABORT,'injected failure'); END");
    await expectLater(ledger.closePeriod('close',reconciled:true),throwsA(anything));
    expect(jsonEncode(await ledger.export()),before);
    expect(await ledger.balance('profit'),1949);await ledger.integrity();
  });
  test('backup restore includes archived periods, advances and deletion metadata',() async {
    await ledger.fund('fund','bd_bank',10000000);await bd('send');
    await ledger.closePeriod('close',reconciled:true);
    await ledger.payAgent('advance','principal',10000);
    await ledger.fund('reserve','reserve',5000);
    final receipt=await backup();
    await ledger.deleteAccountTransactions('erase','reserve',confirmation:'DELETE',backup:receipt);
    final snapshot=await ledger.export(),service=BackupService();
    final decoded=await service.decrypt(await service.encrypt(snapshot,'secure-test-password'),'secure-test-password');
    final restored=await Ledger.open('${directory.path}/metadata_restore.db',factory:databaseFactoryFfi);
    try {
      await restored.restore(decoded);expect(await restored.export(),snapshot);
      expect(await restored.balance('agent_advance'),10000);
      expect((await restored.db.query('periods',where:'ended IS NOT NULL')).length,1);
      expect((await restored.db.query('deletion_events')).length,1);await restored.integrity();
    } finally {await restored.db.close();}
  });

}
