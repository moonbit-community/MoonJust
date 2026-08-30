///|
/// Controls observable line execution behavior without granting host access.
pub struct ExecutionOptions {
  dry_run : Bool
  quiet : Bool
  echo_quiet : Bool
  verbose : Bool
  verbosity : Int
  time : Bool
  timestamp : String?
  command_color : CommandColor?
  jobs : Int
  cache_enabled : Bool
  unstable : Bool
  no_dependencies : Bool
  explain : Bool
  color_enabled : Bool
  guards : Bool
} derive(Eq, Debug)

///|
pub fn ExecutionOptions::new(
  dry_run? : Bool = false,
  quiet? : Bool = false,
  verbose? : Bool = false,
  time? : Bool = false,
  timestamp? : String,
  command_color? : CommandColor,
) -> ExecutionOptions {
  {
    dry_run,
    quiet,
    echo_quiet: false,
    verbose,
    verbosity: if verbose {
      1
    } else {
      0
    },
    time,
    timestamp,
    command_color,
    jobs: 1,
    cache_enabled: true,
    unstable: false,
    no_dependencies: false,
    explain: false,
    color_enabled: command_color is Some(_),
    guards: false,
  }
}

///|
pub fn ExecutionOptions::from_values(
  dry_run : Bool,
  quiet : Bool,
  verbose : Bool,
  time : Bool,
  timestamp : String?,
  command_color : CommandColor?,
) -> ExecutionOptions {
  {
    dry_run,
    quiet,
    echo_quiet: false,
    verbose,
    verbosity: if verbose {
      1
    } else {
      0
    },
    time,
    timestamp,
    command_color,
    jobs: 1,
    cache_enabled: true,
    unstable: false,
    no_dependencies: false,
    explain: false,
    color_enabled: command_color is Some(_),
    guards: false,
  }
}

///|
/// Return a copy with the bounded scheduler width selected by the application.
pub fn ExecutionOptions::with_jobs(
  self : ExecutionOptions,
  jobs : Int,
) -> ExecutionOptions {
  { ..self, jobs, }
}

///|
/// Return a copy with recipe caching enabled or disabled.
pub fn ExecutionOptions::with_cache(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, cache_enabled: enabled, }
}

///|
pub fn ExecutionOptions::with_unstable(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, unstable: enabled, }
}

///|
/// Return a copy which omits both normal and subsequent recipe dependencies.
pub fn ExecutionOptions::with_no_dependencies(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, no_dependencies: enabled, }
}

///|
pub fn ExecutionOptions::with_explain(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, explain: enabled, }
}

///|
pub fn ExecutionOptions::with_color_enabled(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, color_enabled: enabled, }
}

///|
pub fn ExecutionOptions::with_guards(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, guards: enabled, }
}

///|
pub fn ExecutionOptions::with_quiet(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, quiet: enabled, }
}

///|
pub fn ExecutionOptions::with_echo_quiet(
  self : ExecutionOptions,
  enabled : Bool,
) -> ExecutionOptions {
  { ..self, echo_quiet: enabled, }
}

///|
pub fn ExecutionOptions::with_verbosity(
  self : ExecutionOptions,
  verbosity : Int,
) -> ExecutionOptions {
  { ..self, verbose: verbosity > 0, verbosity, }
}

///|
pub fn ExecutionOptions::dry_run(self : ExecutionOptions) -> Bool {
  self.dry_run
}

///|
pub fn ExecutionOptions::quiet(self : ExecutionOptions) -> Bool {
  self.quiet
}

///|
pub fn ExecutionOptions::echo_quiet(self : ExecutionOptions) -> Bool {
  self.echo_quiet
}

///|
pub fn ExecutionOptions::verbose(self : ExecutionOptions) -> Bool {
  self.verbose
}

///|
pub fn ExecutionOptions::verbosity(self : ExecutionOptions) -> Int {
  self.verbosity
}

///|
pub fn ExecutionOptions::time(self : ExecutionOptions) -> Bool {
  self.time
}

///|
pub fn ExecutionOptions::timestamp(self : ExecutionOptions) -> String? {
  self.timestamp
}

///|
pub fn ExecutionOptions::command_color(
  self : ExecutionOptions,
) -> CommandColor? {
  self.command_color
}

///|
pub fn ExecutionOptions::jobs(self : ExecutionOptions) -> Int {
  self.jobs
}

///|
pub fn ExecutionOptions::cache_enabled(self : ExecutionOptions) -> Bool {
  self.cache_enabled
}

///|
pub fn ExecutionOptions::unstable(self : ExecutionOptions) -> Bool {
  self.unstable
}

///|
pub fn ExecutionOptions::no_dependencies(self : ExecutionOptions) -> Bool {
  self.no_dependencies
}

///|
pub fn ExecutionOptions::explain(self : ExecutionOptions) -> Bool {
  self.explain
}

///|
pub fn ExecutionOptions::color_enabled(self : ExecutionOptions) -> Bool {
  self.color_enabled
}

///|
pub fn ExecutionOptions::guards(self : ExecutionOptions) -> Bool {
  self.guards
}

///|
pub(all) enum CommandColor {
  Bold
  Black
  Red
  Green
  Yellow
  Blue
  Magenta
  Cyan
  White
} derive(Eq, Debug)

///|
/// Interpreter and filesystem choices for one generated script.
