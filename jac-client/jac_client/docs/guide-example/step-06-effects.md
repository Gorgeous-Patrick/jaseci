# Step 6: Side Effects with `useEffect`

In this step, you'll learn about `useEffect` - a hook for running code when your component loads or when data changes.

## What is a Side Effect?

In programming, a **side effect** is any operation that affects something outside the function's scope.

**Python analogy:**

```python
class TodoApp:
    def __init__(self):
        self.todos = []
        self.load_from_database()  # Side effect: reads from DB

    def save_todo(self, todo):
        self.todos.append(todo)
        self.save_to_database()  # Side effect: writes to DB
```

Common side effects in web apps:
- 📡 **Fetching data** from an API
- 💾 **Saving data** to localStorage or a database
- ⏰ **Setting timers** or intervals
- 📊 **Logging** or analytics
- 🔔 **Subscriptions** to external events

## The `useEffect` Hook

`useEffect` lets you run code at specific times:

```jac
useEffect(lambda -> None {
    // Code to run
}, [dependencies]);
```

**When does it run?**

1. **After first render** (when component appears)
2. **After dependencies change** (when specified values update)

**Syntax breakdown:**

```jac
useEffect(
    lambda -> None {
        // Your code here
    },
    []  // Dependency array
);
```

- First parameter: Function to run
- Second parameter: Array of dependencies (when to re-run)

## Understanding Dependencies

The dependency array `[]` controls when the effect runs:

### 1. Run Once (on mount)

```jac
useEffect(lambda -> None {
    console.log("Component mounted!");
}, []);  // Empty array = run once
```

**Python analogy**: Like `__init__` in a class.

### 2. Run on Every Render

```jac
useEffect(lambda -> None {
    console.log("Component rendered!");
});  // No array = run always
```

⚠️ **Rarely used** - can cause performance issues!

### 3. Run When Specific Values Change

```jac
let [count, setCount] = useState(0);

useEffect(lambda -> None {
    console.log("Count changed to:", count);
}, [count]);  // Run when count changes
```

## Practical Example: Load Todos on Mount

Let's load todos when the app first starts:

```jac
cl import from react {useState, useEffect}

cl {
    def app() -> any {
        let [todos, setTodos] = useState([]);
        let [loading, setLoading] = useState(True);

        # Run once when component mounts
        useEffect(lambda -> None {
            console.log("App loaded! Fetching todos...");

            # Simulate loading delay
            setTimeout(lambda -> None {
                let mockTodos = [
                    {"id": 1, "text": "Learn useEffect", "done": False},
                    {"id": 2, "text": "Build amazing apps", "done": False}
                ];
                setTodos(mockTodos);
                setLoading(False);
            }, 1000);
        }, []);  # Empty array = run once

        if loading {
            return <div style={{"textAlign": "center", "padding": "50px"}}>
                <h2>Loading todos...</h2>
            </div>;
        }

        return <div style={{"padding": "20px"}}>
            <h1>My Todos</h1>
            <ul>
                {todos.map(lambda todo: any -> any {
                    return <li key={todo["id"]}>{todo["text"]}</li>;
                })}
            </ul>
        </div>;
    }
}
```

### What's Happening:

1. Component renders with `loading = True`
2. `useEffect` runs **after** first render
3. We simulate an API call with `setTimeout`
4. When data "loads", we update state
5. Component re-renders with the todos

## Saving to localStorage

Let's persist todos across page refreshes using browser storage:

