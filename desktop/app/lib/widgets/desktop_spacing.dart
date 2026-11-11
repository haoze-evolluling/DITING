/// The desktop spacing scale: every gap between two elements on a page comes from here.
///
/// The scale is 4-based and deliberately short. Desktop cards are tall, and a hand-picked 6, 7 or
/// 13 between two blocks is what made earlier pages read as cramped: two gaps that differed by two
/// pixels did not read as a hierarchy, they read as an accident.
///
/// Rules of thumb, so the numbers are not applied mechanically:
///
/// * `xs` between a title and the note that belongs to it.
/// * `sm` between two rows of the same list or two badges.
/// * `md` between a heading block and the content under it, and between two unrelated blocks.
/// * `field` between two stacked text fields: an outlined field draws its floating label *above*
///   its border, so the gap has to clear the label, not just the box.
/// * `lg` before an action row that saves or discards the block above it.
/// * `xl` between the page's cards is `dashboardCardGap`, not this scale.
abstract final class AppGap {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;

  /// Between a stacked field and the field above it; see the class comment.
  static const double field = 18;

  /// Between a field and the one-line hint that explains it.
  static const double hint = 6;
}
