# Quick Start Guide

## Installation

To get started with MTLLM, install the base package:

```bash
pip install mtllm
```

## AI-Integrated Function Example

Let's consider an example program where we attempt to categorize a person by their personality using an LLM. For simplicity we will be using names of historical figures.

### Standard Implementation

Traditional implementation of this program with a manual algorithm:

```jac linenums="1"

enum Personality {
    INTROVERT = "Introvert",
    EXTROVERT = "Extrovert",
    AMBIVERT = "Ambivert"
}

def get_personality(name: str) -> Personality {
    # Traditional approach: manual algorithm, prompt-engineered LLM call, etc.
}

with entry {
    name = "Albert Einstein";
    result = get_personality(name);
    print(f"{result.value} personality detected for {name}");
}
```

**Limitations**: Defining an algorithm in code for this problem is difficult, while integrating an LLM to perform the task would require manual prompt engineering, response parsing, and type conversion to be implemented by the developer.

### MTLLM Implementation

The `by` keyword abstraction enables functions to process inputs of any type and generate contextually appropriate outputs of the specified type:

#### Step 1: Configure LLM Model

```jac linenums="1"
import from mtllm {Model}

glob llm = Model(model_name="gpt-4o");
```

#### Step 2: Implement LLM-Integrated Function

Add `by llm` to enable LLM integration:

```jac linenums="1"
def get_personality(name: str) -> Personality by llm();
```

This will auto-generate a prompt for performing the task and provide an output that strictly adheres to the type `Personality`.

#### Step 3: Execute the Application

Set your API key and run:

```bash
export OPENAI_API_KEY="your-api-key-here"
jac run personality.jac
```

For complete usage methodologies of the `by` abstraction, refer to the [Usage Guide](./usage.md) for documentation on object methods, object instantiation, and multi-agent workflows.
