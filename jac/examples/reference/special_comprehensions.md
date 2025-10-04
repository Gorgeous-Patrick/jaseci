Jac provides two special comprehension syntaxes that extend Python-style comprehensions: filter comprehensions and assign comprehensions. These operate on collections of objects to filter or modify them.

**Filter Comprehension Syntax**

Line 20 demonstrates filter comprehension using the `?` operator: `apple(?x >= 0, x <= 15)`. This syntax filters a collection based on conditions applied to object attributes.

The general form is `collection(?condition1, condition2, ...)` where:
- `collection` is a list, set, or other iterable of objects
- `?` indicates a filter operation
- Conditions are comma-separated expressions evaluated against each object's attributes
- Each condition references attributes directly (like `x >= 0` where `x` is an attribute)

In this example, the filter checks if objects in `apple` have `x` attributes between 0 and 15 (inclusive). Since all `TestObj` instances are created with `random.randint(0, 15)` on line 6, all objects satisfy these conditions, so the filtered result equals the original list.

**Filter Comprehension Semantics**

The filter comprehension evaluates each condition for every object in the collection:
1. For each object, check if all conditions are true
2. Include the object in the result if all conditions pass
3. Return a new collection containing only matching objects

Multiple conditions are combined with AND logic - all conditions must be true for an object to be included.

**Assign Comprehension Syntax**

Line 34 demonstrates assign comprehension using the `=` prefix: `[x, y](=apple=5, banana=7)`. This syntax assigns values to attributes across multiple objects in a collection.

The general form is `collection(=attr1=val1, attr2=val2, ...)` where:
- `collection` is a list or other iterable of objects
- `=` prefix indicates an assign operation
- Attribute assignments are comma-separated in the form `attr=value`
- All objects in the collection have the specified attributes set to the given values

In this example, both `x` and `y` (instances of `MyObj`) have their `apple` attribute set to `5` and `banana` attribute set to `7`. The comprehension returns the modified collection, which is assigned to `mvar`.

**Assign Comprehension Semantics**

The assign comprehension modifies objects in place:
1. For each object in the collection
2. Set each specified attribute to its corresponding value
3. Return the collection (now containing modified objects)

This is a mutating operation - the original objects are modified, not copies.

**Object Setup**

Lines 5-9 define `TestObj` with three integer attributes (`x`, `y`, `z`), each initialized with a random value between 0 and 15. Lines 14-16 create 100 instances of `TestObj` and append them to the `apple` list, providing test data for the filter comprehension.

Lines 23-26 define `MyObj` with two integer attributes (`apple` and `banana`), both defaulting to 0. Lines 29-30 create two instances that will be modified by the assign comprehension.

**Combining Comprehensions**

While not shown in this example, filter and assign comprehensions can be chained or combined:
- Filter then assign: `collection(?condition)(=attr=value)` - filter objects, then modify survivors
- Multiple filters: `collection(?cond1)(?cond2)` - apply successive filters

**Use Cases**

**Filter comprehensions** are useful for:
- Finding objects matching specific criteria in graph traversals
- Selecting nodes or edges based on attribute values
- Data filtering in walker operations

**Assign comprehensions** are useful for:
- Bulk updates to object attributes
- Initializing or resetting state across collections
- Modifying graph node or edge properties en masse

These comprehensions provide concise syntax for common operations on object collections, particularly useful in Jac's data-spatial programming model.
