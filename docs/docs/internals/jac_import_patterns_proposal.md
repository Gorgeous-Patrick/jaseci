# Jac Client Import Patterns - Implementation Status

This document provides a comprehensive reference of all JavaScript/ECMAScript import patterns and their Jac equivalents, showing which patterns are currently supported.

## Import Pattern Support Matrix

| Category | JavaScript Pattern | Jac Pattern | Status | Generated JavaScript | Notes |
|----------|-------------------|-------------|--------|---------------------|-------|
| **Category 1: Named Imports** |
| Single named | `import { useState } from 'react'` | `cl import from react { useState }` | ✅ Working | `import { useState } from "react";` | |
| Multiple named | `import { map, filter } from 'lodash'` | `cl import from lodash { map, filter }` | ✅ Working | `import { map, filter } from "lodash";` | |
| Named with alias | `import { get as httpGet } from 'axios'` | `cl import from axios { get as httpGet }` | ✅ Working | `import { get as httpGet } from "axios";` | |
| Mixed named + aliases | `import { createApp, ref as reactive } from 'vue'` | `cl import from vue { createApp, ref as reactive }` | ✅ Working | `import { createApp, ref as reactive } from "vue";` | |
| **Category 1: Relative Paths** |
| Single dot (current) | `import { helper } from './utils'` | `cl import from .utils { helper }` | ✅ Working | `import { helper } from "./utils";` | |
| Double dot (parent) | `import { format } from '../lib'` | `cl import from ..lib { format }` | ✅ Working | `import { format } from "../lib";` | |
| Triple dot (grandparent) | `import { settings } from '../../config'` | `cl import from ...config { settings }` | ✅ Working | `import { settings } from "../../config";` | Supports any number of dots |
| **Category 1: Module Prefix** |
| With jac: prefix | `import { renderJsxTree } from 'jac:client_runtime'` | `cl import from jac:client_runtime { renderJsxTree }` | ✅ Working | `import { renderJsxTree } from "client_runtime";` | Prefix stripped for resolution |
| **Category 2: Default Imports** |
| Default import | `import React from 'react'` | `cl import from react { default as React }` | ✅ Working | `import React from "react";` | Must use `cl` prefix |
| Default with relative | `import Component from './Button'` | `cl import from .Button { default as Component }` | ✅ Working | `import Component from "./Button";` | |
| **Category 4: Namespace Imports** |
| Namespace import | `import * as React from 'react'` | `cl import from react { * as React }` | ✅ Working | `import * as React from "react";` | Must use `cl` prefix |
| Namespace with relative | `import * as utils from './utils'` | `cl import from .utils { * as utils }` | ✅ Working | `import * as utils from "./utils";` | |
| **Category 3: Mixed Imports** |
| Default + Named | `import React, { useState } from 'react'` | `cl import from react { default as React, useState }` | ✅ Working | `import React, { useState } from "react";` | Order matters: default first |
| Default + Namespace | `import React, * as All from 'react'` | `cl import from react { default as React, * as All }` | ✅ Working | `import React, * as All from "react";` | Valid JS (rarely used) |
| Named + Namespace | `import * as _, { map } from 'lodash'` | `cl import from lodash { * as _, map }` | ⚠️ Generates | `import * as _, { map } from "lodash";` | **Invalid JavaScript** - not recommended |

## Unsupported Patterns

| Pattern | Why Not Supported | Workaround |
|---------|-------------------|------------|
| `default` or `*` in non-`cl` imports | No Python equivalent for default/namespace exports | Use `cl import` instead |
| Side-effect only imports | Not yet implemented | Use regular Python import for now |
| Dynamic imports | Runtime feature, not syntax | Use JavaScript directly or add to roadmap |
| Import assertions (JSON, CSS) | Stage 3 proposal, specialized | May add in future |

## Usage Rules

