Semstrings (semantic strings) are Jac's mechanism for providing semantic annotations and context that enrich the meaning available to AI models. The `sem` keyword bridges the gap between code semantics and AI understanding by allowing developers to provide explicit semantic context that works alongside the implicit meaning extracted from code structure (function names, parameter types, return types).

**LLM Model Setup**

Lines 3-8 set up the LLM model that will implement the function. Line 3 imports the `Model` class from the `byllm` module. Lines 5-8 create a global LLM instance using `glob llm = Model(...)`, specifying the model name as `"mockllm"` and providing mock outputs for testing purposes. In production, this would connect to an actual LLM service.

**Function Declaration with by llm()**

Line 11 demonstrates delegating a function's implementation to an LLM using the `by llm()` syntax: `def generate_password() -> str by llm();`. The `by` keyword is what handles the actual delegation of implementation to the AI model. Jac automatically extracts semantic meaning from the function's name (`generate_password`), parameter types, return type (`str`), and surrounding context to generate appropriate prompts for the AI model.

The function signature includes:
- Function name: `generate_password` (provides semantic intent)
- Return type: `-> str` (helps AI understand expected output format)
- Implementation directive: `by llm()` delegates implementation to the AI model

**Semantic String Definition with sem Keyword**

Lines 14-21 use the `sem` keyword to provide additional semantic context that enriches what the AI model knows beyond just the function signature. The syntax is `sem function_name = """description""";`, where:
- `sem` is the keyword indicating a semantic annotation
- `generate_password` matches the function name from line 11
- The triple-quoted string contains explicit requirements and constraints

The semantic string on lines 14-21 provides detailed requirements for password generation:
- At least 8 characters long
- Contains uppercase letters
- Contains lowercase letters
- Contains digits
- Contains special characters

**How sem and by Work Together**

When `generate_password()` is called on line 24, the following happens:
1. The `by llm()` clause delegates implementation to the AI model
2. Jac automatically generates a prompt using the function's name, parameters, and return type
3. The semantic annotation from `sem generate_password` provides additional context that enriches the AI's understanding
4. The AI model uses both the implicit semantics (from the code structure) and explicit semantics (from the `sem` annotation) to generate appropriate output
5. The response is returned as the function's output

**Execution**

Line 24 calls the LLM-implemented function like any normal function: `password = generate_password();`. The caller doesn't need to know or care that the function is implemented by an LLM rather than traditional code. Line 25 prints the generated password.

**Use Cases**

The `sem` keyword is particularly useful for:
- Providing explicit requirements and constraints that supplement function signatures
- Including examples that serve as few-shot learning data for AI models
- Clarifying domain-specific terminology or abbreviations (e.g., `sem Person.yod = "Year of Death"`)
- Documenting behavioral requirements that aren't captured by type signatures alone
- Adding context about tool usage when integrating external functions with AI models

**Advantages**

The semantic annotation approach provides several benefits:
- **Context-Rich**: Enriches AI understanding beyond what code structure alone provides
- **Explicit Semantics**: Unlike comments, semantic annotations become part of the program's execution context within the MTP (meaning-typed programming) system
- **Maintainable**: Natural language descriptions work alongside type annotations to create clear contracts
- **Flexible**: Works with both the `by` keyword for AI delegation and as standalone documentation
- **Type-safe**: Complements rather than replaces the type system, ensuring both semantic and structural correctness

**Implementation Note**

In this example, `mockllm` is used with predefined outputs (line 7) for testing purposes. In real applications, you would configure an actual LLM model (like GPT, Claude, or other models) to interpret the semantic strings and generate appropriate outputs.