```jac
cl import from react {useState, useEffect}

cl {
    def app() -> any {
        let [todos, setTodos] = useState([]);

        # Load from localStorage on mount
        useEffect(lambda -> None {
            let saved = localStorage.getItem("todos");
            if saved {
                let parsed = JSON.parse(saved);
                setTodos(parsed);
            }
        }, []);

        # Save to localStorage whenever todos change
        useEffect(lambda -> None {
            localStorage.setItem("todos", JSON.stringify(todos));
        }, [todos]);  # Run when todos change

        def addTodo(text: str) -> None {
            let newTodo = {
                "id": Date.now(),
                "text": text,
                "done": False
            };
            setTodos(todos.concat([newTodo]));
            # No need to manually save - useEffect handles it!
        }

        return <div style={{"padding": "20px"}}>
            <h1>Persistent Todos</h1>
            <button onClick={lambda -> None { addTodo("New Todo"); }}>
                Add Todo
            </button>
            <ul>
                {todos.map(lambda todo: any -> any {
                    return <li key={todo["id"]}>{todo["text"]}</li>;
                })}
            </ul>
            <p style={{"color": "#999"}}>Todos are saved automatically!</p>
        </div>;
    }
}
```

**Key insight**: We have **two** `useEffect` hooks:
1. First one loads data once (empty dependencies)
2. Second one saves data when todos change (depends on `todos`)

## Fetching from Backend - Real Example

Here's exactly how the todo app loads todos from the backend:

```jac
cl import from react {useState, useEffect}
cl import from "@jac-client/utils" {jacSpawn}

cl {
    def TodosPage() -> any {
        let [todos, setTodos] = useState([]);
        let [input, setInput] = useState("");
        let [filter, setFilter] = useState("all");

        # Load todos when component mounts
        useEffect(lambda -> None {
            async def loadTodos() -> None {
                result = await jacSpawn("read_todos", "", {});
                setTodos(result.reports if result.reports else []);
            }
            loadTodos();
        }, []);  # Empty array = run once on mount

        return <div>
            <h1>My Todos</h1>
            {/* Rest of UI */}
        </div>;
    }
}
```

**What's happening:**
1. Component renders with empty todos array
2. `useEffect` runs **after** first render
3. `loadTodos()` async function calls the backend walker
4. Results update the state with `setTodos()`
5. Component re-renders with the loaded todos

## Multiple Effects for Organization

You can use multiple `useEffect` hooks for different purposes:

```jac
def app() -> any {
    let [todos, setTodos] = useState([]);
    let [user, setUser] = useState(None);

    # Effect 1: Load user data
    useEffect(lambda -> None {
        console.log("Loading user...");
        # Fetch user data
    }, []);

    # Effect 2: Load todos when user changes
    useEffect(lambda -> None {
        if user {
            console.log("Loading todos for user:", user);
            # Fetch todos for this user
        }
    }, [user]);

    # Effect 3: Save todos when they change
    useEffect(lambda -> None {
        if todos.length > 0 {
            console.log("Saving todos...");
            localStorage.setItem("todos", JSON.stringify(todos));
        }
    }, [todos]);

    return <div>...</div>;
}
```

**Best practice**: Separate concerns into different effects.

## Cleanup Functions

Sometimes effects need cleanup (like removing timers):

```jac
useEffect(lambda -> None {
    # Set up an interval
    let intervalId = setInterval(lambda -> None {
        console.log("Tick!");
    }, 1000);

    # Return a cleanup function
    return lambda -> None {
        clearInterval(intervalId);
        console.log("Cleaned up!");
    };
}, []);
```

**When cleanup runs:**
- Before effect runs again
- When component is removed from screen

**Common cleanup scenarios:**
- Canceling timers
- Closing WebSocket connections
- Unsubscribing from events

## Practical Example: Auto-Save Indicator

Let's add a feature that shows when todos are being saved:

