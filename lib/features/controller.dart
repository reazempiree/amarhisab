import 'package:flutter/foundation.dart';
import '../data/ledger.dart';

class LedgerController extends ChangeNotifier {
  final Ledger ledger;
  LedgerController(this.ledger);
  List<Map<String,Object?>> accounts=[];
  List<Map<String,Object?>> history=[];
  Map<String,int> current={};
  Map<String,int> agent={};
  Map<String,Map<String,int>> bankTotals={};
  bool busy=false;
  Future<void> refresh() async {
    accounts=await ledger.accounts(); history=await ledger.history();
    current=await ledger.summary(current:true); agent=await ledger.agentSummary();
    bankTotals={};
    for(final account in accounts.where((a)=>a['role']=='bank'&&a['currency']=='BDT')) {
      bankTotals[account['id'] as String]=await ledger.summary(account:account['id'] as String);
    }
    notifyListeners();
  }
  Future<void> mutate(Future<void> Function() operation) async {
    if(busy) { throw const LedgerException('আগের লেনদেন সংরক্ষণ হচ্ছে'); }
    busy=true; notifyListeners();
    try {await operation(); await refresh();}
    finally {busy=false; notifyListeners();}
  }
  int balance(String id) => (accounts.where((a)=>a['id']==id).firstOrNull?['balance'] as int?)??0;
  String accountName(String id) => (accounts.where((a)=>a['id']==id).firstOrNull?['name'] as String?)??id;
}
