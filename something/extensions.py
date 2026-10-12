"""The extensions: what is added to the core, one file per extension.

The core knows only Herdr. Everything specific to a harness lives in a file of `extensions/`: dropping it in adds
it, deleting it removes it. An extension that does not load is reported in the state, and nothing else stops. What
an extension declares: README.md, "Writing an extension".
"""
import importlib.util
from pathlib import Path

from . import guards, herdr

FOLDER = Path(__file__).resolve().parent.parent / "extensions"


def import_file(path):
    """The module of an extension file, loaded by its path. Raises what the file raises."""
    path = Path(path)
    spec = importlib.util.spec_from_file_location(f"something_extension_{path.stem}", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load(folder=FOLDER):
    """(readers by harness, extensions as the state reports them) from the `*.py` files of the folder.
    A file whose name starts with "_" or with a dot is ignored: a toolbox, or what a system or an editor leaves
    next to a file. Never raises: an extension that is rejected or broken is in the list with the sentence that
    says why, and is not loaded."""
    readers, reported = {}, []
    for path in sorted(Path(folder).glob("[!_.]*.py")):
        harness = None
        try:
            module = import_file(path)
            harness = guards.text(getattr(module, "HARNESS", None))
            error = _rejection(module, harness, readers)
            if error is None:
                herdr.open_reads(getattr(module, "HERDR", ()))
                readers[harness] = module
        except (Exception, SystemExit) as e:    # it raises or exits on import, or asks Herdr for what is not allowed
            error = guards.clip(f"{type(e).__name__}: {e}", 200)
        reported.append({"name": path.stem, "harness": harness, "error": error})
    return readers, reported


def _rejection(module, harness, readers):
    """The sentence that says why a module is not an acceptable reader, or None if it is one."""
    if harness is None:
        return "HARNESS is missing, the name of the harness the extension can read"
    missing = [name for name in ("session", "read") if not callable(getattr(module, name, None))]
    if missing:
        return f"{' and '.join(missing)} missing"
    if harness in readers:
        return f'the harness "{harness}" already has a reader'
    return None
