#!/usr/bin/env python3
"""Regenerate the HPS file/GPIO source fixtures from their production source."""
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

root = Path(__file__).resolve().parents[2]
module_path = root / "tools" / "expansion_adapter" / "connected.py"
spec = spec_from_file_location("connected_source", module_path)
if spec is None or spec.loader is None:
    raise RuntimeError("cannot load source transport extractor")
module = module_from_spec(spec)
spec.loader.exec_module(module)
out = root / "simulation" / "fax_bind" / "source_transport"
out.mkdir(parents=True, exist_ok=True)
print(module.extract(out))
