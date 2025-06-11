import os
import datetime as dt
from math import sqrt as square_root, log
import sys

sys.path.append(os.path.dirname(__file__))
from base_module_structure import add, subtract

for i in range(int(square_root(dt.datetime.now().year))):
    print(os.getcwd(), add(i, subtract(i, 1)), int(log(i + 1)))
