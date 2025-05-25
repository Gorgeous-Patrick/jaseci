# Project Ideas for the Jac Community

This page lists potential projects that can be built using Jac, showcasing its unique capabilities in data spatial programming and AI integration with MTLLM.

---

## Project Idea: Rebuilding Aider with Jac and Data Spatial Programming

This project proposes rebuilding Aider, the AI pair programming tool, using Jac, leveraging its data spatial programming paradigm and the MTLLM (`by <llm>`) feature.

### Core Concepts

#### Aider's Functionality

Aider assists developers by:

1.  **Understanding Code Structure:** Analyzing the existing codebase to build a mental model.
2.  **Responding to Prompts:** Taking user requests (e.g., "add a new feature," "fix this bug," "refactor this code").
3.  **Generating Code Changes:** Producing code snippets or entire file modifications.
4.  **Applying Changes:** Integrating the generated code into the existing codebase.
5.  **Iterative Refinement:** Allowing users to review, accept, or reject changes, and provide further instructions.

#### Jac's Data Spatial Programming

In Jac, a codebase can be represented as a graph.

*   **Nodes:** Represent files, classes, functions, variables, comments, and other code constructs. Each node can have properties (e.g., file path, function signature, variable type, code content).
*   **Edges:** Represent relationships between these constructs (e.g., a function `calls` another function, a class `contains` a method, a file `imports` another file, a variable is `defined in` a function).
*   **Walkers:** Can traverse this code graph to understand its structure, identify relevant sections for a given prompt, and even apply modifications.

#### Jac's MTLLM (`by <llm>`)

The `by <llm>` feature allows Jac to delegate complex reasoning and generation tasks to Large Language Models.

*   **Natural Language Understanding:** An LLM can interpret user prompts for Aider.
*   **Code Generation:** An LLM can generate code snippets based on the prompt and the context derived from the code graph.
*   **Decision Making:** An LLM can decide which parts of the code graph are most relevant to a user's request.

### Proposed Architecture

1.  **Codebase Ingestion and Graph Building:**
    *   A walker traverses the target project directory.
    *   It creates nodes for each file and its constituent elements (classes, functions, imports, etc.).
    *   Edges are established to represent relationships (containment, calls, inheritance, dependencies).
    *   The code content of functions, classes, etc., can be stored as a property of the respective nodes. This process effectively creates a rich, queryable representation of the codebase.

2.  **User Prompt Handling:**
    *   The user's prompt (e.g., "add a login feature to the `User` class") is received.
    *   An MTLLM-powered ability, say `interpret_prompt_and_locate_context(prompt: str) -> list[Node] by <llm>()`, is used.
        *   This ability would leverage the LLM's understanding to identify which nodes (files, classes, functions) in the code graph are most relevant to the prompt.
        *   The LLM could be guided by providing it with schemas of the node types and their properties.

3.  **Information Retrieval and Contextualization (RAG-like):**
    *   Once relevant nodes are identified, their code content and the content of closely related nodes (e.g., functions called by a relevant function, or the class a relevant method belongs to) are retrieved.
    *   This information, along with the user's prompt, forms the context for the code generation step. This is analogous to the retrieval part of Retrieval Augmented Generation (RAG).

4.  **Code Generation and Modification Planning:**
    *   Another MTLLM-powered ability, `generate_code_changes(prompt: str, context: str) -> CodeEditPlan by <llm>()`, would take the user prompt and the retrieved context.
    *   `CodeEditPlan` could be a custom Jac object representing the proposed changes (e.g., new code to insert, existing code to modify/delete, target file and line numbers).
    *   The LLM generates the new code and a plan for how to integrate it. For example:
        ```jac
        obj CodeEdit {
            has file_path: str;
            has start_line: int;
            has end_line: int; // Can be same as start_line for insertions
            has new_content: str; // Empty if deleting
            has operation: str; // "insert", "replace", "delete"
        }

        obj CodeEditPlan {
            has edits: list[CodeEdit];
            has reasoning: str; // LLM's explanation for the changes
        }

        can \'Analyze user prompt and relevant code context to generate code modifications.\'
        generate_code_changes(prompt: str, current_code_snippets: dict[str, str]) -> CodeEditPlan by <llm>;
        ```

