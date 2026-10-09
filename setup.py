from setuptools import setup, Extension
from pathlib import Path

from builder import ZigBuilder

zaml = Extension("zaml", sources=["zamlmodule.zig"])

setup(
    name="zaml",
    version="0.2.0",
    url="https://github.com/niranjanaryan/zaml-elixir",
    description="Fast YAML parser for Python, built with Zig + libyaml",
    ext_modules=[zaml],
    cmdclass={"build_ext": ZigBuilder},
    long_description=(Path(__file__).parent / "README.md").read_text(encoding="utf-8"),
    long_description_content_type="text/markdown",
    py_modules=["builder"],
)
