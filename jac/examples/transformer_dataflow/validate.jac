import from model { build }
import validation;
import os;
with entry { validation.main(build, os.path.dirname(__file__)); }
