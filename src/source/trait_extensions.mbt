///|
#deprecated
pub extend SourceError with Debug::{to_repr}

///|
#deprecated
pub extend SourceError with Eq::{not_equal, equal}

///|
#deprecated
pub extend Source with Debug::{to_repr}

///|
#deprecated
pub extend SourcePosition with Debug::{to_repr}

///|
#deprecated
pub extend SourcePosition with Eq::{not_equal, equal}

///|
#deprecated
pub extend SourceId with Debug::{to_repr}

///|
#deprecated
pub extend SourceId with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
#deprecated
pub extend SourceId with Eq::{not_equal, equal}

///|
#deprecated
pub extend SourceId with Hash::{hash, hash_combine}

///|
#deprecated
pub extend Span with Debug::{to_repr}

///|
#deprecated
pub extend Span with Eq::{not_equal, equal}

///|
#deprecated
pub extend Span with Hash::{hash, hash_combine}
