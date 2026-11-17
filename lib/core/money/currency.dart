/// Mata uang ISO 4217 (dibundel lokal, tanpa API kurs).
class Currency {
  final String code;
  final String symbol;
  final int decimals;
  final String name;
  const Currency(this.code, this.symbol, this.decimals, this.name);

  @override
  bool operator ==(Object other) => other is Currency && other.code == code;
  @override
  int get hashCode => code.hashCode;
  @override
  String toString() => code;
}
