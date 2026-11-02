/// Decimal input is parsed exactly. Ledger amounts are integer hundredths.
/// Division rounds half away from zero, once at each posted currency boundary.
class Decimal {
  final BigInt numerator;
  final BigInt denominator;
  const Decimal._(this.numerator, this.denominator);

  factory Decimal.parse(String input) {
    final text = latinDigits(input.trim());
    if (!RegExp(r'^-?\d+(\.\d{1,8})?$').hasMatch(text)) {
      throw const FormatException('সঠিক সংখ্যা লিখুন (সর্বোচ্চ ৮ দশমিক)');
    }
    final parts = text.split('.');
    final scale = BigInt.from(10).pow(parts.length == 2 ? parts[1].length : 0);
    return Decimal._(BigInt.parse(text.replaceAll('.', '')), scale);
  }

  int minor() => rounded(numerator * BigInt.from(100), denominator);
  bool get positive => numerator > BigInt.zero;
  int divideMinor(int foreignMinor) {
    if (!positive) { throw const FormatException('রেট শূন্যের বেশি হতে হবে'); }
    return rounded(BigInt.from(foreignMinor) * denominator, numerator);
  }

  int multiplyMinor(int minor) => rounded(BigInt.from(minor) * numerator, denominator);
}

int rounded(BigInt numerator, BigInt denominator) {
  if (denominator <= BigInt.zero) { throw ArgumentError('Invalid denominator'); }
  final absolute = numerator.abs();
  final result = (absolute + denominator ~/ BigInt.two) ~/ denominator;
  final signed = numerator.isNegative ? -result : result;
  // Stay within exact SQLite/Dart/JSON portable integer range.
  if (signed.abs() > BigInt.from(9007199254740991)) {
    throw const FormatException('টাকার পরিমাণ অনেক বড়');
  }
  return signed.toInt();
}

String latinDigits(String text) {
  const bn = '০১২৩৪৫৬৭৮৯';
  for (var i = 0; i < 10; i++) {
    text = text.replaceAll(bn[i], '$i');
  }
  return text;
}

String bengali(String text) => text.replaceAllMapped(
  RegExp(r'[0-9]'), (m) => '০১২৩৪৫৬৭৮৯'[int.parse(m[0]!)],
);

String money(int minor, String currency) {
  final absolute = minor.abs();
  final whole = (absolute ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',',
  );
  final fraction = absolute % 100;
  final decimals = currency == 'AED' || fraction != 0
      ? '.${fraction.toString().padLeft(2, '0')}' : '';
  return '${minor < 0 ? '−' : ''}${bengali('$whole$decimals')} $currency';
}

class RemittanceQuote {
  final int principal, customer, exchangeProfit, fee, profit, collected;
  const RemittanceQuote._(this.principal, this.customer, this.exchangeProfit,
      this.fee, this.profit, this.collected);
  factory RemittanceQuote({required int amount, required String bankRate,
      required String customerRate, required int fee, int agentCommission = 0}) {
    if (amount <= 0 || fee < 0 || agentCommission < 0) {
      throw const FormatException('পরিমাণ শূন্যের বেশি এবং ফি ঋণাত্মক নয়');
    }
    final principal = Decimal.parse(bankRate).divideMinor(amount);
    final customer = Decimal.parse(customerRate).divideMinor(amount);
    final exchange = customer - principal;
    final profit = exchange + fee - agentCommission;
    if (principal <= 0 || customer <= 0 || profit < 0) {
      throw const FormatException('এই রেটে লাভ ঋণাত্মক বা পরিমাণ খুব কম');
    }
    return RemittanceQuote._(principal, customer, exchange, fee, profit, customer + fee);
  }
}
