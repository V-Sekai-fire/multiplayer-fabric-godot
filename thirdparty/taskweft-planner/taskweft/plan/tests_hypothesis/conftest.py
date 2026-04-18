"""Add plan directory to sys.path so ipyhop and examples are importable."""
import sys
from pathlib import Path

_plan_dir = str(Path(__file__).resolve().parent.parent)
if _plan_dir not in sys.path:
    sys.path.insert(0, _plan_dir)
