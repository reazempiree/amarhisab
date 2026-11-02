import 'package:flutter/material.dart';
import '../core/money.dart';
import '../data/ledger.dart';
import 'components.dart';
import 'controller.dart';

class RemittanceScreen extends StatefulWidget {
  final LedgerController controller;
  final String initialCountry;
  const RemittanceScreen({super.key,required this.controller,this.initialCountry='BD'});
  @override
  State<RemittanceScreen> createState()=>_RemittanceScreenState();
}
class _RemittanceScreenState extends State<RemittanceScreen> {
  late String country=widget.initialCountry;
  String bank='bd_bank';
  final bankRate=TextEditingController(),customerRate=TextEditingController(),
    amount=TextEditingController(),fee=TextEditingController();
  final key=operationKey();
  bool loading=true,busy=false;
  String? error;
  int? commission;
  @override
  void initState(){super.initState();loadDefaults();}
  Future<void> loadDefaults() async {
    final ledger=widget.controller.ledger;
    final selected=country;
    final rb=await ledger.setting('${selected}_bankRate')??(selected=='BD'?'34.45':'76.00');
    final rc=await ledger.setting('${selected}_customerRate')??(selected=='BD'?'34.00':'75.50');
    final f=await ledger.setting('${selected}_fee')??'5.00';
    // No guessed commission sharing: PK save stays blocked until a verified rule
    // is implemented. This cannot be enabled by an arbitrary settings value.
    if(!mounted||selected!=country){ return; }
    setState((){bankRate.text=rb;customerRate.text=rc;fee.text=f;loading=false;});
  }
  RemittanceQuote quote()=>RemittanceQuote(amount:Decimal.parse(amount.text).minor(),
    bankRate:bankRate.text,customerRate:customerRate.text,fee:Decimal.parse(fee.text).minor(),agentCommission:commission??0);
  Future<void> save() async {
    if(busy){ return; }
    setState((){busy=true;error=null;});
    try {
      final q=quote();
      await widget.controller.mutate(()=>widget.controller.ledger.remittance(key,country:country,
        amount:Decimal.parse(amount.text).minor(),bankRate:latinDigits(bankRate.text.trim()),
        customerRate:latinDigits(customerRate.text.trim()),fee:q.fee,bank:bank,
        agentCommission:country=='PK'?commission:null));
      if(mounted){ Navigator.pop(context); }
    }catch(e){if(mounted){ setState((){error=e is FormatException?e.message:e.toString();busy=false;}); }}
  }
  @override
  void dispose(){bankRate.dispose();customerRate.dispose();amount.dispose();fee.dispose();super.dispose();}
  @override
  Widget build(BuildContext context) {
    RemittanceQuote? q;String? quoteError;
    if(amount.text.isNotEmpty){try{q=quote();}catch(e){quoteError=e is FormatException?e.message:e.toString();}}
    final banks=widget.controller.accounts.where((a)=>a['role']=='bank'&&a['currency']=='BDT').toList();
    return PopScope(canPop:!busy,child:Scaffold(appBar:AppBar(title:const Text('টাকা পাঠান')),
      body:SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.all(20),child:Center(child:ConstrainedBox(
        constraints:const BoxConstraints(maxWidth:600),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        SegmentedButton<String>(segments:const [ButtonSegment(value:'BD',label:Text('বাংলাদেশ')),ButtonSegment(value:'PK',label:Text('পাকিস্তান'))],
          selected:{country},onSelectionChanged:busy?null:(s){setState((){country=s.single;loading=true;error=null;});loadDefaults();}),
        const SizedBox(height:20),
        if(loading)const Center(child:CircularProgressIndicator()) else ...[
          if(country=='BD'&&banks.length>1)Padding(padding:const EdgeInsets.only(bottom:16),child:DropdownButtonFormField<String>(
            initialValue:bank,items:banks.map((a)=>DropdownMenuItem(value:a['id'] as String,child:Text(a['name'] as String))).toList(),
            decoration:const InputDecoration(labelText:'বাংলাদেশ ব্যাংক'),onChanged:busy?null:(v)=>setState(()=>bank=v!))),
          OutlineCard(child:Column(children:[
            for(final field in <(TextEditingController,String)>[
              (bankRate,country=='BD'?'ব্যাংক রেট (BDT / AED)':'এজেন্ট রেট (PKR / AED)'),
              (customerRate,'গ্রাহক রেট (${country=='BD'?'BDT':'PKR'} / AED)'),
              (amount,'পাঠানোর পরিমাণ (${country=='BD'?'BDT':'PKR'})'),(fee,'সার্ভিস চার্জ (AED)'),
            ])Padding(padding:const EdgeInsets.symmetric(vertical:8),child:TextField(controller:field.$1,enabled:!busy,
              keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:field.$2),onChanged:(_)=>setState((){}))),
          ])),
          if(country=='PK')const OutlineCard(child:Text('এজেন্ট কমিশনের নিয়ম এখনও নিশ্চিত নয়। নিচের হিসাব কমিশনের আগের প্রাক্কলন। নিয়ম যাচাই না হওয়া পর্যন্ত পাকিস্তান রেমিট্যান্স সংরক্ষণ বন্ধ আছে।')),
          if(q!=null)OutlineCard(black:true,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            AmountLine('মূলধন',q.principal,'AED'),AmountLine('গ্রাহকের AED',q.customer,'AED'),
            AmountLine('বিনিময় লাভ',q.exchangeProfit,'AED'),AmountLine('সার্ভিস ফি',q.fee,'AED'),
            const Divider(color:Colors.white38),AmountLine(country=='PK'?'কমিশনের আগে মোট লাভ':'নিজের মোট লাভ',q.profit,'AED',prominent:true),
            AmountLine('গ্রাহকের কাছ থেকে মোট গ্রহণ',q.collected,'AED'),
          ])),
          if(quoteError!=null)Text(quoteError,style:TextStyle(color:Theme.of(context).colorScheme.error)),
          if(error!=null)Padding(padding:const EdgeInsets.only(bottom:16),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
          const Text('সংরক্ষণ মানে গ্রাহকের সম্পূর্ণ AED হাতে পেয়েছেন এবং রেমিট্যান্স সম্পন্ন। গ্রাহক-বাকির ব্যবস্থা নেই।'),
          const SizedBox(height:16),FilledButton.icon(onPressed:busy||q==null||(country=='PK'&&commission==null)?null:save,
            icon:busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.check),
            label:Text(busy?'সংরক্ষণ হচ্ছে…':'সংরক্ষণ করুন')),
        ],
      ])))))));
  }
}
