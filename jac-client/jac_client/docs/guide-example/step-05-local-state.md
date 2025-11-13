# Step 5: Adding Local State with `useState`

In this step, you'll learn about **state** - the data that makes your app interactive and dynamic.

## What is State?

Imagine a light switch in Python:

```python
class LightSwitch:
    def __init__(self):
        self.is_on = False  # This is "state"

    def toggle(self):
        self.is_on = not self.is_on  # Changing state
        print(f"Light is {'on' if self.is_on else 'off'}")

switch = LightSwitch()
switch.toggle()  # Light is on
switch.toggle()  # Light is off
```

In React/Jac, **state** works similarly - it's data that can change over time and causes your UI to update when it changes.

## The `useState` Hook

`useState` is a special function that lets you add state to your components.

**Basic syntax:**

```jac
let [value, setValue] = useState(initialValue);
```

- `value` - The current state value (read-only)
- `setValue` - Function to update the state
- `initialValue` - Starting value

**Python analogy:**

```python
# Python
class Component:
    def __init__(self):
        self.count = 0  # state

    def increment(self):
        self.count += 1  # updating state

# Jac
def Component() -> any {
    let [count, setCount] = useState(0);  # state

    # Later: setCount(count + 1)  # updating state
}
```

## Your First State: Input Value

Let's make the todo input field work. First, import `useState`:

```jac
cl import from react {useState}

cl {
    def TodoInput() -> any {
        # Create state for the input value
        let [inputValue, setInputValue] = useState("");

        return <div style={{
            "display": "flex",
            "gap": "8px",
            "marginBottom": "24px",
            "backgroundColor": "#ffffff",
            "padding": "16px",
            "borderRadius": "12px",
            "boxShadow": "0 1px 3px rgba(0,0,0,0.1)"
        }}>
            <input
                type="text"
                value={inputValue}
                onChange={lambda e: any -> None {
                    setInputValue(e.target.value);
                }}
                placeholder="What needs to be done?"
                style={{
                    "flex": "1",
                    "padding": "12px 16px",
                    "border": "1px solid #e5e7eb",
                    "borderRadius": "8px",
                    "fontSize": "16px",
                    "outline": "none"
                }}
            />
            <button style={{
                "padding": "12px 24px",
                "backgroundColor": "#3b82f6",
                "color": "#ffffff",
                "border": "none",
                "borderRadius": "8px",
                "fontSize": "16px",
                "fontWeight": "600",
                "cursor": "pointer"
            }}>
                Add
            </button>
        </div>;
    }

    def app() -> any {
        return <div style={{"padding": "20px"}}>
            <TodoInput />
        </div>;
    }
}
```

### What's Happening:

1. **Import useState**: `cl import from react {useState}`

2. **Create state**: `let [inputValue, setInputValue] = useState("");`
   - Initial value is empty string `""`

3. **Bind to input**: `value={inputValue}`
   - The input shows whatever is in `inputValue`

4. **Update on change**: `onChange={lambda e: any -> None { setInputValue(e.target.value); }}`
   - When you type, it calls `setInputValue` with the new text
   - This updates the state
   - React automatically re-renders the input with the new value

**Try it!** Type in the input field. The text should appear as you type!

## Understanding Event Handlers

The `lambda e: any -> None { ... }` is an event handler:

```jac
onChange={lambda e: any -> None {
    setInputValue(e.target.value);
}}
```

**Breakdown:**
- `lambda e: any -> None` - Anonymous function (like Python lambda)
- `e` - The event object (contains info about what happened)
- `e.target` - The element that triggered the event (the input field)
- `e.target.value` - The current value of the input field

**Python comparison:**

```python
# Python
def on_change(event):
    self.input_value = event.target.value

# Jac
lambda e: any -> None {
    setInputValue(e.target.value);
}
```

## Managing Todo List State

Now let's add state for our todo list:

```jac
cl import from react {useState}

cl {
    def app() -> any {
        # State for the list of todos
        let [todos, setTodos] = useState([
            {"id": 1, "text": "Learn Jac basics", "done": False},
            {"id": 2, "text": "Build todo app", "done": False},
            {"id": 3, "text": "Deploy to production", "done": False}
        ]);

        # State for input field
        let [inputValue, setInputValue] = useState("");

        return <div style={{
            "maxWidth": "720px",
            "margin": "0 auto",
            "padding": "24px"
        }}>
            <h1>My Todos</h1>
            <p>Total todos: {todos.length}</p>

            {/* Input field */}
            <div style={{"display": "flex", "gap": "8px", "marginBottom": "16px"}}>
                <input
                    type="text"
                    value={inputValue}
                    onChange={lambda e: any -> None {
                        setInputValue(e.target.value);
                    }}
                    placeholder="What needs to be done?"
                    style={{"flex": "1", "padding": "10px"}}
                />
                <button style={{"padding": "10px 20px"}}>
                    Add
                </button>
            </div>

            {/* Display todos */}
            <div>
                {todos.map(lambda todo: any -> any {
                    return <div key={todo["id"]} style={{
                        "display": "flex",
                        "gap": "10px",
                        "padding": "10px",
                        "backgroundColor": "#f9fafb",
                        "marginBottom": "8px",
                        "borderRadius": "8px"
                    }}>
                        <input type="checkbox" checked={todo["done"]} />
                        <span style={{"flex": "1"}}>{todo["text"]}</span>
                        <button style={{"color": "red"}}>Delete</button>
                    </div>;
                })}
            </div>
        </div>;
    }
}
```

