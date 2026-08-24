///|
/// Failures from lexical path construction and composition.
pub(all) suberror PathError {
  NulByte
  FlavorMismatch(expected~ : PathFlavor, actual~ : PathFlavor)
} derive(Eq, Debug)
