import IPython
from pygments.token import Token

# get_config() is injected by IPython at startup
c = get_config()

# always tell IPython we're on a dark terminal:
c.TerminalInteractiveShell.colors = "linux"

# choose a stub style
major = int(IPython.__version__.split(".", 1)[0])
if major < 9:
    # IPython 8: must pick a real Pygments style
    stub = "native"
else:
    # IPython 9+: can pick the IPython theme
    stub = "linux"

c.TerminalInteractiveShell.highlighting_style = stub


# tokyonight colors to try and keep REPL similar to how neovim looks
c.TerminalInteractiveShell.highlighting_style_overrides = {
    Token.Comment: "#565f89",
    Token.Comment.Preproc: "#565f89",
    Token.Keyword: "#9d7cd8",
    Token.Keyword.Namespace: "#9d7cd8",
    Token.Operator: "#9d7cd8",
    Token.Punctuation: "#9d7cd8",
    Token.Name.Builtin: "#1abc9c",
    Token.Prompt: "#7aa2f7",
    Token.PromptNum: "#fca7ea",
    Token.OutPrompt: "#7aa2f7",
    Token.OutPromptNum: "#1abc9c",
    # functions & classes → orange
    Token.Name: "#89ddff",
    Token.Name.Function: "#ff9e64",
    Token.Name.Class: "#1abc9c",
    # namespaces (modules/packages) → teal
    Token.Name.Namespace: "#fca7ea",
    # decorators → magenta
    Token.Name.Decorator: "#ff9e64",
    # variables → blue
    Token.Name.Variable: "#89ddff",
    # literals (strings, numbers) → muted fg
    Token.Literal.String: "#c0caf5",
    Token.Literal.Number: "#c0caf5",
    # errors & tracebacks → red
    Token.Error: "bold #f7768e",
    Token.TB: "bold #f7768e",
}
