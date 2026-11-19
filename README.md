# MoonJust

MoonJust runs justfiles through MoonX and targets CLI compatibility with **just 1.59.0**.

## Usage

Save this recipe as `justfile`.

```just
hello name="world":
    @echo "Hello, {{ name }}!"
```

```sh
# Run the default recipe (prints "Hello, world!")
moonx ZSeanYves/MoonJust

# List recipes, then run one with an argument
moonx ZSeanYves/MoonJust --list
moonx ZSeanYves/MoonJust hello MoonBit

# Preview the shell command
moonx ZSeanYves/MoonJust --dry-run hello MoonBit
```

MoonJust looks for a justfile in the current directory and its parents. By default, the first recipe runs when you omit the recipe name. Use `[default]` to select a different recipe.

## All options

Put MoonJust options before the recipe name. To pass a flag to a recipe, place it after the recipe name. Use `--` to end option parsing explicitly.

### Finding and editing justfiles

| Option | Description |
| --- | --- |
| `-f, --justfile FILE` | Read a specific justfile. Use `-` to read it from standard input. |
| `-d, --working-directory DIR` | Use `DIR` as the working directory. With automatic discovery, start the search there. |
| `--justfile-name NAME` | Search for the given filename. Repeat the option or supply a comma-separated list to try multiple names. |
| `--ceiling DIR` | Stop the upward search for a justfile at `DIR`. |
| `-g, --global-justfile` | Use the global justfile. |
| `--init`, `--initialize` | Create a starter justfile in the project root. |
| `-e, --edit` | Open the justfile in an editor. |
| `--fmt`, `--format` | Format the justfile. When reading from stdin, write the formatted text to stdout. See **Notes** for in-place writes. |
| `--check` | Use with `--fmt` to check formatting. Exit 0 if the input is formatted, or exit 1 and show a diff if it needs changes. |
| `--indentation TEXT` | Use `TEXT` to indent recipe bodies when formatting. |

### Listing and inspecting recipes

| Option | Description |
| --- | --- |
| `-l, --list [MODULE...]` | List available recipes in the root justfile or in the named module. |
| `--default-list` | List recipes when invoked without arguments. |
| `--list-submodules` | Include recipes from submodules in `--list`. |
| `--group GROUP` | Filter `--list` or `--choose` by group. Repeat to include multiple groups. |
| `--groups` | Print recipe group names. |
| `--summary` | Print available recipe names on one line. |
| `-u, --unsorted` | Show list and summary entries in source order. |
| `--no-aliases` | Hide recipe aliases in the list. |
| `--alias-style STYLE` | Display aliases on the `left`, on the `right` (default), or as `separate` entries. |
| `--list-heading TEXT` | Set the text before the recipe list. The default is `Available recipes:` followed by a newline. |
| `--list-prefix TEXT` | Set the prefix before each list entry. The default is four spaces. |
| `-s, --show RECIPE_PATH...` | Print the definition of the recipe at the given path. |
| `--usage [PATH...]` | Print usage for one recipe or for all recipes in a module. Omit the path for the root module. |
| `--variables` | Print variable names. |
| `--evaluate [VARIABLE]`, `--eval [VARIABLE]` | Print evaluated assignments, or just the value of the named variable. |
| `--evaluate-format FORMAT` | Print evaluated assignments in `just` (default) or `shell` syntax. |
| `--dump` | Print the parsed justfile. |
| `--dump-format FORMAT` | Select `just` (default) or `json` output for `--dump`. |
| `--json` | Print the justfile as JSON. |

### Running recipes and commands

| Option | Description |
| --- | --- |
| `-n, --dry-run` | Print the commands a recipe would run. |
| `--choose` | Select one or more recipes interactively and run them. |
| `--chooser COMMAND` | Set the chooser used by `--choose`. The default is `fzf`. |
| `-c, --command COMMAND [ARG...]` | Run an external command with the justfile’s working directory and environment. |
| `--shell-command` | With `--command`, invoke the command through the recipe shell. |
| `--shell SHELL` | Set the shell for recipe lines and backticks. |
| `--shell-arg ARG` | Pass an argument to the shell. Repeat to pass more than one. |
| `--clear-shell-args` | Clear the shell argument list. |
| `--set VARIABLE VALUE` | Override a variable. Repeat for additional overrides. |
| `--jobs N` | Run at most `N` recipes simultaneously when executing parallel dependencies. |
| `--one` | Allow only one recipe to be requested on the command line. |
| `--allow-missing` | Ignore missing recipe or module errors. |
| `--no-deps`, `--no-dependencies` | Skip recipe dependencies. |
| `--yes` | Automatically confirm recipes that ask for confirmation. |
| `--no-cache` | Bypass the recipe cache. |
| `--clean [RECIPE_PATH...]` | Clear the project’s recipe cache. Supply a path to clear only entries with that recipe path prefix. |
| `--tempdir DIR` | Use `DIR` for temporary files. |
| `--cygpath PROGRAM` | Set the program used to convert Unix and Windows paths. The default is `cygpath`. |
| `--unstable` | Enable features marked unstable. |

### Loading environment variables

| Option | Description |
| --- | --- |
| `-F, --dotenv-filename NAME` | Search for an environment file with this name. Repeat to supply multiple names. |
| `-E, --dotenv-path FILE` | Load an environment file from an explicit path. Repeat to supply multiple paths. |
| `--dotenv-command COMMAND` | Run a command and read its stdout as dotenv data. Repeat for multiple commands. |
| `--no-dotenv` | Disable dotenv loading. |

### Output and program information

| Option | Description |
| --- | --- |
| `-q, --quiet` | Suppress output during execution. |
| `-v, --verbose` | Increase verbosity. Repeat for more detail. |
| `--explain` | Print the recipe’s documentation comment before running it. |
| `--color MODE` | Set color output to `always`, `auto` (default), or `never`. |
| `--command-color COLOR` | Color echoed recipe lines. Choose `black`, `blue`, `cyan`, `green`, `purple`, `red`, or `yellow`. |
| `--highlight` | Display echoed recipe lines in bold. |
| `--no-highlight` | Disable bold highlighting for echoed recipe lines. |
| `--time` | Print recipe execution times. |
| `--timestamp` | Add timestamps to echoed commands. |
| `--timestamp-format FORMAT` | Set the timestamp format. The default is `%H:%M:%S`. |
| `--changelog` | Print the upstream just changelog. |
| `--man` | Print the manual page. |
| `-h, --help` | Show command-line help, including environment variable names. |
| `-V, --version` | Print the MoonJust version. |

The table describes the current source. In MoonJust builds targeting just 1.57, `--usage` requires a recipe path, `-d` requires `-f`, and `--justfile-name` accepts a single filename.

## Notes

- Use `--fmt --check` to check formatting. If formatting would change an existing file, the Wasm CLI refuses the rewrite to preserve its permissions.
- Recipes can start child processes with the permissions of the host. Review unfamiliar justfiles before running them. See the [security policy](SECURITY.md).

See the [compatibility guide](https://github.com/moonbit-community/MoonJust/blob/main/tests/compatibility/README.md) for tested behavior and known differences from upstream just.
