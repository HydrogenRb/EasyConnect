"""Optional independent SystemVerilog elaboration for development tests only."""

import os
import sys


SLANG = None
if os.environ.get("EASYCONNECT_SLANG_PATH"):
    sys.path.insert(0, os.environ["EASYCONNECT_SLANG_PATH"])
    import pyslang as SLANG


def check_files(testcase, sources, include_directory):
    if SLANG is None:
        return
    manager = SLANG.SourceManager()
    manager.addUserDirectories(str(include_directory))
    tree = SLANG.syntax.SyntaxTree.fromFiles([str(path) for path in sources], manager)
    compilation = SLANG.ast.Compilation()
    compilation.addSyntaxTree(tree)
    diagnostics = compilation.getAllDiagnostics()
    errors = [diag for diag in diagnostics if diag.isError()]
    testcase.assertFalse(errors, SLANG.DiagnosticEngine.reportAll(manager, errors))


def check_text(testcase, text):
    if SLANG is None:
        return
    tree = SLANG.syntax.SyntaxTree.fromText(text)
    compilation = SLANG.ast.Compilation()
    compilation.addSyntaxTree(tree)
    errors = [diag for diag in compilation.getAllDiagnostics() if diag.isError()]
    testcase.assertFalse(errors, SLANG.DiagnosticEngine.reportAll(tree.sourceManager, errors))
