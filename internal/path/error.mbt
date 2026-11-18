///|
/// Failures from lexical path construction and composition.
#derive(Eq, Debug)
pub(all) suberror PathError {
  NulByte
  FlavorMismatch(expected~ : PathFlavor, actual~ : PathFlavor)
}
