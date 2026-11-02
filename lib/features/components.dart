import 'package:flutter/material.dart';
import '../core/money.dart';

class OutlineCard extends StatelessWidget {
  final Widget child;
  final bool black;
  final EdgeInsets padding;
  const OutlineCard({super.key,required this.child,this.black=false,
    this.padding=const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext context) {
    final dark=Theme.of(context).brightness==Brightness.dark;
    return Container(margin:const EdgeInsets.only(bottom:16),padding:padding,
      decoration:BoxDecoration(color:black?const Color(0xff181818):Theme.of(context).colorScheme.surface,
        borderRadius:BorderRadius.circular(24),
        border:Border.all(color:dark?Colors.white70:const Color(0xff252525),width:1.5),
        boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:0.08),blurRadius:12,offset:const Offset(0,5))]),
      child:black?DefaultTextStyle.merge(style:const TextStyle(color:Colors.white),child:IconTheme(
        data:const IconThemeData(color:Colors.white),child:child)):child);
  }
}

class AmountLine extends StatelessWidget {
  final String label,currency;
  final int amount;
  final bool prominent;
  const AmountLine(this.label,this.amount,this.currency,{super.key,this.prominent=false});
  @override
  Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.symmetric(vertical:6),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(label,style:TextStyle(fontSize:prominent?14:12)),
      Text(money(amount,currency),style:TextStyle(fontWeight:FontWeight.w800,fontSize:prominent?30:20)),
    ]));
}

class FieldSpec {
  final String keyName,label,initial;
  final bool numeric,secret;
  const FieldSpec(this.keyName,this.label,{this.initial='',this.numeric=false,this.secret=false});
}

class EntryDialog extends StatefulWidget {
  final String title,action;
  final List<FieldSpec> fields;
  final Map<String,String>? choices;
  final String? initialChoice;
  final String? warning;
  final Future<void> Function(Map<String,String> values,String? choice) submit;
  const EntryDialog({super.key,required this.title,required this.fields,required this.submit,
    this.action='সংরক্ষণ করুন',this.choices,this.initialChoice,this.warning});
  @override
  State<EntryDialog> createState()=>_EntryDialogState();
}
class _EntryDialogState extends State<EntryDialog> {
  late final Map<String,TextEditingController> fields={for(final f in widget.fields) f.keyName:TextEditingController(text:f.initial)};
  late String? choice=widget.initialChoice??widget.choices?.keys.firstOrNull;
  bool busy=false;
  String? error;
  @override
  void dispose(){for(final c in fields.values){c.dispose();}super.dispose();}
  Future<void> submit() async {
    if(busy){ return; }
    setState((){busy=true;error=null;});
    try {
      await widget.submit({for(final e in fields.entries)e.key:e.value.text},choice);
      if(mounted){ Navigator.pop(context,true); }
    } catch(e) {
      if(mounted){ setState((){error=e is FormatException?e.message:e.toString();busy=false;}); }
    }
  }
  @override
  Widget build(BuildContext context)=>PopScope(canPop:!busy,child:AlertDialog(
    title:Text(widget.title),content:SizedBox(width:420,child:SingleChildScrollView(child:Column(
      mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      if(widget.warning!=null)Padding(padding:const EdgeInsets.only(bottom:16),child:Text(widget.warning!)),
      if(widget.choices!=null)DropdownButtonFormField<String>(initialValue:choice,isExpanded:true,
        items:widget.choices!.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),
        onChanged:busy?null:(v)=>setState(()=>choice=v),decoration:const InputDecoration(labelText:'অ্যাকাউন্ট')),
      for(final f in widget.fields)Padding(padding:const EdgeInsets.only(top:14),child:TextField(
        controller:fields[f.keyName],enabled:!busy,obscureText:f.secret,
        keyboardType:f.numeric?const TextInputType.numberWithOptions(decimal:true,signed:false):TextInputType.text,
        decoration:InputDecoration(labelText:f.label),onSubmitted:(_)=>submit())),
      if(error!=null)Padding(padding:const EdgeInsets.only(top:16),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
    ]))),actions:[TextButton(onPressed:busy?null:()=>Navigator.pop(context),child:const Text('ফিরে যান')),
      FilledButton(onPressed:busy?null:submit,child:Text(busy?'সংরক্ষণ হচ্ছে…':widget.action))]));
}

Future<bool> confirm(BuildContext context,String title,String message) async => await showDialog<bool>(
  context:context,builder:(context)=>AlertDialog(title:Text(title),content:SingleChildScrollView(child:Text(message)),
    actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('ফিরে যান')),
      FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('নিশ্চিত করুন'))]))??false;
