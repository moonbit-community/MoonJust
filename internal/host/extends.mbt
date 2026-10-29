///|
pub extend CacheLease with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CacheLease with Eq::{not_equal, equal}

///|
pub extend CommandSpec with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CommandSpec with Eq::{not_equal, equal}

///|
pub extend FileMetadata with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FileMetadata with Eq::{not_equal, equal}

///|
pub extend HostCapability with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend HostCapability with Eq::{not_equal, equal}

///|
pub extend HostCapability with Hash::{hash, hash_combine}

///|
pub extend HostError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend HostError with Eq::{not_equal, equal}

///|
pub extend OperatingSystem with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend OperatingSystem with Eq::{not_equal, equal}

///|
pub extend OperatingSystem with Hash::{hash, hash_combine}

///|
pub extend OutputStream with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend OutputStream with Eq::{not_equal, equal}

///|
pub extend PlatformInfo with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PlatformInfo with Eq::{not_equal, equal}

///|
pub extend ProcessResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ProcessResult with Eq::{not_equal, equal}

///|
pub extend ProcessTermination with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ProcessTermination with Eq::{not_equal, equal}

///|
pub extend SignalKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SignalKind with Eq::{not_equal, equal}

///|
pub extend StdioBehavior with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend StdioBehavior with Eq::{not_equal, equal}

///|
pub extend TerminalInfo with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TerminalInfo with Eq::{not_equal, equal}