5.  **Applying Changes:**
    *   A walker receives the `CodeEditPlan`.
    *   It navigates to the target nodes (files) in the code graph.
    *   It applies the specified modifications to the `code_content` property of the relevant file nodes or directly to the source files.

6.  **Iteration and Refinement:**
    *   The user reviews the changes.
    *   If further modifications are needed, the process repeats, with the updated code graph and the new prompt.

### Advantages of this Approach

*   **Deep Code Understanding:** The data spatial graph provides a structured and queryable representation of the codebase, far richer than simple text parsing. Walkers can perform complex queries and analyses on this graph.
*   **Intelligent Contextualization:** By traversing the graph, the system can gather highly relevant context for the LLM, improving the quality of generated code.
*   **Flexible and Extensible:** New types of code analysis or modification walkers can be easily added. Different LLMs can be swapped in using the `by <llm>` syntax.
*   **Natural Language Interaction:** MTLLM simplifies the interface between the user's natural language requests and the structured code operations.
*   **Jac's Strengths:** Type safety, Pythonic syntax, and the ability to mix imperative, object-oriented, and data spatial paradigms make Jac a powerful tool for this kind of complex application.

### Project Steps

1.  **Define Core Jac Archetypes:**
    *   `FileNode`, `ClassNode`, `FunctionNode`, `ImportNode`, `VariableNode`, etc.
    *   `CallsEdge`, `ContainsEdge`, `ImportsEdge`, `DefinesEdge`, etc.
    *   `CodeParsingWalker` to build the initial graph from a directory.
2.  **Develop Prompt Interpretation Ability:**
    *   `interpret_prompt_and_locate_context` ability using MTLLM.
3.  **Implement Context Retrieval Walkers:**
    *   Walkers that, given a starting node, can gather relevant surrounding code (e.g., all methods in a class, all functions called by a given function).
4.  **Develop Code Generation Ability:**
    *   `generate_code_changes` ability using MTLLM to produce a `CodeEditPlan`.
5.  **Implement Code Application Walker:**
    *   A walker that takes a `CodeEditPlan` and applies it to the files.
6.  **Build CLI/Interface:**
    *   A way for the user to specify the target project and interact with the Jac-Aider.
7.  **Testing and Refinement:**
    *   Test with various coding tasks and refine the prompts, walkers, and MTLLM abilities.

This project would not only be a powerful demonstration of Jac's capabilities but also a valuable tool for the Jac community and potentially beyond. It pushes the boundaries of how AI can be integrated into the development lifecycle through a deeply code-aware, graph-based approach.

---

## Project Idea: Codebase Genius - AI-Powered Documentation Generator

This project envisions "Codebase Genius," an agentic system built with Jac that ingests a GitHub repository, performs a deep analysis of its structure using data spatial programming, and leverages a 1 billion parameter MTLLM (via the `by <llm>` syntax) to generate a rich suite of Markdown documentation. This documentation will meticulously describe the codebase's architecture and design, incorporating Mermaid diagrams for enhanced visual understanding.

### Core Concepts & Jac Implementation

1.  **Input Source:**
    *   A GitHub repository URL.

