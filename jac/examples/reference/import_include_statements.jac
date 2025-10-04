# Import and Include statements

# Include statement (includes module directly)
import os;

# Import with alias
import datetime as dt;

# Multiple imports in one statement
import sys, json, random;

# Import from with braces and items
import from math { sqrt as square_root, log, pi }

# Import from with trailing comma
import from collections { defaultdict, Counter, }

# Relative imports with dots (from_path with DOT/ELLIPSIS)
# import from . { local_module };           # Current package
# import from .. { parent_module };         # Parent package
# import from ... { grandparent_module };   # Grandparent package

# Import from with only dots (current package)
# import from . { utils };

with entry {
    for i in range(5) {
        print(
            os.getcwd(),
            square_root(i + 1),
            int(log(i + 1)),
            pi
        );
    }
}
