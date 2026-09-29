"""Runs the Lua test files (tests/*_test.lua or the paths given) under Lua 5.4.

Usage: uv run tests/run.py [file_test.lua ...]
Exit status is 1 if any test fails or a test file cannot be loaded.
"""
import sys
from pathlib import Path

from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent


def run_file(path: Path) -> tuple[int, int]:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        f'package.path = "{ROOT}/?.lua;{ROOT}/lib/?.lua;{ROOT}/tests/?.lua;" .. package.path'
    )
    lua.execute(f'_G.TEST_ROOT = "{ROOT}"')
    try:
        lua.execute(path.read_text(encoding="utf-8"), )
    except Exception as exc:  # syntax or load-time error
        print(f"FAIL {path.name}: cannot load: {exc}")
        return 0, 1
    passed, failed, failures, skipped = lua.eval('require("luatest").run()')
    for failure in failures.values():
        print(f"FAIL {path.name}: {failure}")
    for skip in skipped.values():
        print(f"SKIP {path.name}: {skip}")
    print(f"{path.name}: {passed} passed, {failed} failed, {len(skipped)} skipped")
    return passed, failed


def main() -> int:
    files = [Path(a).resolve() for a in sys.argv[1:]] or sorted(
        (ROOT / "tests").glob("*_test.lua")
    )
    total_failed = 0
    for f in files:
        _, failed = run_file(f)
        total_failed += failed
    return 1 if total_failed else 0


if __name__ == "__main__":
    sys.exit(main())
