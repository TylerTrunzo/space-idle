import 'big_num.dart';

/// `after − before`, or zero when that is within a relative 1e-12 of the
/// larger side: float residue of summing and subtracting, not a real
/// change.
///
/// Reports and tools use it to leave out unchanged values.
BigNum changeBetween(BigNum after, BigNum before) {
  final d = after - before;
  final residue = after.max(before).mulDouble(1e-12);
  return d > residue || d < -residue ? d : const BigNum.zero();
}
