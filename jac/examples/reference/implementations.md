Implementation blocks (`impl`) in Jac provide bodies for forward-declared elements, separating interface declarations from their implementations.

**Forward Declarations**

Lines 4, 6, 8 show forward declarations using semicolons:
- Line 4: `def foo -> str;` - function signature without body
- Line 6: `obj vehicle;` - object declaration without members
- Line 8: `enum Size;` - enum declaration without values

Forward declarations allow:
- Separating interface from implementation
- Resolving circular dependencies
- Organizing code with headers and implementations

**Function Implementation**

Lines 11-13 implement the `foo` function: `impl foo -> str { return ("Hello"); }`. The signature matches the forward declaration, and the `impl` block provides the implementation.

**Object Implementation**

Lines 16-18 implement the `vehicle` object: `impl vehicle { has name: str = "Car"; }`. The implementation adds the object's members and structure.

**Enum Implementation**

Lines 21-25 implement the `Size` enum: `impl Size { Small=1, Medium=2, Large=3 }`. Enum implementations provide the member names and values.

**Implementation Pattern**

The typical pattern is:
1. Forward declare at the top (interface/signature)
2. Implement later in the file or separate module
3. Compile succeeds because signature is known before use

**Usage**

Lines 28-31 demonstrate using the implemented elements:
- `vehicle()` creates an instance
- `foo()` calls the function
- `Size.Medium.value` accesses enum member

This separation is useful for:
- Large codebases with many interdependent types
- API design where signatures are stable but implementation evolves
- Generated code where signatures come from one source, implementations from another

**Comparison to Other Languages**

This pattern is similar to:
- C/C++ header/source file separation
- Interface/implementation splitting in various OOP languages
- Protocol/implementation separation in some functional languages