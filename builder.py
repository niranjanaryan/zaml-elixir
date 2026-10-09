import os
import platform
from setuptools.command.build_ext import build_ext
import sysconfig

_PREFIXES = ("/opt/homebrew", "/usr/local", "/usr")
_LIB_CANDIDATES = (
    "libyaml.dylib",
    "libyaml.so",
    "libyaml.a",
    "yaml.lib",
    "libyaml.lib",
)


def _find_libyaml():
    """Locate libyaml headers and library directory.

    Honours YAML_INCLUDE_DIR / YAML_LIB_DIR; otherwise probes the usual
    Homebrew / /usr/local / /usr prefixes. Returns (include, lib_dir), either
    of which may be None when nothing was found.
    """
    inc = os.environ.get("YAML_INCLUDE_DIR")
    lib_dir = os.environ.get("YAML_LIB_DIR")

    if not inc:
        for prefix in _PREFIXES:
            if os.path.exists(os.path.join(prefix, "include", "yaml.h")):
                inc = os.path.join(prefix, "include")
                break

    if not lib_dir:
        for prefix in _PREFIXES:
            candidate = os.path.join(prefix, "lib")
            if any(
                os.path.exists(os.path.join(candidate, name))
                for name in _LIB_CANDIDATES
            ):
                lib_dir = candidate
                break

    return inc, lib_dir


class ZigBuilder(build_ext):
    def build_extension(self, ext):
        assert len(ext.sources) == 1

        if not os.path.exists(self.build_lib):
            os.makedirs(self.build_lib)

        windows = platform.system() == "Windows"
        yaml_inc, yaml_lib_dir = _find_libyaml()

        self.spawn(
            [
                "zig",
                "build-lib",
                "-O",
                "ReleaseFast",
                "-lc",
                *(["-target", "x86_64-windows-msvc"] if windows else []),
                f"-femit-bin={self.get_ext_fullpath(ext.name)}",
                "-fallow-shlib-undefined",
                "-dynamic",
                *[f"-I{d}" for d in self.include_dirs],
                *([f"-I{yaml_inc}"] if yaml_inc else []),
                *([f"-L{yaml_lib_dir}"] if yaml_lib_dir else []),
                "-lyaml",
                *(
                    [
                        f"-L{sysconfig.get_config_var('installed_base')}\\Libs",
                        "-lpython3",
                    ]
                    if windows
                    else []
                ),
                ext.sources[0],
            ]
        )
