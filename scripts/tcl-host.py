"""Host genuine Tcl 8.6 using the interpreter shipped with Python on Windows.

Python does no parsing or mathematics. Set WONKYCALC_TCL to use tclsh instead.
"""
import pathlib
import sys
import tkinter

interp = tkinter.Tcl()
try:
    interp.eval(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
except tkinter.TclError as error:
    print(error, file=sys.stderr)
    sys.exit(1)