### Understanding Arrays and `.map()`

`.map()` is used to render a list:

```jac
{todos.map(lambda todo: any -> any {
    return <div key={todo["id"]}>
        {todo["text"]}
    </div>;
})}
```

**Python analogy:**

```python
# Python list comprehension
[f"<div>{todo['text']}</div>" for todo in todos]

# Jac .map()
todos.map(lambda todo: any -> any {
    return <div>{todo["text"]}</div>;
})
```

**Important**: Always add a `key` prop when mapping:
- `key={todo["id"]}` helps React track which items changed
- Use a unique identifier (like an ID)

## Adding Todos

Let's make the "Add" button work:

```jac
cl import from react {useState}

cl {
    def app() -> any {
        let [todos, setTodos] = useState([]);
        let [inputValue, setInputValue] = useState("");

        # Function to add a new todo
        def handleAddTodo() -> None {
            if inputValue.trim() == "" {
                return;  # Don't add empty todos
            }

            # Create new todo object
            let newTodo = {
                "id": todos.length + 1,  # Simple ID generation
                "text": inputValue,
                "done": False
            };

            # Add to todos list
            let updatedTodos = todos.concat([newTodo]);
            setTodos(updatedTodos);

            # Clear input field
            setInputValue("");
        }

        return <div style={{"maxWidth": "720px", "margin": "0 auto", "padding": "24px"}}>
            <h1>My Todos</h1>

            {/* Input section */}
            <div style={{"display": "flex", "gap": "8px", "marginBottom": "16px"}}>
                <input
                    type="text"
                    value={inputValue}
                    onChange={lambda e: any -> None {
                        setInputValue(e.target.value);
                    }}
                    onKeyPress={lambda e: any -> None {
                        if e.key == "Enter" {
                            handleAddTodo();
                        }
                    }}
                    placeholder="What needs to be done?"
                    style={{"flex": "1", "padding": "10px", "fontSize": "16px"}}
                />
                <button
                    onClick={lambda -> None { handleAddTodo(); }}
                    style={{"padding": "10px 20px", "backgroundColor": "#3b82f6", "color": "white", "border": "none", "borderRadius": "6px", "cursor": "pointer"}}
                >
                    Add
                </button>
            </div>

            {/* Display todos */}
            <div>
                {todos.map(lambda todo: any -> any {
                    return <div key={todo["id"]} style={{
                        "display": "flex",
                        "gap": "10px",
                        "padding": "12px",
                        "backgroundColor": "#ffffff",
                        "marginBottom": "8px",
                        "borderRadius": "8px",
                        "border": "1px solid #e5e7eb"
                    }}>
                        <input type="checkbox" checked={todo["done"]} />
                        <span style={{"flex": "1"}}>{todo["text"]}</span>
                        <button style={{"padding": "4px 12px", "backgroundColor": "#ef4444", "color": "white", "border": "none", "borderRadius": "4px", "cursor": "pointer"}}>
                            Delete
                        </button>
                    </div>;
                })}
            </div>

            {/* Empty state */}
            {(todos.length == 0) ? (
                <div style={{"textAlign": "center", "padding": "40px", "color": "#9ca3af"}}>
                    No todos yet. Add one above!
                </div>
            ) : <span></span>}
        </div>;
    }
}
```

### Key Concepts:

1. **Helper function**: `def handleAddTodo()`
   - Defined inside the component
   - Has access to state variables

2. **Updating arrays**:
   - ❌ Don't mutate: `todos.push(newTodo)`
   - ✅ Create new array: `todos.concat([newTodo])`

3. **Event handlers**:
   - `onClick={lambda -> None { handleAddTodo(); }}`
   - `onKeyPress` detects "Enter" key

## Toggling Todo Completion

Let's make checkboxes work:

```jac
def handleToggleTodo(id: int) -> None {
    let updatedTodos = todos.map(lambda todo: any -> any {
        if todo["id"] == id {
            return {
                "id": todo["id"],
                "text": todo["text"],
                "done": not todo["done"]  # Toggle!
            };
        }
        return todo;
    });
    setTodos(updatedTodos);
}

# In your JSX:
<input
    type="checkbox"
    checked={todo["done"]}
    onChange={lambda -> None { handleToggleTodo(todo["id"]); }}
/>
```

## Deleting Todos

```jac
def handleDeleteTodo(id: int) -> None {
    let remaining = todos.filter(lambda todo: any -> bool {
        return todo["id"] != id;
    });
    setTodos(remaining);
}

# In your JSX:
<button onClick={lambda -> None { handleDeleteTodo(todo["id"]); }}>
    Delete
</button>
```

## Complete Working Example

Here's the actual state management from the todo app:

