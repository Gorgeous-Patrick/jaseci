Collection values in Jac support both literal syntax and powerful comprehension expressions for creating and transforming collections.

**Dict Comprehension**

Lines 5-6 show dictionary comprehension: `{num: num ** 2 for num in range(1, 6)}`. This creates a dictionary where keys are numbers 1-5 and values are their squares. The syntax is `{key_expr: value_expr for var in iterable}`.

**Set Comprehension**

Lines 9-10 demonstrate set comprehension with a filter: `{num ** 2 for num in range(1, 11) if num % 2 == 0}`. This creates a set of squares of even numbers. The `if` clause filters which elements are included.

**Generator Comprehension**

Lines 13-14 show generator comprehension using parentheses: `(num ** 2 for num in range(1, 6))`. Generators produce values lazily on demand rather than creating the entire collection in memory. Line 14 converts it to a list for printing.

**List Comprehension**

Lines 17-18 demonstrate list comprehension: `[num ** 2 for num in range(1, 6) if num != 3]`. Square brackets create a list, and the `if` clause excludes the number 3.

**Multiple For Clauses**

Lines 21-22 show nested iteration in comprehensions: `[x * y for x in [1, 2, 3] for y in [10, 20]]`. This produces all combinations of x and y values: [10, 20, 20, 40, 30, 60].

**Multiple If Clauses**

Lines 25-26 demonstrate multiple filter conditions: `[x for x in range(20) if x % 2 == 0 if x % 3 == 0]`. Only numbers divisible by both 2 and 3 are included (i.e., multiples of 6).

**Async Comprehension**

Line 29 (commented) mentions async comprehension syntax for asynchronous iteration: `[x async for x in async_generator()]`.

**Dictionary Literals**

Lines 32-33 show basic dictionary syntax: `{"a": "b", "c": "d"}`. Keys and values are separated by colons, pairs by commas.

**Dictionary Unpacking**

Lines 36-38 demonstrate dictionary unpacking with `**`: `{**base_dict, "z": 3}`. This spreads all key-value pairs from `base_dict` into the new dictionary and adds a new pair.

**Set Literals**

Lines 41-42 show set literals: `{"a", "b", "c"}`. Braces with comma-separated values (not key-value pairs) create a set.

**Tuple Literals**

Lines 45-46 show tuple literals: `("a", "b", "c")`. Parentheses with comma-separated values create an immutable tuple.

**List Literals**

Lines 49-50 show list literals: `['a', 'b', 'c']`. Square brackets with comma-separated values create a mutable list.

**Empty Collections**

Lines 53-56 demonstrate empty collection syntax:
- Empty list: `[]`
- Empty dict: `{}` (note: `{}` creates a dict, not a set)
- Empty tuple: `()`
- Empty set: `set()` (must use function call since `{}` is reserved for empty dict)

**Trailing Commas**

Lines 60-63 show that trailing commas are allowed in collection literals: `[1, 2, 3,]`. This is useful for version control as it allows adding items without modifying the previous line.

**Nested Comprehensions**

Lines 66-67 demonstrate nested list comprehensions: `[[i * j for j in range(3)] for i in range(3)]`. This creates a 2D matrix where each element is the product of its row and column indices.