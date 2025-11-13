# Step 8: Backend with Walkers

In this step, you'll learn about **walkers** - Jac's unique way of handling backend logic and data persistence.

## What are Walkers?

In traditional web development, you write separate backend code:

```python
# Python/Flask Backend (separate file)
@app.route("/api/todos", methods=["GET"])
def get_todos():
    todos = db.query(Todo).all()
    return jsonify(todos)

@app.route("/api/todos", methods=["POST"])
def create_todo():
    data = request.json
    todo = Todo(**data)
    db.save(todo)
    return jsonify(todo)
```

In Jac, **walkers** are special functions that:
- Run on the **server** (backend)
- Can traverse your data graph (nodes and edges)
- Automatically become API endpoints
- Can be called from your frontend

**Think of walkers as:**
- Python: "Functions that run on the backend"
- FastAPI: "Automatically created API endpoints"
- Database queries: "Functions that fetch/modify data"

## Data Model: Nodes

First, we need to define our data structure using **nodes**:

```jac
# Node is like a Python class or database table
node Todo {
    has text: str;
    has done: bool = False;
}
```

**Python analogy:**

```python
# Python class
class Todo:
    def __init__(self, text, done=False):
        self.text = text
        self.done = done

# SQL Table
CREATE TABLE todos (
    id INTEGER PRIMARY KEY,
    text TEXT NOT NULL,
    done BOOLEAN DEFAULT FALSE
);
```

## Your First Walker: Reading Todos

Let's create a walker that fetches all todos:

```jac
# Data model
node Todo {
    has text: str;
    has done: bool = False;
}

# Walker to read todos
walker read_todos {
    # Specs define if authentication is required
    class __specs__ {
        has auth: bool = True;
    }

    # Entry point: runs when walker starts at root
    can read with `root entry {
        # Visit all Todo nodes connected to root
        visit [-->(`?Todo)];
    }

    # Runs when walker finishes
    can report_todos with exit {
        # Report all todos back to client
        report here;
    }
}
```

### Breaking It Down:

1. **`walker read_todos`** - Declares a walker (like a function)

2. **`class __specs__`** - Configuration
   - `has auth: bool = True` - Requires user to be logged in

3. **`can read with `root entry`** - Entry point
   - Runs when walker starts at the root node
   - `` `root `` is a special keyword for the root of your data graph

4. **`visit [-->(`?Todo)]`** - Graph traversal
   - `-->` means "follow edges going out"
   - `` `?Todo `` means "find nodes of type Todo"
   - Think: "Visit all Todo nodes connected to root"

5. **`can report_todos with exit`** - Exit handler
   - Runs when walker is done
   - `report here` sends the current node back to frontend

## Walker: Creating Todos

Let's create a walker that adds new todos:

```jac
walker create_todo {
    # Parameters that frontend passes
    has text: str;

    class __specs__ {
        has auth: bool = True;
    }

    can create with `root entry {
        # Create new Todo node and connect it to root
        new_todo = here ++> Todo(text=self.text);

        # Report the new todo back to frontend
        report new_todo;
    }
}
```

### Key Concepts:

- **`has text: str`** - Walker parameter (passed from frontend)
- **`here`** - Current node (in this case, root)
- **`++>`** - Create edge operator
  - `here ++> Todo(...)` means "create Todo and connect it to current node"
- **`report new_todo`** - Send data back to frontend

**Python analogy:**

```python
def create_todo(text):
    new_todo = Todo(text=text, done=False)
    db.save(new_todo)
    return new_todo
```

## Walker: Toggling Todo Completion

```jac
walker toggle_todo {
    class __specs__ {
        has auth: bool = True;
    }

    can toggle with Todo entry {
        # Toggle the done status
        here.done = not here.done;

        # Report the updated todo
        report here;
    }
}
```

### What's Different:

- **`can toggle with Todo entry`** - Runs when walker reaches a `Todo` node
- **`here.done`** - Access properties of current node
- This walker is called with a specific Todo node ID (not root)

## Complete Backend Example

Here's a complete todo backend with all CRUD operations:

```jac
# ===== DATA MODEL =====
node Todo {
    has text: str;
    has done: bool = False;
}

