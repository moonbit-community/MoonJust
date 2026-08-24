///|
/// Keywords recognized by the `just` 1.57.0 parser.
///
/// The lexer deliberately emits keywords as `Identifier`; parser clients may
/// use `Keyword::from_lexeme` when grammar context requires a keyword.
pub(all) enum Keyword {
  Alias
  AllowDuplicateRecipes
  AllowDuplicateVariables
  Assert
  DefaultList
  DefaultScript
  DotenvCommand
  DotenvFilename
  DotenvLoad
  DotenvOverride
  DotenvPath
  DotenvRequired
  Eager
  Else
  Export
  F
  Fallback
  False
  Guards
  If
  IgnoreComments
  Import
  Indentation
  Lazy
  Lists
  MinimumVersion
  Mod
  NoCd
  NoExitMessage
  PositionalArguments
  Quiet
  ScriptInterpreter
  Set
  Shell
  Tempdir
  True
  Unexport
  Unstable
  WindowsPowershell
  WindowsShell
  WorkingDirectory
  X
} derive(Eq, Compare, Hash, Debug)

///|
/// Resolve a keyword from its exact source lexeme.
pub fn Keyword::from_lexeme(lexeme : String) -> Keyword? {
  match lexeme {
    "alias" => Some(Alias)
    "allow-duplicate-recipes" => Some(AllowDuplicateRecipes)
    "allow-duplicate-variables" => Some(AllowDuplicateVariables)
    "assert" => Some(Assert)
    "default-list" => Some(DefaultList)
    "default-script" => Some(DefaultScript)
    "dotenv-command" => Some(DotenvCommand)
    "dotenv-filename" => Some(DotenvFilename)
    "dotenv-load" => Some(DotenvLoad)
    "dotenv-override" => Some(DotenvOverride)
    "dotenv-path" => Some(DotenvPath)
    "dotenv-required" => Some(DotenvRequired)
    "eager" => Some(Eager)
    "else" => Some(Else)
    "export" => Some(Export)
    "f" => Some(F)
    "fallback" => Some(Fallback)
    "false" => Some(False)
    "guards" => Some(Guards)
    "if" => Some(If)
    "ignore-comments" => Some(IgnoreComments)
    "import" => Some(Import)
    "indentation" => Some(Indentation)
    "lazy" => Some(Lazy)
    "lists" => Some(Lists)
    "minimum-version" => Some(MinimumVersion)
    "mod" => Some(Mod)
    "no-cd" => Some(NoCd)
    "no-exit-message" => Some(NoExitMessage)
    "positional-arguments" => Some(PositionalArguments)
    "quiet" => Some(Quiet)
    "script-interpreter" => Some(ScriptInterpreter)
    "set" => Some(Set)
    "shell" => Some(Shell)
    "tempdir" => Some(Tempdir)
    "true" => Some(True)
    "unexport" => Some(Unexport)
    "unstable" => Some(Unstable)
    "windows-powershell" => Some(WindowsPowershell)
    "windows-shell" => Some(WindowsShell)
    "working-directory" => Some(WorkingDirectory)
    "x" => Some(X)
    _ => None
  }
}

///|
/// Return the exact source lexeme for this keyword.
pub fn Keyword::lexeme(self : Keyword) -> String {
  match self {
    Alias => "alias"
    AllowDuplicateRecipes => "allow-duplicate-recipes"
    AllowDuplicateVariables => "allow-duplicate-variables"
    Assert => "assert"
    DefaultList => "default-list"
    DefaultScript => "default-script"
    DotenvCommand => "dotenv-command"
    DotenvFilename => "dotenv-filename"
    DotenvLoad => "dotenv-load"
    DotenvOverride => "dotenv-override"
    DotenvPath => "dotenv-path"
    DotenvRequired => "dotenv-required"
    Eager => "eager"
    Else => "else"
    Export => "export"
    F => "f"
    Fallback => "fallback"
    False => "false"
    Guards => "guards"
    If => "if"
    IgnoreComments => "ignore-comments"
    Import => "import"
    Indentation => "indentation"
    Lazy => "lazy"
    Lists => "lists"
    MinimumVersion => "minimum-version"
    Mod => "mod"
    NoCd => "no-cd"
    NoExitMessage => "no-exit-message"
    PositionalArguments => "positional-arguments"
    Quiet => "quiet"
    ScriptInterpreter => "script-interpreter"
    Set => "set"
    Shell => "shell"
    Tempdir => "tempdir"
    True => "true"
    Unexport => "unexport"
    Unstable => "unstable"
    WindowsPowershell => "windows-powershell"
    WindowsShell => "windows-shell"
    WorkingDirectory => "working-directory"
    X => "x"
  }
}
