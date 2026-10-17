"""Representative codec scaling workloads; wall-clock time is never a CI gate."""
import statistics

import pytest


def decode_samples():
    factories = {
        "plain": lambda n: 'FCT1:{data={future="' + "x" * n + '"}}',
        "escaped": lambda n: 'FCT1:{data={future="' + "\\q" * (n // 2) + '"}}',
        "whitespace": lambda n: "FCT1:{data={" + " " * n + "}}",
        "missing_equals": lambda n: "FCT1:{data={" + "k" * (n // 2) + " " * (n // 2) + "}}",
        "bad_exponent": lambda n: "FCT1:{data={cd={size=" + "9" * (n - 2) + "e+}}}",
    }
    for name, factory in factories.items():
        for size in (8192, 32768, 122880):
            yield pytest.param(
                name, factory(size), name not in {"missing_equals", "bad_exponent"},
                id=f"{name}-{size}",
            )
    for groups in (2, 8, 15):
        row = "{" + "true," * 256 + "},"
        yield pytest.param(
            "many_entries", "FCT1:{data={future={" + row * groups + "}}}", True,
            id=f"many_entries-{groups * 256}",
        )


def measure(operation, value, batch):
    batch(operation, value, 5)
    samples = [batch(operation, value, 10) for _ in range(3)]
    return {
        "seconds_per_operation": statistics.median(sample[0] for sample in samples),
        "allocated_kib_per_operation": statistics.median(sample[1] for sample in samples),
        "samples": len(samples),
        "operations_per_sample": 10,
    }


@pytest.mark.parametrize("workload,raw,valid", list(decode_samples()))
def test_decode_workload(codec_runtime, workload, raw, valid, record_performance):
    _, ns, batch = codec_runtime
    result = ns.ProfileCodec.Decode(raw)
    candidate, error = result if isinstance(result, tuple) else (result, None)
    if valid:
        assert candidate is not None
    else:
        assert candidate is None and isinstance(error, str)
    record_performance(
        workload=workload, operation="decode", input_bytes=len(raw.encode("utf-8")),
        **measure(ns.ProfileCodec.Decode, raw, batch),
    )


@pytest.mark.parametrize("size", (32, 128, 512))
def test_encode_dictionary(codec_runtime, size, record_performance):
    lua, ns, batch = codec_runtime
    data = lua.table_from({f"key{i:04d}": True for i in range(size, 0, -1)})
    encoded = ns.Kit.Encode(data)
    assert ns.Kit.Encode(ns.Kit.Decode(encoded)) == encoded
    record_performance(
        operation="encode_dictionary", keys=size, output_bytes=len(encoded),
        **measure(ns.Kit.Encode, data, batch),
    )


def test_encode_deep_payload(codec_runtime, record_performance):
    lua, ns, batch = codec_runtime
    data = lua.table_from({"payload": "x" * 64000})
    for _ in range(12):
        data = lua.table_from({"child": data})
    encoded = ns.Kit.Encode(data)
    # This workload exercises the encoder's maximum table depth. The decoder
    # also counts the leaf scalar, so a round trip is not its contract here.
    assert encoded == "{child=" * 12 + '{payload="' + "x" * 64000 + '"}' + "}" * 12
    record_performance(
        operation="encode_deep_payload", depth=12, payload_bytes=64000,
        **measure(ns.Kit.Encode, data, batch),
    )
