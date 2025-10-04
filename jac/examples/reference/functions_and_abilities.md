Functions and abilities in Jac define callable units of code with various modifiers including access control, abstract declarations, variadic parameters, async support, and walker-specific abilities.

**Basic Functions with Type Annotations**

Lines 5-7 show a function with typed parameters and return type: `def divide(x: float, y: float) -> float`. Lines 10-12 demonstrate a function with only a return type annotation, no parameters.

**Static Functions with Access Tags**

Lines 18-20 show a static function with private access: `static def:priv multiply(a: float, b: float) -> float`. Static functions belong to the class rather than instances.

**Abstract Methods**

Line 23 shows abstract method declaration: `def substract -> float abs`. The `abs` keyword marks it as abstract - subclasses must implement it.

**Forward Declarations**

Lines 26, 29 show function signatures without bodies:
- Line 26: `def add(number: float, *a: tuple) -> float;` - forward declaration with variadic args
- Line 29: `def configure(**options: dict) -> dict;` - forward declaration with keyword args

**Variadic Parameters**

Line 51 shows `*a: tuple` which collects additional positional arguments into a tuple. Line 29 shows `**options: dict` which collects keyword arguments into a dictionary.

**Implementation Blocks**

Lines 50-53 show implementing a forward-declared function: `impl Calculator.add` provides the body for the previously declared `add` method.

**Inheritance and Overriding**

Lines 43-47 show `Substractor(Calculator)` inheriting from Calculator and implementing the abstract `substract` method.

**Walker Abilities**

Lines 56-71 demonstrate walker abilities using `can` statements:
- Lines 58-60: `can initialize with entry` - triggers when walker starts
- Lines 63-65: `can cleanup with exit` - triggers when walker finishes
- Abilities define behavior at specific points in walker execution

**Async Functions and Abilities**

Lines 74-76 show async function: `async def fetch_data(url: str) -> dict`. Lines 80-82 show async ability: `async can process with entry`.

**Decorators**

Lines 86-93 demonstrate function decorators: `@logger` is applied to `logged_function`.

**Abstract Abilities**

Lines 99-101 show abstract walker ability: `can must_implement with entry abs` - subclasses must provide implementation.

**Commented Advanced Features**

Lines 32, 35, 38-40, 68-70, 96 show commented syntax for positional-only parameters (`/`), keyword-only parameters (`*`), override keyword, and expression-based function proxying.