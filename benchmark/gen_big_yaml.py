# Generates a large synthetic YAML file with `n` top-level keys for benchmarking.
import sys

try:
    import yaml as pyyaml
except ImportError:
    print("PyYAML is required to generate the benchmark YAML: pip install pyyaml")
    sys.exit(1)

n = int(sys.argv[1]) if len(sys.argv) > 1 else 100_000
out = sys.argv[2] if len(sys.argv) > 2 else "benchmark/big.yml"

data = {
    "a{i}".format(i=i): {
        "name": "name{i}".format(i=i),
        "value": i,
        "ratio": i * 0.5,
        "flag": i % 2 == 0,
        "tags": ["t{i}".format(i=i), "common"],
        "meta": {"created": "2024-01-01", "active": True},
    }
    for i in range(n)
}

with open(out, "w") as f:
    pyyaml.dump(data, f, Dumper=pyyaml.CSafeDumper, default_flow_style=False)

print("Wrote", out)