### 1. Client Import Requirement
- **Default imports** (`default as Name`) and **namespace imports** (`* as Name`) **MUST** use `cl` prefix
- **Named imports** work with or without `cl` prefix (but `cl` generates JavaScript)

### 2. Syntax Patterns

```jac
# ✅ Correct Usage
cl import from react { useState }                    # Category 1: Named
cl import from react { default as React }            # Category 2: Default
cl import from react { * as React }                  # Category 4: Namespace
cl import from react { default as React, useState }  # Category 3: Mixed

# ❌ Incorrect Usage
import from react { default as React }   # Error: default requires cl
import from lodash { * as _ }            # Error: namespace requires cl
cl import from lodash { * as _, map }    # Generates invalid JS
```

### 3. Relative Path Conversion

Jac uses Python-style dots for relative imports, which are automatically converted to JavaScript format:

| Jac Syntax | JavaScript Output | Description |
|------------|-------------------|-------------|
| `.utils` | `"./utils"` | Current directory |
| `..lib` | `"../lib"` | Parent directory |
| `...config` | `"../../config"` | Grandparent directory |
| `....deep` | `"../../../deep"` | Great-grandparent directory |

## Implementation Details

### Grammar
```lark
import_item: (KW_DEFAULT | STAR_MUL | named_ref) (KW_AS NAME)?
```

### Type Handling
- Regular named imports: `ModuleItem.name` is `Name`
- Default imports: `ModuleItem.name` is `Token(KW_DEFAULT)`
- Namespace imports: `ModuleItem.name` is `Token(STAR_MUL)`

### Validation
- `pyast_gen_pass.py`: Logs error if `default` or `*` used without `cl`
- `sym_tab_build_pass.py`: Only alias added to symbol table for default/namespace
- `esast_gen_pass.py`: Generates appropriate `ImportSpecifier`, `ImportDefaultSpecifier`, or `ImportNamespaceSpecifier`

## Testing

All patterns tested and verified in:
- `test_js_generation.py::test_category1_named_imports_generate_correct_js`
- `test_js_generation.py::test_category2_default_imports_generate_correct_js`
- `test_js_generation.py::test_category4_namespace_imports_generate_correct_js`

## Examples

### Full Feature Demo
```jac
cl {
    # Named imports
    import from react { useState, useEffect, useRef }
    import from lodash { map as mapArray, filter }

    # Default imports
    import from react { default as React }
    import from axios { default as axios }

    # Namespace imports
    import from date-fns { * as DateFns }
    import from .utils { * as Utils }

    # Mixed imports
    import from react { default as React, useState, useEffect }

    # Relative paths
    import from .components.Button { default as Button }
    import from ..lib.helpers { formatDate }
    import from ...config.constants { API_URL }

    def MyComponent() {
        let [count, setCount] = useState(0);
        let now = DateFns.format(new Date());
        axios.get(API_URL);

        return count;
    }
}
```

### Generated JavaScript Output
```javascript
import { useState, useEffect, useRef } from "react";
import { map as mapArray, filter } from "lodash";
import React from "react";
import axios from "axios";
import * as DateFns from "date-fns";
import * as Utils from "./utils";
import React, { useState, useEffect } from "react";
import Button from "./components.Button";
import { formatDate } from "../lib.helpers";
import { API_URL } from "../../config.constants";

function MyComponent() {
  let [count, setCount] = useState(0);
  let now = DateFns.format(new Date());
  axios.get(API_URL);
  return count;
}
```

## Status Summary

- ✅ **Category 1 (Named Imports)**: Fully implemented and tested
- ✅ **Category 2 (Default Imports)**: Fully implemented and tested
- ✅ **Category 3 (Mixed Imports)**: Working for default+named and default+namespace
- ✅ **Category 4 (Namespace Imports)**: Fully implemented and tested
- ✅ **Relative Paths**: Full support with automatic conversion
- ⚠️ **Named + Namespace Mix**: Generates but produces invalid JavaScript

**Last Updated**: 2025-10-22
