"""Configure pytest to use importlib import mode, avoiding auto-import of holographic/__init__.py
which depends on the 'agent' package not available in the test environment."""
import sys
from pathlib import Path

# Ensure the taskweft root is on sys.path so we can do direct file imports
_taskweft_root = str(Path(__file__).resolve().parent.parent.parent)
if _taskweft_root not in sys.path:
    sys.path.insert(0, _taskweft_root)

collect_ignore = ["__init__.py"]
