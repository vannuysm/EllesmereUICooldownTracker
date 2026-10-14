"""Small pytest bridge for executing the real Lua addon in isolated runtimes."""
from dataclasses import dataclass
from functools import lru_cache
import importlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
RUNTIMES = ("lua51", "luajit21")


@dataclass
class LuaHarness:
    lua: object
    context: object

    @classmethod
    def create(cls, runtime: str, *, standalone: bool = False):
        lua = importlib.import_module(f"lupa.{runtime}").LuaRuntime(
            unpack_returned_tuples=True
        )
        lua.globals().TEST_REPO_ROOT = ROOT.as_posix()
        lua.globals().TEST_ADDON_ROOT = SRC.as_posix()
        bootstrap = lua.execute(
            (ROOT / "tests/unit/support/bootstrap.lua").read_text(encoding="utf-8")
        )
        return cls(lua, bootstrap(standalone))

    def load(self, relative_path: str):
        source = (ROOT / relative_path).read_text(encoding="utf-8")
        loader = self.lua.eval(
            "function(source, name, ctx) return assert(loadstring(source, '@' .. name))(ctx) end"
        )
        return loader(source, relative_path, self.context)

    def register(self, relative_path: str):
        self.load(relative_path)
        return self.context.cases

    def run_case(self, relative_path: str, case_name: str):
        cases = self.register(relative_path)
        for index in range(1, len(cases) + 1):
            if cases[index]["name"] == case_name:
                cases[index]["run"]()
                return
        raise LookupError(f"Unknown case {case_name!r} in {relative_path}")


@lru_cache(maxsize=None)
def cases_for(relative_path: str) -> tuple[str, ...]:
    """Discover names only; execution gets a fresh harness for every case/runtime."""
    harness = LuaHarness.create("lua51")
    cases = harness.register(relative_path)
    names = [cases[index]["name"] for index in range(1, len(cases) + 1)]
    assert len(set(names)) == len(names), f"Duplicate case names in {relative_path}"
    return tuple(sorted(names))


def to_python(value):
    """Convert Lua result tables into portable JSON-compatible metric dictionaries."""
    if hasattr(value, "items"):
        return {key: to_python(item) for key, item in value.items()}
    return value