```jac
cl import from react {useState, useEffect}
cl import from "@jac-client/utils" {jacSpawn}

cl {
    def TodosPage() -> any {
        let [todos, setTodos] = useState([]);
        let [input, setInput] = useState("");
        let [filter, setFilter] = useState("all");

        # Load todos on mount
        useEffect(lambda -> None {
            async def loadTodos() -> None {
                result = await jacSpawn("read_todos", "", {});
                setTodos(result.reports if result.reports else []);
            }
            loadTodos();
        }, []);

        # Add todo
        async def addTodo() -> None {
            if not input.trim() { return; }
            result = await jacSpawn("create_todo", "", {"text": input.trim()});
            setTodos(todos.concat([result.reports[0][0]]));
            setInput("");
        }

        # Toggle todo
        async def toggleTodo(id: any) -> None {
            await jacSpawn("toggle_todo", id, {});
            setTodos(todos.map(lambda todo: any -> any {
                if todo._jac_id == id {
                    return {
                        "_jac_id": todo._jac_id,
                        "text": todo.text,
                        "done": not todo.done
                    };
                }
                return todo;
            }));
        }

        # Delete todo
        async def deleteTodo(id: any) -> None {
            await jacSpawn("delete_todo", id, {});
            setTodos(todos.filter(lambda todo: any -> bool { return todo._jac_id != id; }));
        }

        # Filter todos
        def getFilteredTodos() -> list {
            if filter == "active" {
                return todos.filter(lambda todo: any -> bool { return not todo.done; });
            } elif filter == "completed" {
                return todos.filter(lambda todo: any -> bool { return todo.done; });
            }
            return todos;
        }

        filteredTodos = getFilteredTodos();
        activeCount = todos.filter(lambda todo: any -> bool { return not todo.done; }).length;

        return <div style={{"maxWidth": "600px", "margin": "20px auto", "padding": "20px"}}>
            <h1>My Todos</h1>

            {/* Input section */}
            <div style={{"display": "flex", "gap": "8px", "marginBottom": "16px"}}>
                <input
                    type="text"
                    value={input}
                    onChange={lambda e: any -> None { setInput(e.target.value); }}
                    onKeyPress={lambda e: any -> None {
                        if e.key == "Enter" { addTodo(); }
                    }}
                    placeholder="What needs to be done?"
                    style={{"flex": "1", "padding": "8px"}}
                />
                <button onClick={addTodo}>Add</button>
            </div>

            {/* Filter buttons */}
            <div style={{"display": "flex", "gap": "8px", "marginBottom": "16px"}}>
                <button onClick={lambda -> None { setFilter("all"); }}>All</button>
                <button onClick={lambda -> None { setFilter("active"); }}>Active</button>
                <button onClick={lambda -> None { setFilter("completed"); }}>Completed</button>
            </div>

            {/* Todo list */}
            <div>
                {filteredTodos.map(lambda todo: any -> any {
                    return <div key={todo._jac_id}>
                        <input
                            type="checkbox"
                            checked={todo.done}
                            onChange={lambda -> None { toggleTodo(todo._jac_id); }}
                        />
                        <span>{todo.text}</span>
                        <button onClick={lambda -> None { deleteTodo(todo._jac_id); }}>
                            Delete
                        </button>
                    </div>;
                })}
            </div>

            {/* Stats */}
            {(<div>{activeCount} items left</div>) if todos.length > 0 else None}
        </div>;
    }
}
```

**Key state patterns:**
- Three pieces of state: `todos`, `input`, `filter`
- All mutations create new arrays (no direct mutation)
- Filter is local-only (doesn't affect backend)
- Backend calls are async and update state on completion

## State Update Rules

**Golden rules for updating state:**

1. **Never mutate state directly**:
   ```jac
   # ❌ Wrong
   todos.push(newTodo);
   setTodos(todos);

   # ✅ Correct
   setTodos(todos.concat([newTodo]));
   ```

2. **Always create new objects/arrays**:
   - Use `.concat()` for adding to arrays
   - Use `.map()` for updating items
   - Use `.filter()` for removing items

3. **State updates are asynchronous**:
   - Don't rely on state value immediately after calling setter
   - React batches updates for performance

## Common Issues

### Issue: Typing doesn't update input
**Check**: Did you add both `value` and `onChange`?

### Issue: Button click doesn't work
**Check**: Did you wrap your function in a lambda?
- ✅ `onClick={lambda -> None { handleAddTodo(); }}`
- ❌ `onClick={handleAddTodo}` (might work in some cases)

### Issue: List doesn't update
**Check**: Are you creating a new array or mutating the old one?

## What You Learned

- ✅ What state is and why we need it
- ✅ How to use `useState` hook
- ✅ How to handle user input
- ✅ How to update arrays (add, modify, delete)
- ✅ Event handlers (`onClick`, `onChange`, `onKeyPress`)
- ✅ Mapping over arrays to render lists
- ✅ Conditional rendering with ternary operator

## Next Step

Your app now works locally, but the data isn't saved anywhere! When you refresh, everything is lost. In the next step, we'll learn about `useEffect` to load data when the app starts.

👉 **[Continue to Step 6: Side Effects with useEffect](./step-06-effects.md)**