2.  **Codebase Analysis with Data Spatial Programming:**
    *   **Graph Representation:** The entire codebase (files, directories, modules, classes, functions, methods, data structures, comments, configuration files, etc.) will be parsed into a detailed data spatial graph.
        *   **Nodes:** Represent individual code entities. Properties could include raw code, parsed AST elements, docstrings, file paths, line numbers, and extracted metadata.
            *   Examples: `FileNode`, `DirectoryNode`, `ModuleNode`, `ClassNode`, `FunctionNode`, `MethodNode`, `VariableNode`, `CommentNode`.
        *   **Edges:** Represent the myriad relationships between these entities.
            *   Examples: `ImportsEdge`, `CallsEdge` (function/method calls), `InheritsFromEdge`, `ContainsEdge` (class contains method, module contains class), `DataFlowEdge`, `DependencyEdge`.
    *   **Analytical Walkers:** Specialized walkers will autonomously traverse and analyze this code graph:
        *   `RepoCloningWalker`: Clones the specified GitHub repository locally.
        *   `CodeParsingWalker`: Iterates through the codebase, potentially using Jac's parsing capabilities or integrating with existing language parsers, to construct the nodes and edges of the code graph.
        *   `ArchitectureAnalysisWalker`: Traverses the graph to identify high-level architectural patterns (e.g., MVC, Microservices, Layered), key components, modules, entry points, and their interactions. This walker might use heuristics or invoke MTLLM abilities for complex pattern recognition.
        *   `DependencyAnalysisWalker`: Maps out inter-module, inter-class, and inter-function dependencies to understand coupling, cohesion, and potential impact areas.
        *   `DiagramDataExtractionWalker`: Identifies and extracts structured data from the graph specifically for generating various Mermaid diagrams (e.g., class hierarchies for class diagrams, call sequences for sequence diagrams, component dependencies for architecture diagrams).

3.  **Documentation Generation with MTLLM (1B Parameter Model):**
    *   **Content Strategy & Outline:**
        *   An MTLLM-powered ability, `plan_documentation_structure(code_graph_summary: str, repo_metadata: dict) -> DocumentationOutline by <llm>()`, would analyze a summary of the code graph and repository metadata to determine an optimal structure for the documentation.
        *   `DocumentationOutline` would be a Jac object detailing the main sections, subsections, and the types of diagrams appropriate for each.
    *   **Markdown Section Generation:**
        *   For each section defined in the `DocumentationOutline`, an ability like `generate_markdown_section(section_topic: str, relevant_graph_extracts: list[NodeInfo], diagram_specs: list[MermaidSpec]) -> str by <llm>()` would:
            *   Receive the specific topic (e.g., "User Authentication Service").
            *   Be provided with relevant data extracted from the code graph by the analysis walkers (e.g., code snippets of relevant classes/functions, their relationships, and docstrings).
            *   Receive specifications for any Mermaid diagrams identified for this section.
            *   Generate descriptive text in Markdown, explaining the design, purpose, and interactions related to the topic, seamlessly embedding Mermaid diagram definitions.
    *   **Mermaid Diagram Generation:**
        *   A dedicated MTLLM ability, or a specialized part of `generate_markdown_section`, `generate_mermaid_code(diagram_type: str, elements: list, relationships: list) -> str by <llm>()`, would translate the structured data (extracted by `DiagramDataExtractionWalker`) into valid Mermaid syntax.
            *   Example: Given a list of class nodes and their inheritance edges, it would generate the Mermaid code for a class diagram.

4.  **Output:**
    *   A suite of interlinked Markdown files.
    *   A main `README.md` or `index.md` would serve as the entry point, providing an overview and navigation to other generated documents.
    *   Generated documentation will be stored in a user-specified output directory or a `docs` folder within the analyzed repository.

### Why Jac is the Right Tool

*   **Rich Code Representation:** Data spatial programming offers a natural and powerful way to model the complex, interconnected nature of codebases.
*   **Autonomous Agents (Walkers):** Walkers can intelligently navigate and analyze the code graph, performing tasks like pattern detection and data extraction for documentation.
*   **Seamless AI Integration (MTLLM):** The `by <llm>` syntax provides a clean and powerful way to delegate complex natural language processing, content generation, and reasoning tasks to a sophisticated 1B parameter model.
*   **Structured Data Handling:** Jac's ability to define custom objects (archetypes) allows for structured representation of documentation plans, diagram specifications, and extracted code information, which can then effectively guide the LLM.
*   **Extensibility:** The system can be extended with new walkers for deeper analysis or support for more languages/diagram types.

