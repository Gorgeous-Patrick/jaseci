Subscripted and dotted expressions provide syntax for accessing elements in collections and attributes on objects, forming the foundation of data access in Jac.

**Dotted Expressions (Attribute Access)**

Line 8 demonstrates dotted notation for accessing object attributes: `Sample().my_list` and `Sample().my_dict`. The dot operator `.` accesses an attribute or method on an object. The syntax is `object.attribute`, where:
- `object` is an expression that evaluates to an object instance
- `attribute` is the name of the attribute to access

In this example, `Sample()` creates a new instance of the `Sample` class, and `.my_list` accesses its `my_list` attribute.

**Subscripted Expressions (Index/Key Access)**

Line 8 also demonstrates subscript notation for accessing collection elements: `Sample().my_list[2]` and `Sample().my_dict["name"]`. The subscript operator `[...]` accesses an element by index (for sequences) or key (for mappings).

For lists/sequences:
- `Sample().my_list[2]` accesses the element at index 2 (the third element, since indexing is zero-based)
- In this case, `my_list` is `[1, 2, 3]`, so `[2]` returns `3`

For dictionaries/mappings:
- `Sample().my_dict["name"]` accesses the value associated with key `"name"`
- In this case, `my_dict` is `{"name":"John", "age": 30}`, so `["name"]` returns `"John"`

**Chaining Operations**

Line 8 shows chaining dotted and subscripted expressions: `Sample().my_list[2]` chains object instantiation, attribute access, and subscripting. This chains operations left-to-right:
1. `Sample()` - Creates an instance
2. `.my_list` - Accesses the `my_list` attribute
3. `[2]` - Subscripts into the list

Similarly, `Sample().my_dict["name"]` chains:
1. `Sample()` - Creates an instance
2. `.my_dict` - Accesses the `my_dict` attribute
3. `["name"]` - Subscripts into the dictionary

**Global Tuple Assignment**

Line 8 uses tuple unpacking in a global declaration: `glob (first, second) = (...)`. This declares two global variables:
- `first` is assigned the value `Sample().my_list[2]` which evaluates to `3`
- `second` is assigned the value `Sample().my_dict["name"]` which evaluates to `"John"`

**Object Definition**

Lines 3-6 define the `Sample` object with two attributes:
- `my_list`: a list initialized to `[1, 2, 3]`
- `my_dict`: a dictionary initialized to `{"name":"John", "age": 30}`

**Subscript Semantics**

The subscript operator has different semantics depending on the type:

| Type | Subscript Behavior | Example |
|------|-------------------|---------|
| List | Access by integer index (0-based) | `[1, 2, 3][0]` → `1` |
| Tuple | Access by integer index (0-based) | `(1, 2, 3)[1]` → `2` |
| String | Access character by index | `"hello"[0]` → `"h"` |
| Dictionary | Access by key | `{"a": 1}["a"]` → `1` |
| Custom objects | Calls `__getitem__` method | Depends on implementation |

**Dot Operator Semantics**

The dot operator accesses:
- Instance attributes
- Instance methods
- Class attributes
- Properties
- Any attribute accessible via `__getattribute__` or `__getattr__`

**Execution**

When the program runs, line 11 prints the values of `first` and `second`, which are `3` and `"John"` respectively, demonstrating successful attribute access and subscripting operations.
