import inspect
import spectrum_engine

lines = ["from typing import Any, List", ""]

for name in sorted(dir(spectrum_engine)):
    if name.startswith("_"):
        continue
    obj = getattr(spectrum_engine, name)
    if inspect.isfunction(obj):
        sig = inspect.signature(obj)
        params = ", ".join(p for p in sig.parameters)
        lines.append(f"def {name}({params}) -> Any: ...")
    elif inspect.isclass(obj):
        lines.append(f"class {name}:")
        lines.append("    ...")
    lines.append("")

open("spectrum_engine.pyi", "w").write("\n".join(lines))
print("Generated spectrum_engine.pyi")