### High-Level Project Steps

1.  **Environment Setup:** Configure Jac with MTLLM and integrate a chosen 1B parameter LLM (e.g., via a local Ollama setup or an API).
2.  **Define Core Jac Archetypes:** Specify node types (`FileNode`, `ClassNode`, `FunctionNode`) and edge types (`ImportsEdge`, `CallsEdge`) for the code graph.
3.  **GitHub Integration:** Develop the `RepoCloningWalker`.
4.  **Code Parsing & Graph Construction:** Implement the `CodeParsingWalker(s)`. This might involve creating Jac-native parsers for common languages or wrappers around existing parsing libraries.
5.  **Analysis Walkers Development:**
    *   Create walkers for architectural pattern identification.
    *   Build walkers for detailed dependency mapping.
    *   Develop walkers for extracting data specifically for Mermaid diagrams (class, sequence, component, entity-relationship, etc.).
6.  **MTLLM Abilities for Documentation:**
    *   Implement the `plan_documentation_structure` ability.
    *   Develop the `generate_markdown_section` ability, including Mermaid integration.
    *   Refine the `generate_mermaid_code` ability for various diagram types.
7.  **Markdown Output System:** Create walkers or abilities to write the generated Markdown content and Mermaid diagrams to a structured set of files.
8.  **CLI and User Interface:** Design a simple command-line interface to accept a GitHub URL and output directory.
9.  **Testing & Iteration:** Thoroughly test with a variety of GitHub repositories (different sizes, languages, complexities). Refine prompts, walker logic, graph schema, and LLM interactions based on output quality.

"Codebase Genius" would be a landmark project demonstrating Jac's prowess in creating sophisticated, AI-driven developer tools. The generated documentation could significantly reduce the time developers spend understanding unfamiliar codebases.

---

## Project Idea: Fine-tuning TinyLLaMA for Enhanced Jac MTLLM Performance

This project focuses on fine-tuning the TinyLLaMA model to significantly improve its ability to handle Jac's MTLLM `by <llm>` calls. The primary goal is to enhance its proficiency in accurately processing structured inputs (like Jac objects passed as context) and generating well-formed, type-consistent structured outputs (such as Jac object instances or other typed data) directly at `by <llm>` call sites.

### Problem Statement

While MTLLM provides a powerful bridge to integrate Large Language Models within Jac programs, smaller, more accessible models like TinyLLaMA might not natively excel at:

*   **Interpreting Complex Jac Structures:** Difficulty in understanding the schema and content of custom Jac objects or complex data structures provided as context (e.g., via `incl_info`) to `by <llm>` calls.
*   **Strict Adherence to Output Typing:** Challenges in consistently generating outputs that strictly conform to Jac's precise type hints (e.g., `list[MyObject]`, `dict[str, int]`) or custom object definitions (e.g., ensuring all required fields of a `obj MyData` are present and correctly typed in the generated output).
*   **Nuanced Understanding of Semstrings:** Suboptimal interpretation of semantic strings (semstrings) when they are intended to guide the generation of specifically structured data rather than free-form text.

### Proposed Solution & Jac's Role

The core of this project is to create a specialized fine-tuning dataset and a robust evaluation process for TinyLLaMA, leveraging Jac's capabilities:

1.  **Dataset Generation using Jac:**
    *   **Corpus Creation:** Assemble a diverse corpus of Jac code examples that utilize the `by <llm>` feature. This should include:
        *   Various input data types passed as context: primitive types, lists, dictionaries, and instances of custom Jac objects.
        *   A wide range of output type hints: simple types (`str`, `int`), collections (`list[str]`), and complex custom Jac objects (e.g., `obj Result { has status: bool; has data: dict; }`).
        *   Examples demonstrating the use of `incl_info` for contextual data passing.
        *   Scenarios where semstrings are used to guide the LLM in generating structured output.
    *   **Automated Input/Output Pair Extraction:**
        *   Develop Jac walkers and scripts to parse the Jac code corpus.
        *   These tools would identify `by <llm>` call sites and automatically extract or help formulate the (prompt, ideal_completion) pairs for fine-tuning.
        *   The "prompt" would encapsulate the function/ability signature, relevant context (including serialized Jac objects), and semstrings.
        *   The "ideal_completion" would be the string representation of the perfectly structured and typed Jac output (e.g., a valid Jac object instantiation string `MyData(field1='value', field2=123)`).

