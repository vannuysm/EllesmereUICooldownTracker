"""Shared runtime fixtures, category markers, and optional performance reporting."""
import json
from pathlib import Path
import sys

import pytest

from tests.lua_runtime import LuaHarness, ROOT, RUNTIMES


def pytest_addoption(parser):
    parser.addoption(
        "--performance-report",
        metavar="PATH",
        help="Write observational performance metrics as JSON to PATH",
    )


def pytest_configure(config):
    config._euict_performance_metrics = []


def pytest_sessionstart(session):
    if sys.platform == "win32":
        # LuaJIT uses handled Windows exceptions to unwind Lua errors. Python's
        # fault handler logs each one as a fatal exception even when pcall handles it.
        import faulthandler

        faulthandler.disable()


def pytest_collection_modifyitems(items):
    for item in items:
        category = item.path.relative_to(ROOT / "tests").parts[0]
        item.add_marker(category)


@pytest.fixture(params=RUNTIMES, ids=RUNTIMES)
def lua_runtime_name(request):
    return request.param


@pytest.fixture
def lua_harness(lua_runtime_name):
    return LuaHarness.create(lua_runtime_name)


@pytest.fixture
def record_performance(request, lua_runtime_name):
    def record(**metrics):
        request.config._euict_performance_metrics.append(
            {"test": request.node.nodeid, "runtime": lua_runtime_name, **metrics}
        )

    return record


def pytest_sessionfinish(session):
    destination = session.config.getoption("--performance-report")
    if destination:
        path = Path(destination)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(
                {"schema": 1, "measurements": session.config._euict_performance_metrics},
                indent=2,
                sort_keys=True,
            ) + "\n",
            encoding="utf-8",
        )
