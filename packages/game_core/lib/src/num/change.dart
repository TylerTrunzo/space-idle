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

/// Relative tolerance within which [takeFrom] treats a result below zero
/// as float residue.
const double takeResidue = 1e-9;

/// `have − taken`, snapped to exactly zero when it falls below zero by no
/// more than [takeResidue] of the larger side.
///
/// BigNum comparison holds two values equal at 12 significant digits, so
/// an affordability check (`have >= taken`) can pass when `have` is a hair
/// below `taken`; subtracting would then leave a tiny negative such as
/// −2.2e-16. Every place that takes stock or credits subtracts with this,
/// so such residue never reaches the state. A larger shortfall stays
/// negative, so a real overdraw is not hidden.
BigNum takeFrom(BigNum have, BigNum taken) {
  final left = have - taken;
  if (!left.isNegative) return left;
  BigNum abs(BigNum v) => v.isNegative ? -v : v;
  final scale = abs(have).max(abs(taken));
  return -left <= scale.mulDouble(takeResidue) ? const BigNum.zero() : left;
}
