#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Require module API and script runtime contracts.

Every Python file needs a one-sentence summary line, then at least one
substantial explanatory paragraph. The paragraph must be specific to its
module; boilerplate repeated across files satisfies the word count while
defeating the contract, so the finding messages spell out what counts.
Package modules also need a static `__all__` tuple for public functions and
classes, while standalone scripts need an explicit Python runtime contract
from either their repository or PEP 723 metadata. File discovery is shared
with the sibling checks via the `lib/pyfiles.py` subprocess (see its
docstring).
"""

from __future__ import annotations

import ast
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:

    def _load_toml(_text: str) -> dict[str, object] | None:
        return None
else:

    def _load_toml(text: str) -> dict[str, object] | None:
        try:
            data = tomllib.loads(text)
        except ValueError:
            return None
        if not isinstance(data, dict):
            return None
        return data


MIN_DETAIL_SENTENCES = 2
MIN_DETAIL_WORDS = 25
MIN_DOCSTRING_LINES = 3
DETAIL_ADVICE = (
    "the paragraph must say something true and specific about this module "
    "(why it exists, constraints, gotchas) — not restate the summary; expand "
    "existing prose instead of replacing it, and never paste one generic "
    "paragraph across files"
)
PYFILES_LIB = Path(__file__).resolve().parent / "lib" / "pyfiles.py"
# Sentence heuristic: an ender counts only before whitespace plus a
# non-lowercase character or at the end of the text, so "Python 3.10" and
# "e.g. tuples" do not count; stripping abbreviations first also keeps
# "e.g. Python" from counting.
ABBREVIATION = re.compile(r"\b(?:e\.g\.|i\.e\.|vs\.|cf\.)", re.IGNORECASE)
SENTENCE_END = re.compile(r"[.!?](?=\s+[^a-z\s]|$)")
WORD = re.compile(r"[A-Za-z0-9_']+")
DEFINITION_NODES = (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)
SEQUENCE_TARGET_NODES = (ast.Tuple, ast.List)
TOML_SECTION = re.compile(r"^\[([A-Za-z0-9_.-]+)\]\s*$")
REQUIRES_PYTHON = re.compile(r"^requires-python\s*=\s*['\"][^'\"]+['\"]\s*$")


@dataclass(frozen=True)
class _Finding:
    path: Path
    line: int
    message: str


@dataclass(frozen=True)
class _AllContract:
    names: set[str]
    line: int
    valid: bool


def main(argv: list[str]) -> int:
    findings = [finding for path in _python_files(argv) for finding in _check(path)]
    for finding in findings:
        sys.stdout.write(f"{finding.path}:{finding.line}: {finding.message}\n")
    return 1 if findings else 0


def _python_files(argv: list[str]) -> list[Path]:
    completed = subprocess.run(
        (sys.executable, str(PYFILES_LIB), *argv),
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    return [Path(raw) for raw in completed.stdout.split("\0") if raw]


def _check(path: Path) -> list[_Finding]:
    try:
        source = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return [_Finding(path, 1, "file is not valid UTF-8; fix the encoding")]
    try:
        module = ast.parse(source, filename=str(path))
    except SyntaxError as error:
        return [_Finding(path, error.lineno or 1, _parse_failure_message(error))]
    findings = _docstring_findings(path, module)
    if _is_test_file(path):
        return findings
    if _is_standalone_script(path):
        findings.extend(_script_contract_findings(path, source))
        return findings
    findings.extend(_all_findings(path, module))
    return findings


def _parse_failure_message(error: SyntaxError) -> str:
    runtime = ".".join(str(part) for part in sys.version_info[:2])
    return f"cannot be parsed by Python {runtime} ({error.msg}); fix the syntax or run this check on a newer Python"


def _is_test_file(path: Path) -> bool:
    return "tests" in path.parts


def _all_findings(path: Path, module: ast.Module) -> list[_Finding]:
    findings: list[_Finding] = []
    contract = _all_contract(module)
    public_defs = _public_top_level_definitions(module)
    if contract is None:
        findings.append(
            _Finding(
                path,
                1,
                "__all__ is required; include every public top-level function/class "
                "and review the module docstring for drift",
            )
        )
        return findings
    if not contract.valid:
        findings.append(
            _Finding(path, contract.line, "__all__ must be a static tuple of strings")
        )
    missing = sorted(public_defs - contract.names)
    if missing:
        findings.append(
            _Finding(
                path,
                contract.line,
                "__all__ is missing public definitions "
                f"{', '.join(missing)}; add them or make them private, then review "
                "the module docstring for drift",
            )
        )
    unknown = sorted(contract.names - _top_level_names(module))
    if unknown:
        findings.append(
            _Finding(
                path,
                contract.line,
                f"__all__ lists unknown names: {', '.join(unknown)}",
            )
        )
    if _mutates_all(module):
        findings.append(
            _Finding(
                path, contract.line, "__all__ must not be mutated after definition"
            )
        )
    return findings


def _is_standalone_script(path: Path) -> bool:
    if path.suffix == ".pyi":
        return False
    if path.name == "__init__.py":
        return False
    return not (path.parent / "__init__.py").is_file()


def _script_contract_findings(path: Path, source: str) -> list[_Finding]:
    if _has_pep723_requires_python(source):
        return []
    repo_root = _git_root(path)
    if repo_root is None:
        return [
            _Finding(
                path,
                1,
                "standalone script outside a git repo does not need __all__, but "
                "it needs PEP 723 script metadata with requires-python; add "
                "dependencies there if needed",
            )
        ]
    pyproject = repo_root / "pyproject.toml"
    if not pyproject.is_file():
        return [
            _Finding(
                path,
                1,
                "standalone script does not need __all__, but it needs a runtime "
                "contract: add PEP 723 metadata with requires-python, or give "
                "the git repo root a pyproject.toml with "
                "[project].requires-python",
            )
        ]
    if _pyproject_has_requires_python(pyproject):
        return []
    return [
        _Finding(
            path,
            1,
            "standalone script does not need __all__, but the repo pyproject.toml "
            "must define [project].requires-python so agents know the Python "
            "runtime",
        )
    ]


def _git_root(path: Path, *, git: str | None = None) -> Path | None:
    git_command = git or shutil.which("git")
    if git_command is None:
        return None
    anchor = path if path.is_dir() else path.parent
    try:
        completed = subprocess.run(
            (git_command, "-C", str(anchor), "rev-parse", "--show-toplevel"),
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        return None
    if completed.returncode != 0:
        return None
    root = completed.stdout.strip()
    if not root:
        return None
    return Path(root)


def _pyproject_has_requires_python(pyproject: Path) -> bool:
    text = pyproject.read_text(encoding="utf-8")
    data = _load_toml(text)
    if data is None:
        return _fallback_has_project_requires_python(text)
    project = data.get("project")
    if not isinstance(project, dict):
        return False
    value = project.get("requires-python")
    return isinstance(value, str) and bool(value.strip())


def _fallback_has_project_requires_python(text: str) -> bool:
    section = ""
    for raw_line in text.splitlines():
        line = raw_line.split("#", maxsplit=1)[0].strip()
        if not line:
            continue
        if (match := TOML_SECTION.match(line)) is not None:
            section = match.group(1)
            continue
        if section == "project" and REQUIRES_PYTHON.match(line):
            return True
    return False


def _has_pep723_requires_python(source: str) -> bool:
    in_script_block = False
    has_requires_python = False
    for raw_line in source.splitlines():
        line = raw_line.strip()
        if line == "# /// script":
            in_script_block = True
            has_requires_python = False
            continue
        if in_script_block and line == "# ///":
            return has_requires_python
        if not in_script_block:
            continue
        if not line.startswith("#"):
            return False
        content = line[1:].strip()
        if REQUIRES_PYTHON.match(content):
            has_requires_python = True
    return False


def _docstring_findings(path: Path, module: ast.Module) -> list[_Finding]:
    docstring = ast.get_docstring(module)
    line = _docstring_line(module)
    if docstring is None:
        return [
            _Finding(
                path,
                1,
                f"module docstring required: one-sentence summary plus substantial detail paragraph; {DETAIL_ADVICE}",
            )
        ]
    findings: list[_Finding] = []
    lines = docstring.strip("\n").splitlines()
    if not lines or not lines[0].strip():
        return [_Finding(path, line, "module docstring needs a summary sentence")]
    summary = lines[0].strip()
    if not summary.endswith("."):
        findings.append(_Finding(path, line, "summary sentence must end with a period"))
    if len(SENTENCE_END.findall(ABBREVIATION.sub("", summary))) != 1:
        findings.append(_Finding(path, line, "summary must be a single sentence"))
    if len(lines) == 1:
        findings.append(
            _Finding(
                path,
                line,
                "module docstring needs a blank line after the summary, then a substantial detail paragraph",
            )
        )
        return findings
    if len(lines) < MIN_DOCSTRING_LINES or lines[1].strip():
        findings.append(
            _Finding(path, line, "summary must be followed by a blank line")
        )
    detail = _first_detail_paragraph(lines)
    if detail is None:
        findings.append(
            _Finding(
                path,
                line,
                f"module docstring needs a substantial detail paragraph; {DETAIL_ADVICE}",
            )
        )
    elif (
        len(WORD.findall(detail)) < MIN_DETAIL_WORDS
        or len(SENTENCE_END.findall(ABBREVIATION.sub("", detail)))
        < MIN_DETAIL_SENTENCES
    ):
        findings.append(
            _Finding(
                path,
                line,
                "first detail paragraph must be substantial: at least "
                f"{MIN_DETAIL_WORDS} words and {MIN_DETAIL_SENTENCES} sentences; {DETAIL_ADVICE}",
            )
        )
    if any(part.strip() == "Exports:" for part in lines):
        findings.append(
            _Finding(
                path, line, "remove Exports: from the docstring; __all__ owns exports"
            )
        )
    return findings


def _docstring_line(module: ast.Module) -> int:
    if not module.body:
        return 1
    return getattr(module.body[0], "lineno", 1)


def _first_detail_paragraph(lines: list[str]) -> str | None:
    if len(lines) < MIN_DOCSTRING_LINES or lines[1].strip():
        return None
    paragraph: list[str] = []
    for raw_line in lines[2:]:
        line = raw_line.strip()
        if not line:
            break
        paragraph.append(line)
    if not paragraph:
        return None
    return " ".join(paragraph)


def _all_contract(module: ast.Module) -> _AllContract | None:
    contracts: list[_AllContract] = []
    for statement in module.body:
        value = _all_assignment_value(statement)
        if value is None:
            continue
        contracts.append(
            _AllContract(
                names=_static_string_tuple(value),
                line=getattr(statement, "lineno", 1),
                valid=_is_static_string_tuple(value),
            )
        )
    if not contracts:
        return None
    if len(contracts) == 1:
        return contracts[0]
    first = contracts[0]
    return _AllContract(names=first.names, line=first.line, valid=False)


def _all_assignment_value(statement: ast.stmt) -> ast.expr | None:
    if isinstance(statement, ast.Assign) and any(
        _is_all_target(target) for target in statement.targets
    ):
        return statement.value
    if isinstance(statement, ast.AnnAssign) and _is_all_target(statement.target):
        return statement.value
    return None


def _is_all_target(target: ast.expr) -> bool:
    return isinstance(target, ast.Name) and target.id == "__all__"


def _is_static_string_tuple(value: ast.expr | None) -> bool:
    if not isinstance(value, ast.Tuple):
        return False
    return all(
        isinstance(element, ast.Constant) and isinstance(element.value, str)
        for element in value.elts
    )


def _static_string_tuple(value: ast.expr | None) -> set[str]:
    if not isinstance(value, ast.Tuple):
        return set()
    return {
        element.value
        for element in value.elts
        if isinstance(element, ast.Constant) and isinstance(element.value, str)
    }


def _public_top_level_definitions(module: ast.Module) -> set[str]:
    names: set[str] = set()
    for statement in module.body:
        if isinstance(statement, DEFINITION_NODES):
            _add_public(names, statement.name)
    return names


def _statements_with_conditional_blocks(body: list[ast.stmt]) -> list[ast.stmt]:
    statements: list[ast.stmt] = []
    for statement in body:
        statements.append(statement)
        for block in _conditional_blocks(statement):
            statements.extend(_statements_with_conditional_blocks(block))
    return statements


def _conditional_blocks(statement: ast.stmt) -> tuple[list[ast.stmt], ...]:
    if isinstance(statement, ast.Try):
        handler_bodies = tuple(handler.body for handler in statement.handlers)
        return (statement.body, *handler_bodies, statement.orelse, statement.finalbody)
    if isinstance(statement, ast.If):
        return (statement.body, statement.orelse)
    return ()


def _top_level_names(module: ast.Module) -> set[str]:
    names: set[str] = set()
    for statement in _statements_with_conditional_blocks(module.body):
        if isinstance(statement, DEFINITION_NODES):
            names.add(statement.name)
        elif isinstance(statement, ast.Import):
            names.update(
                alias.asname or alias.name.split(".", maxsplit=1)[0]
                for alias in statement.names
            )
        elif isinstance(statement, ast.ImportFrom):
            names.update(
                alias.asname or alias.name
                for alias in statement.names
                if alias.name != "*"
            )
        elif isinstance(statement, ast.Assign):
            for target in statement.targets:
                _add_target_names(names, target)
        elif isinstance(statement, ast.AnnAssign):
            _add_target_names(names, statement.target)
        elif (name := _type_alias_name(statement)) is not None:
            names.add(name)
    return names


def _type_alias_name(statement: ast.stmt) -> str | None:
    type_alias = getattr(ast, "TypeAlias", None)
    if type_alias is None or not isinstance(statement, type_alias):
        return None
    name = getattr(statement, "name", None)
    if isinstance(name, ast.Name):
        return name.id
    return None


def _add_target_names(names: set[str], target: ast.expr) -> None:
    if isinstance(target, ast.Name):
        names.add(target.id)
    elif isinstance(target, SEQUENCE_TARGET_NODES):
        for element in target.elts:
            _add_target_names(names, element)


def _add_public(names: set[str], name: str) -> None:
    if not name.startswith("_"):
        names.add(name)


def _mutates_all(module: ast.Module) -> bool:
    for statement in _statements_with_conditional_blocks(module.body):
        if isinstance(statement, ast.AugAssign) and _is_all_target(statement.target):
            return True
        if isinstance(statement, ast.Expr) and isinstance(statement.value, ast.Call):
            call = statement.value
            if isinstance(call.func, ast.Attribute) and _is_all_target(call.func.value):
                return True
    return False


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
