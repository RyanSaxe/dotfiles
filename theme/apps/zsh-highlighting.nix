# zsh's command-line highlighting, by fast-syntax-highlighting, in Neovim's
# code tiers: commands are functions, keywords are structure, and paths and
# variables are variables, and quoted text is quiet like strings.
{ t, ... }:
let
  inherit (t) code;
in
{
  "fast-syntax-highlighting.ini" = ''
    [base]
    default = none
    unknown-token = ${t.error},bold
    commandseparator = ${t.faint}
    redirection = ${code.structure}
    here-string-tri = ${code.function}
    here-string-text = ${t.muted}
    here-string-var = ${code.member},bg:${t.raised}
    exec-descriptor = ${code.function},bold
    comment = ${code.comment},bold
    correct-subtle = ${t.raised}
    incorrect-subtle = ${t.error}
    subtle-separator = ${t.faint}
    subtle-bg = bg:${t.panel}
    secondary =
    recursive-base = ${t.muted}

    [command-point]
    reserved-word = ${code.structure}
    subcommand = ${code.structure}
    precommand = ${code.structure}
    single-sq-bracket = ${code.structure}
    double-sq-bracket = ${code.structure}
    double-paren = ${code.structure}
    alias = ${code.function}
    suffix-alias = ${code.function}
    builtin = ${code.function}
    function = ${code.function}
    command = ${code.function}
    hashed-command = ${code.function}
    global-alias = bg:${t.raised}

    [paths]
    path = ${code.variable}
    pathseparator =
    path-to-dir = ${code.variable},underline
    globbing = ${code.variable},bold
    globbing-ext = ${code.variable}

    [brackets]
    paired-bracket = bg:${t.raised}
    bracket-level-1 = ${code.structure},bold
    bracket-level-2 = ${code.variable},bold
    bracket-level-3 = ${code.member},bold

    [arguments]
    single-hyphen-option = ${t.muted}
    double-hyphen-option = ${t.muted}
    back-quoted-argument = none
    single-quoted-argument = ${code.literal}
    double-quoted-argument = ${code.literal}
    dollar-quoted-argument = ${code.literal}

    [in-string]
    back-dollar-quoted-argument = ${t.second}
    back-or-dollar-double-quoted-argument = ${t.second}

    [other]
    variable = ${code.variable}
    assign = none
    assign-array-bracket = ${code.structure}
    history-expansion = ${t.info},bold

    [math]
    mathvar = ${code.variable},bold
    mathnum = ${code.constant}
    matherr = ${t.error},bold

    [for-loop]
    forvar = ${code.variable}
    fornum = ${code.constant}
    foroper = ${code.structure}
    forsep = ${t.faint}

    [case]
    case-input = ${code.variable}
    case-parentheses = ${code.structure}
    case-condition = bg:${t.raised}
  '';
}
