# Step 2: Components Basics

In this step, you'll learn what components are and how to create reusable UI pieces.

## What is a Component?

Think of components like **Python functions that return HTML**.

In Python, you write functions to avoid repeating code:

```python
def greet_user(name):
    return f"Hello, {name}!"

print(greet_user("Alice"))  # Hello, Alice!
print(greet_user("Bob"))    # Hello, Bob!
```

Components work the same way, but they return **UI elements** instead of strings:

```jac
def GreetUser(name: str) -> any {
    return <h1>Hello, {name}!</h1>;
}
```

## Why Use Components?

1. **Reusability**: Write once, use many times
2. **Organization**: Break your UI into logical pieces
3. **Maintainability**: Easy to find and fix bugs
4. **Composition**: Combine small components into bigger ones

**Python analogy**: Just like you organize Python code into functions and classes, you organize UI into components.

## Creating Your First Component

Let's create a simple welcome component. Update your `app.jac`:

```jac
cl {
    # This is a component - a function that returns JSX
    def WelcomeMessage() -> any {
        return <div>
            <h2>Welcome to Todo App</h2>
            <p>Stay organized and productive!</p>
        </div>;
    }

    # The main entry point
    def app() -> any {
        return <div>
            <h1>My Todo App</h1>
            <WelcomeMessage />
        </div>;
    }
}
```

### Key Points:

1. **Component naming**: Use `PascalCase` (first letter capitalized)
   - ✅ `WelcomeMessage`, `TodoItem`, `UserProfile`
   - ❌ `welcomeMessage`, `todo_item`, `user-profile`

2. **Using a component**: `<WelcomeMessage />`
   - It looks like an HTML tag
   - Self-closing tags need `/` at the end

3. **Return value**: Must return a single root element
   - ✅ `return <div>...</div>`
   - ❌ `return <h1>...</h1> <p>...</p>` (multiple root elements)

## Components with Parameters (Props)

Let's make our component more flexible by accepting parameters (called "props" in React):

```jac
cl {
    # Component with parameters
    def Greeting(name: str, emoji: str) -> any {
        return <div>
            <h2>{emoji} Hello, {name}!</h2>
            <p>Ready to organize your day?</p>
        </div>;
    }

    def app() -> any {
        return <div>
            <h1>My Todo App</h1>
            <Greeting name="Alice" emoji="👋" />
            <Greeting name="Bob" emoji="🎉" />
        </div>;
    }
}
```

### Understanding Props:

- **Definition**: `def Greeting(name: str, emoji: str)`
  - Just like Python function parameters!

- **Usage**: `<Greeting name="Alice" emoji="👋" />`
  - Pass values like HTML attributes

- **Accessing**: Use `{name}` and `{emoji}` inside JSX
  - Curly braces `{}` let you insert Python/Jac values into HTML

**Python analogy**:
```python
# Python function
def greeting(name, emoji):
    return f"{emoji} Hello, {name}!"

# Jac component
def Greeting(name: str, emoji: str) -> any {
    return <h2>{emoji} Hello, {name}!</h2>;
}
```

## Creating a TodoItem Component

Let's create something more practical - a component to display a single todo item:

```jac
cl {
    # A component for displaying a todo item
    def TodoItem(text: str, completed: bool) -> any {
        return <div>
            <input type="checkbox" checked={completed} />
            <span>{text}</span>
        </div>;
    }

    def app() -> any {
        return <div>
            <h1>My Todos</h1>

            <TodoItem text="Learn Jac basics" completed={True} />
            <TodoItem text="Build a todo app" completed={False} />
            <TodoItem text="Deploy to production" completed={False} />
        </div>;
    }
}
```

Notice:
- We pass `text` (a string) and `completed` (a boolean)
- The checkbox uses `checked={completed}` to set its state
- We can reuse `TodoItem` multiple times with different data

## Composing Components

You can nest components inside other components, just like calling functions from other functions:

```jac
cl {
    # Small component for a single todo
    def TodoItem(text: str, done: bool) -> any {
        return <div>
            <input type="checkbox" checked={done} />
            <span>{text}</span>
        </div>;
    }

    # Larger component that uses TodoItem
    def TodoList() -> any {
        return <div>
            <h2>My Tasks</h2>
            <TodoItem text="Morning jog" done={True} />
            <TodoItem text="Code review" done={False} />
            <TodoItem text="Team meeting" done={False} />
        </div>;
    }

    # Main app uses TodoList
    def app() -> any {
        return <div>
            <h1>Todo App</h1>
            <TodoList />
        </div>;
    }
}
```

**Component hierarchy**:
```
app
└── TodoList
    ├── TodoItem (Morning jog)
    ├── TodoItem (Code review)
    └── TodoItem (Team meeting)
```

## Dynamic Content with Expressions

You can put any Jac expression inside `{}`:

```jac
cl {
    def Stats(totalTodos: int, completedTodos: int) -> any {
        let remaining = totalTodos - completedTodos;
        let percentage = (completedTodos / totalTodos) * 100;

        return <div>
            <h3>Progress</h3>
            <p>Total: {totalTodos}</p>
            <p>Completed: {completedTodos}</p>
            <p>Remaining: {remaining}</p>
            <p>Progress: {percentage}%</p>
        </div>;
    }

    def app() -> any {
        return <div>
            <h1>Todo Stats</h1>
            <Stats totalTodos={10} completedTodos={7} />
        </div>;
    }
}
```

## Conditional Rendering

Show different UI based on conditions:

```jac
cl {
    def TodoStatus(completed: bool) -> any {
        if completed {
            return <div>✅ Task completed!</div>;
        } else {
            return <div>⏳ Task pending...</div>;
        }
    }

    def app() -> any {
        return <div>
            <h1>Task Status</h1>
            <TodoStatus completed={True} />
            <TodoStatus completed={False} />
        </div>;
    }
}
```

## Common Issues

### Issue: Component not showing up
**Check**:
- Is the component name in `PascalCase`?
- Did you use `<ComponentName />` (not just `ComponentName`)?
- Does the component have a `return` statement?

### Issue: "Multiple root elements" error
**Solution**: Wrap everything in a single `<div>`:
```jac
# ❌ Wrong
def MyComponent() -> any {
    return <h1>Title</h1><p>Text</p>;
}

# ✅ Correct
def MyComponent() -> any {
    return <div>
        <h1>Title</h1>
        <p>Text</p>
    </div>;
}
```

### Issue: Curly braces not working
**Check**: Make sure you're using `{variable}` not `{{variable}}` or `(variable)`

## What You Learned

- ✅ What components are (functions that return UI)
- ✅ How to create components
- ✅ How to pass data to components (props)
- ✅ How to nest components
- ✅ How to use expressions in JSX with `{}`
- ✅ Conditional rendering

## Practice Exercise

Before moving on, try creating:
1. A `Header` component with your app title
2. A `Footer` component with copyright text
3. Use both in your `app()` function

## Next Step

Your components are plain right now. Let's make them beautiful with **styling**!

👉 **[Continue to Step 3: Adding Styles](./step-03-styling.md)**