```jac
cl import from react {useState, useEffect}

cl {
    def app() -> any {
        let [todos, setTodos] = useState([]);
        let [saving, setSaving] = useState(False);

        useEffect(lambda -> None {
            setSaving(True);

            # Debounce: wait a bit before saving
            let timerId = setTimeout(lambda -> None {
                localStorage.setItem("todos", JSON.stringify(todos));
                setSaving(False);
            }, 500);

            # Cleanup: cancel save if todos change again quickly
            return lambda -> None {
                clearTimeout(timerId);
            };
        }, [todos]);

        def addTodo(text: str) -> None {
            let newTodo = {"id": Date.now(), "text": text, "done": False};
            setTodos(todos.concat([newTodo]));
        }

        return <div style={{"padding": "20px"}}>
            <h1>Auto-Save Todos</h1>

            {/* Save indicator */}
            <div style={{
                "padding": "10px",
                "backgroundColor": (("#fef3c7" if saving else "#d1fae5")),
                "marginBottom": "20px",
                "borderRadius": "6px"
            }}>
                {(("💾 Saving..." if saving else "✅ Saved!"))}
            </div>

            <button onClick={lambda -> None { addTodo("Test todo"); }}>
                Add Todo
            </button>

            <ul>
                {todos.map(lambda todo: any -> any {
                    return <li key={todo["id"]}>{todo["text"]}</li>;
                })}
            </ul>
        </div>;
    }
}
```

## Common Patterns

### Pattern 1: Fetch on Mount

```jac
useEffect(lambda -> None {
    async def fetchData() -> None {
        let data = await apiCall();
        setState(data);
    }
    fetchData();
}, []);
```

### Pattern 2: Sync with External System

```jac
useEffect(lambda -> None {
    localStorage.setItem("key", value);
}, [value]);
```

### Pattern 3: Conditional Effect

```jac
useEffect(lambda -> None {
    if someCondition {
        // Do something
    }
}, [someCondition]);
```

## Common Issues

### Issue: Effect runs too many times
**Solution**: Check your dependency array. Include only values the effect actually uses.

```jac
# ❌ Runs on every render
useEffect(lambda -> None {
    console.log(todos);
});

# ✅ Runs only when todos change
useEffect(lambda -> None {
    console.log(todos);
}, [todos]);
```

### Issue: "Stale" values in effect
**Solution**: Make sure to include all values you use in the dependency array.

```jac
def Component() -> any {
    let [count, setCount] = useState(0);

    # ❌ Always logs 0
    useEffect(lambda -> None {
        setTimeout(lambda -> None {
            console.log(count);
        }, 1000);
    }, []);  # Missing count dependency!

    # ✅ Logs current count
    useEffect(lambda -> None {
        setTimeout(lambda -> None {
            console.log(count);
        }, 1000);
    }, [count]);  # Include count
}
```

### Issue: Effect runs on first render when it shouldn't
**Solution**: Use a ref or flag to skip first render.

```jac
let [isFirstRender, setIsFirstRender] = useState(True);

useEffect(lambda -> None {
    if isFirstRender {
        setIsFirstRender(False);
        return;
    }

    // This runs on updates, not first render
}, [someDependency]);
```

## useEffect Lifecycle Summary

```
Component Lifecycle:
┌─────────────────────────────────────┐
│ 1. Component renders                │
├─────────────────────────────────────┤
│ 2. UI updates on screen             │
├─────────────────────────────────────┤
│ 3. useEffect runs                   │
├─────────────────────────────────────┤
│ 4. State changes (from effect)      │
├─────────────────────────────────────┤
│ 5. Component re-renders             │
├─────────────────────────────────────┤
│ 6. useEffect cleanup runs (if any)  │
├─────────────────────────────────────┤
│ 7. useEffect runs again (if deps    │
│    changed)                          │
└─────────────────────────────────────┘
```

## What You Learned

- ✅ What side effects are
- ✅ How to use `useEffect` hook
- ✅ Dependency arrays and when effects run
- ✅ Loading data on component mount
- ✅ Persisting data to localStorage
- ✅ Cleanup functions for timers/subscriptions
- ✅ Multiple effects for organization
- ✅ Common patterns and pitfalls

## Practice Exercise

Try implementing:
1. A "last saved" timestamp that updates when todos are saved
2. A feature that loads todos from localStorage on app start
3. A countdown timer that updates every second

## Next Step

Your app works great, but it's all on one page. Let's add **multiple pages** with routing!

👉 **[Continue to Step 7: Adding Routes](./step-07-routing.md)**