# ===== CREATE =====
walker create_todo {
    has text: str;

    can create with `root entry {
        # Create new todo connected to root
        new_todo = here ++> Todo(text=self.text);
        report new_todo;
    }
}

# ===== READ =====
walker read_todos {
    can read with `root entry {
        # Visit all todos
        visit [-->(`?Todo)];
    }

    can report_todos with Todo entry {
        # Report each todo we visited
        report here;
    }
}

# ===== UPDATE (Toggle) =====
walker toggle_todo {
    can toggle with Todo entry {
        here.done = not here.done;
        report here;
    }
}

# ===== DELETE =====
walker delete_todo {
    can delete with Todo entry {
        # Destroy the todo node
        here.destroy();
        report {"success": True};
    }
}
```

## Calling Walkers from Frontend

Now let's connect the frontend to these walkers:

```jac
cl import from react {useState, useEffect}
cl import from "@jac-client/utils" {jacSpawn}

cl {
    def DashboardPage() -> any {
        let [todos, setTodos] = useState([]);
        let [inputValue, setInputValue] = useState("");

        # Load todos when component mounts
        useEffect(lambda -> None {
            async def loadTodos() -> None {
                try {
                    # Call read_todos walker
                    let response = await jacSpawn("read_todos", "", {});

                    # Get todos from response
                    let items = response.reports || [];
                    setTodos(items);
                } except Exception as err {
                    console.error("Error loading todos:", err);
                }
            }

            loadTodos();
        }, []);

        # Add new todo
        async def handleAddTodo() -> None {
            if inputValue.trim() == "" {
                return;
            }

            try {
                # Call create_todo walker with parameters
                let response = await jacSpawn("create_todo", "", {
                    "text": inputValue
                });

                # Get the new todo from response
                let newTodo = response.reports[0];

                # Update local state
                setTodos(todos.concat([newTodo]));
                setInputValue("");
            } except Exception as err {
                console.error("Error creating todo:", err);
            }
        }

        # Toggle todo completion
        async def handleToggle(todoId: any) -> None {
            try {
                # Call toggle_todo walker on specific todo node
                await jacSpawn("toggle_todo", todoId, {});

                # Update local state
                let updated = todos.map(lambda todo: any -> any {
                    if todo._jac_id == todoId {
                        return {
                            "_jac_id": todo._jac_id,
                            "text": todo.text,
                            "done": not todo.done
                        };
                    }
                    return todo;
                });
                setTodos(updated);
            } except Exception as err {
                console.error("Error toggling todo:", err);
            }
        }

        return <div style={{"maxWidth": "720px", "margin": "20px auto", "padding": "20px"}}>
            <h1>My Todos</h1>

            {/* Input */}
            <div style={{"display": "flex", "gap": "8px", "marginBottom": "16px"}}>
                <input
                    type="text"
                    value={inputValue}
                    onChange={lambda e: any -> None { setInputValue(e.target.value); }}
                    onKeyPress={lambda e: any -> None {
                        if e.key == "Enter" { handleAddTodo(); }
                    }}
                    placeholder="What needs to be done?"
                    style={{"flex": "1", "padding": "12px"}}
                />
                <button onClick={lambda -> None { handleAddTodo(); }}>
                    Add
                </button>
            </div>

            {/* Todo List */}
            <div>
                {todos.map(lambda todo: any -> any {
                    return <div key={todo._jac_id} style={{
                        "display": "flex",
                        "gap": "12px",
                        "padding": "12px",
                        "backgroundColor": "#fff",
                        "marginBottom": "8px",
                        "borderRadius": "8px"
                    }}>
                        <input
                            type="checkbox"
                            checked={todo.done}
                            onChange={lambda -> None { handleToggle(todo._jac_id); }}
                        />
                        <span style={{
                            "flex": "1",
                            "textDecoration": (("line-through" if todo.done else "none"))
                        }}>
                            {todo.text}
                        </span>
                    </div>;
                })}
            </div>
        </div>;
    }

    def app() -> any {
        return <DashboardPage />;
    }
}
```

### Understanding `jacSpawn`:

```jac
let response = await jacSpawn(walkerName, nodeId, parameters);
```

- **`walkerName`** - Name of walker to call (string)
- **`nodeId`** - Which node to run walker on (empty string "" for root)
- **`parameters`** - Object with walker parameters
- **Returns** - Promise with response containing `reports`

**Examples:**

```jac
# Call walker on root
jacSpawn("read_todos", "", {})

# Call walker with parameters
jacSpawn("create_todo", "", {"text": "New todo"})

# Call walker on specific node
jacSpawn("toggle_todo", "node-id-123", {})
```

## Data Persistence

Unlike localStorage, walkers automatically persist data! When you:

1. Create a todo → Saved to backend database
2. Refresh page → Data still there
3. Login from different device → See your todos

**No extra work needed!** Jac handles:
- Database storage
- User isolation (each user sees only their data)
- Concurrent access
- Data integrity

## Graph Structure Visualization

Your data looks like this:

```
     root (user's root node)
      |
      +---> Todo("Learn Jac")
      |
      +---> Todo("Build app")
      |
      +---> Todo("Deploy")
```

When you call `read_todos`:
1. Walker starts at `root`
2. Follows edges (`-->`) to find `Todo` nodes
3. Reports each Todo found

## Advanced: Filtering Todos

Let's add a walker that returns only active todos:

```jac
walker read_active_todos {
    class __specs__ {
        has auth: bool = True;
    }

    can read with `root entry {
        visit [-->(`?Todo)];
    }

    can filter with Todo entry {
        # Only report if not done
        if not here.done {
            report here;
        }
    }
}
```

## Advanced: Updating Todo Text

```jac
walker update_todo {
    has new_text: str;

    class __specs__ {
        has auth: bool = True;
    }

    can update with Todo entry {
        here.text = self.new_text;
        report here;
    }
}

# Frontend usage
await jacSpawn("update_todo", todoId, {"new_text": "Updated text"});
```

## Error Handling in Walkers

```jac
walker create_todo {
    has text: str;

    class __specs__ {
        has auth: bool = True;
    }

    can create with `root entry {
        # Validate input
        if self.text.trim() == "" {
            report {"error": "Text cannot be empty"};
            return;
        }

        # Check if already exists
        let existing = [-->(`?Todo)];
        for todo in existing {
            if todo.text == self.text {
                report {"error": "Todo already exists"};
                return;
            }
        }

        # Create todo
        new_todo = here ++> Todo(text=self.text);
        report {"success": True, "todo": new_todo};
    }
}
```

## Common Walker Patterns

### Pattern 1: Count Items

```jac
walker count_todos {
    class __specs__ {
        has auth: bool = True;
    }

    can count with `root entry {
        let total = [-->(`?Todo)].length;
        let completed = [-->(`?Todo)].filter(
            lambda t: any -> bool { return t.done; }
        ).length;

        report {"total": total, "completed": completed};
    }
}
```

### Pattern 2: Bulk Operations

```jac
walker clear_completed {
    class __specs__ {
        has auth: bool = True;
    }

    can clear with `root entry {
        visit [-->(`?Todo)];
    }

    can delete_if_done with Todo entry {
        if here.done {
            del here;
        }
    }
}
```

### Pattern 3: Complex Queries

```jac
walker search_todos {
    has query: str;

    class __specs__ {
        has auth: bool = True;
    }

    can search with `root entry {
        visit [-->(`?Todo)];
    }

    can filter with Todo entry {
        if self.query.lower() in here.text.lower() {
            report here;
        }
    }
}
```

## Common Issues

### Issue: Walker not found
**Check**: Is the walker defined outside any `cl` block?

### Issue: Permission denied
**Check**: Does your walker have `auth: bool = True`? Are you logged in?

### Issue: Empty reports array
**Check**: Did you call `report` in your walker?

### Issue: Can't access node properties
**Check**: Are you using `here.property` (not `self.property`)?

## What You Learned

- ✅ What walkers are (backend functions)
- ✅ How to define data models with nodes
- ✅ Creating walkers for CRUD operations
- ✅ Calling walkers from frontend with `jacSpawn`
- ✅ Graph traversal syntax (`-->`, `` `?Node ``)
- ✅ Data persistence (automatic!)
- ✅ Walker parameters and specs
- ✅ Reporting data back to frontend

## Next Step

Now you can create and store todos! But anyone can see anyone's todos. Let's add **authentication** to make it secure!

👉 **[Continue to Step 9: Adding Authentication](./step-09-authentication.md)**



