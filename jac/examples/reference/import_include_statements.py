from __future__ import annotations
from jaclang.runtimelib.builtin import *
from jaclang import JacMachineInterface as _jl
import os
import datetime as dt
import sys, json, random
from math import sqrt as square_root, log, pi
from collections import defaultdict, Counter
for i in range(5):
    print(os.getcwd(), square_root(i + 1), int(log(i + 1)), pi)
