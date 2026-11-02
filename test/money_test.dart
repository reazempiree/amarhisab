import 'package:flutter_test/flutter_test.dart';
import 'package:amar_hisab/core/money.dart';

void main(){
  test('Bangladesh worked example reconciles to the cent',(){
    final q=RemittanceQuote(amount:3400000,bankRate:'34.50',customerRate:'34.00',fee:500);
    expect(q.principal,98551);expect(q.customer,100000);expect(q.exchangeProfit,1449);
    expect(q.profit,1949);expect(q.collected,100500);expect(q.principal+q.profit,q.collected);
  });
  test('Pakistan commission belongs to the agent, not profit',(){
    final q=RemittanceQuote(amount:7550000,bankRate:'76',customerRate:'75.5',fee:500,agentCommission:200);
    expect(q.principal,99342);expect(q.customer,100000);expect(q.profit,958);
    expect(q.principal+200+q.profit,q.collected);
  });
  test('rounding is half away from zero and exact for Bengali input',(){
    expect(Decimal.parse('১.২৩৫').minor(),124);expect(Decimal.parse('-1.235').minor(),-124);
    expect(Decimal.parse('0.005').minor(),1);expect(Decimal.parse('0.0049').minor(),0);
    expect(Decimal.parse('34.45').divideMinor(344500),10000);
  });
  test('invalid and unsafe input fails',(){
    for(final value in ['NaN','Infinity','1e3','1.234567891','1,000','']){
      expect(()=>Decimal.parse(value),throwsFormatException);
    }
    expect(()=>Decimal.parse('90071992547410').minor(),throwsFormatException);
    expect(()=>RemittanceQuote(amount:1,bankRate:'0',customerRate:'34',fee:0),throwsFormatException);
    expect(()=>RemittanceQuote(amount:3400000,bankRate:'30',customerRate:'40',fee:0),throwsFormatException);
  });
  test('display preserves fractional BDT and AED cents',(){
    expect(money(10000,'BDT'),'১০০ BDT');expect(money(10001,'BDT'),'১০০.০১ BDT');
    expect(money(10000,'AED'),'১০০.০০ AED');
  });
}
