Unpack expressions use the `*` and `**` operators to expand collections inline, enabling concise collection composition and flexible function calls.

**List Unpacking with Asterisk**

Lines 9-12 demonstrate list unpacking using the `*` operator. Line 11 shows `[*first_list, *second_list]`, which unpacks both lists and combines their elements into a new list.

The unpacking works as follows:
- `*first_list` expands to `1, 2, 3, 4, 5`
- `*second_list` expands to `5, 8, 7, 6, 9`
- Combined: `[1, 2, 3, 4, 5, 5, 8, 7, 6, 9]`

This provides a clean way to concatenate lists without using the `+` operator or `extend()` method.

**Dictionary Unpacking with Double Asterisk**

Lines 15-19 demonstrate dictionary unpacking using the `**` operator. Line 19 shows `{**first_dict, **second_dict}`, which unpacks both dictionaries and merges them into a new dictionary.

The unpacking works as follows:
- `**first_dict` expands to `'a':1, 'b':2`
- `**second_dict` expands to `'c':3, 'd':4`
- Combined: `{'a':1, 'b':2, 'c':3, 'd':4}`

If both dictionaries had the same key, the rightmost dictionary's value would take precedence.

**Unpacking in Function Calls**

Lines 22-23 demonstrate unpacking in function arguments. The function `combine_via_func` (lines 3-5) expects four integer parameters: `a`, `b`, `c`, and `d`.

Line 22: `combine_via_func(**combined_dict)` unpacks the dictionary as keyword arguments:
- `combined_dict` is `{'a':1, 'b':2, 'c':3, 'd':4}`
- Unpacking passes `a=1, b=2, c=3, d=4` to the function
- Returns `1 + 2 + 3 + 4 = 10`

Line 23: `combine_via_func(**first_dict, **second_dict)` unpacks two dictionaries in the same call:
- `**first_dict` provides `a=1, b=2`
- `**second_dict` provides `c=3, d=4`
- Same result: `10`

**Unpacking Operators**

| Operator | Works With | Use Case | Example |
|----------|-----------|----------|---------|
| `*` | Sequences (lists, tuples) | Expand elements | `[*list1, *list2]` |
| `**` | Mappings (dicts) | Expand key-value pairs | `{**dict1, **dict2}` |

**Multiple Unpacking**

You can unpack multiple collections in a single expression:
- Lists: `[*a, *b, *c]` combines three lists
- Dicts: `{**x, **y, **z}` merges three dictionaries
- Function calls: `func(**d1, **d2)` passes arguments from two dictionaries

**Unpacking in Assignment (Currently Unsupported)**

Line 26 shows a commented-out example of unpacking in assignment: `a, *rest, b = [1, 2, 3, 4, 5]`. This would:
- Assign first element to `a` (1)
- Assign middle elements to `rest` ([2, 3, 4])
- Assign last element to `b` (5)

This feature is shown but appears to be a TODO item.

**Literal Collection Building**

Unpacking is particularly powerful for building collections:
- Combining lists: `combined = [*base_list, new_item, *other_list]`
- Merging dictionaries: `config = {**defaults, **user_settings}`
- Mixed content: `result = [1, 2, *middle_values, 9, 10]`

**Use Cases**

Unpacking expressions are useful for:
- Combining multiple collections without loops
- Merging configurations with override precedence
- Passing collected arguments to functions
- Building collections with interspersed literal values
- Creating shallow copies with modifications: `{**original, 'key': new_value}`

**Shallow Copy Semantics**

When unpacking creates a new collection, it performs a shallow copy:
- New outer collection is created
- Elements/values themselves are not copied
- Modifying nested objects affects both collections