2.  **Fine-tuning TinyLLaMA:**
    *   Employ standard LLM fine-tuning libraries and techniques (e.g., Hugging Face `transformers`, PEFT/LoRA) with the specialized dataset generated in the previous step.
    *   The objective is to train TinyLLaMA to recognize the patterns of Jac MTLLM calls and learn to generate outputs that are syntactically and semantically valid within the Jac ecosystem.

3.  **Evaluation Framework in Jac:**
    *   Construct a Jac-based evaluation harness.
    *   This harness will consist of Jac programs that invoke the fine-tuned TinyLLaMA via `by <fine_tuned_tiny_llm>`.
    *   The harness will programmatically:
        *   Call abilities that use the fine-tuned model.
        *   Receive the (potentially structured) output.
        *   Validate the output against expected Jac types and structures using Jac's runtime type checking and object introspection capabilities.
        *   Measure accuracy in terms of structural integrity, type correctness, and semantic plausibility.

4.  **Integration as an MTLLM Backend:**
    *   Adapt the fine-tuned TinyLLaMA model to be seamlessly integrated as a custom backend within the `jac-mtllm` plugin system, likely by creating a new class inheriting from `BaseLLM`.

### Benefits

*   **Accessible and Local MTLLM:** Empowers developers to use MTLLM features with a small, efficient model that can run locally, reducing dependency on large, cloud-based LLMs.
*   **Improved Reliability for Small Models:** Significantly enhances the reliability and predictability of MTLLM when used with smaller models by making them more adept at Jac's structured data paradigms.
*   **Cost-Effective AI Solutions:** Lowers or eliminates API costs for many GenAI tasks that can be effectively handled by a fine-tuned local model.
*   **Enhanced Privacy:** Facilitates on-device processing for applications dealing with sensitive code or data.
*   **Community Enablement:** Provides the Jac community with a powerful, optimized small model for local MTLLM experimentation and development.

### High-Level Project Steps

1.  **Setup & Tooling:** Prepare the development environment for Jac programming and LLM fine-tuning (Python, PyTorch, Hugging Face libraries, etc.).
2.  **Dataset Design and Scoping:** Define the scope and variety of Jac `by <llm>` patterns, data structures (input/output), and specific tasks to be included in the fine-tuning dataset.
3.  **Jac-Powered Dataset Generation:**
    *   Implement Jac walkers/scripts to automatically or semi-automatically generate fine-tuning data (prompt-completion pairs) from the Jac code corpus.
4.  **TinyLLaMA Fine-Tuning Execution:**
    *   Select a suitable pre-trained TinyLLaMA variant.
    *   Conduct the fine-tuning process using the generated dataset, experimenting with different strategies (e.g., full fine-tuning vs. parameter-efficient methods like LoRA).
5.  **Jac Evaluation Harness Implementation:**
    *   Develop Jac archetypes and test suites to programmatically assess the fine-tuned model's performance on structured data generation tasks.
6.  **MTLLM Backend Integration:** Package the fine-tuned model as an easily usable backend for `jac-mtllm`.
7.  **Testing, Iteration, and Documentation:**
    *   Thoroughly test the integrated fine-tuned model across diverse scenarios.
    *   Iteratively refine the dataset and fine-tuning process based on evaluation results.
    *   Provide clear documentation on how to set up and use the fine-tuned TinyLLaMA with Jac MTLLM.

This project would be a significant contribution to the Jac ecosystem, making its advanced AI-integration features more accessible, efficient, and reliable, especially for developers preferring or requiring local model execution.