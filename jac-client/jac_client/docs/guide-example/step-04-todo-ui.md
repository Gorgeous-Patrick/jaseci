# Step 4: Building the Todo UI

In this step, you'll create the complete user interface for your todo application (without functionality yet - we'll add that next!).

## Planning the UI Structure

Before coding, let's think about what a todo app needs:

1. **Header** - App title and branding
2. **Input Section** - Text field + "Add" button
3. **Filter Buttons** - Show All / Active / Completed
4. **Todo List** - Display all todos
5. **Footer Stats** - Items remaining, Clear completed button

Think of it like planning a Python class structure before implementing methods.

## Creating the Complete UI

Let's build each section as a component:

### 1. Input Section Component

```jac
cl {
    def TodoInput() -> any {
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
}
```

**What's happening here:**
- `display: "flex"` - Places input and button side-by-side
- `flex: "1"` on input - Input takes all available space
- `placeholder` - Gray hint text shown when empty

### 2. Filter Buttons Component

```jac
cl {
    def FilterButtons() -> any {
        return <div style={{
            "display": "flex",
            "gap": "8px",
            "marginBottom": "24px",
            "justifyContent": "center"
        }}>
            <button style={{
                "padding": "8px 16px",
                "backgroundColor": "#3b82f6",
                "color": "#ffffff",
                "border": "1px solid #3b82f6",
                "borderRadius": "6px",
                "fontSize": "14px",
                "fontWeight": "600",
                "cursor": "pointer"
            }}>
                All
            </button>
            <button style={{
                "padding": "8px 16px",
                "backgroundColor": "#ffffff",
                "color": "#3b82f6",
                "border": "1px solid #3b82f6",
                "borderRadius": "6px",
                "fontSize": "14px",
                "fontWeight": "600",
                "cursor": "pointer"
            }}>
                Active
            </button>
            <button style={{
                "padding": "8px 16px",
                "backgroundColor": "#ffffff",
                "color": "#3b82f6",
                "border": "1px solid #3b82f6",
                "borderRadius": "6px",
                "fontSize": "14px",
                "fontWeight": "600",
                "cursor": "pointer"
            }}>
                Completed
            </button>
        </div>;
    }
}
```

**Design pattern**: One button is "active" (filled background), others are "inactive" (white background). We'll make this dynamic later.

### 3. Todo Item Component

```jac
cl {
    def TodoItem(text: str, completed: bool) -> any {
        return <div style={{
            "display": "flex",
            "alignItems": "center",
            "gap": "12px",
            "padding": "16px",
            "borderBottom": "1px solid #e5e7eb"
        }}>
            <input
                type="checkbox"
                checked={completed}
                style={{
                    "width": "20px",
                    "height": "20px",
                    "cursor": "pointer"
                }}
            />
            <span style={{
                "flex": "1",
                "fontSize": "16px",
                "color": (("#9ca3af" if completed else "#1f2937")),
                "textDecoration": (("line-through" if completed else "none"))
            }}>
                {text}
            </span>
            <button style={{
                "padding": "6px 12px",
                "backgroundColor": "#ef4444",
                "color": "#ffffff",
                "border": "none",
                "borderRadius": "6px",
                "fontSize": "14px",
                "fontWeight": "500",
                "cursor": "pointer"
            }}>
                Delete
            </button>
        </div>;
    }
}
```

**Key features:**
- Checkbox for marking complete/incomplete
- Text color changes when completed (gray)
- Strike-through text when completed
- Red delete button

### 4. Todo List Container

```jac
cl {
    def TodoList() -> any {
        return <div style={{
            "backgroundColor": "#ffffff",
            "borderRadius": "12px",
            "boxShadow": "0 1px 3px rgba(0,0,0,0.1)",
            "overflow": "hidden"
        }}>
            <TodoItem text="Learn Jac basics" completed={True} />
            <TodoItem text="Build a todo app" completed={False} />
            <TodoItem text="Deploy to production" completed={False} />
        </div>;
    }
}
```

### 5. Footer Stats Component

```jac
cl {
    def TodoFooter() -> any {
        return <div style={{
            "display": "flex",
            "justifyContent": "space-between",
            "alignItems": "center",
            "marginTop": "24px",
            "padding": "16px",
            "backgroundColor": "#ffffff",
            "borderRadius": "12px",
            "boxShadow": "0 1px 3px rgba(0,0,0,0.1)"
        }}>
            <span style={{
                "color": "#6b7280",
                "fontSize": "14px"
            }}>
                2 items left
            </span>
            <button style={{
                "padding": "8px 16px",
                "backgroundColor": "#ef4444",
                "color": "#ffffff",
                "border": "none",
                "borderRadius": "6px",
                "fontSize": "14px",
                "fontWeight": "600",
                "cursor": "pointer"
            }}>
                Clear Completed
            </button>
        </div>;
    }
}
```

## Putting It All Together

Now let's combine all components into the main app:

```jac
cl {
    # Header Component
    def Header() -> any {
        return <h1 style={{
            "textAlign": "center",
            "color": "#1f2937",
            "marginBottom": "24px",
            "fontSize": "2.5rem",
            "fontWeight": "700"
        }}>
            📝 My Todo App
        </h1>;
    }

    # Input Section
    def TodoInput() -> any {
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

    # Filter Buttons
    def FilterButtons() -> any {
        return <div style={{
            "display": "flex",
            "gap": "8px",
            "marginBottom": "24px",
            "justifyContent": "center"
        }}>
            <button style={{
                "padding": "8px 16px",
                "backgroundColor": "#3b82f6",
                "color": "#ffffff",
                "border": "1px solid #3b82f6",
                "borderRadius": "6px",
                "fontSize": "14px",
                "fontWeight": "600",
                "cursor": "pointer"
            }}>
                All
            </button>
            <button style={{
                "padding": "8px 16px",
                "backgroundColor": "#ffffff",
                "color": "#3b82f6",
                "border": "1px solid #3b82f6",
                "borderRadius": "6px",
                "fontSize": "14px",
                "fontWeight": "600",
                "cursor": "pointer"
            }}>
                Active
            </button>
            <button style={{
                "padding": "8px 16px",
                "backgroundColor": "#ffffff",
                "color": "#3b82f6",
                "border": "1px solid #3b82f6",
                "borderRadius": "6px",
                "fontSize": "14px",
                "fontWeight": "600",
                "cursor": "pointer"
            }}>
                Completed
            </button>
        </div>;
    }

    # Single Todo Item
    def TodoItem(text: str, completed: bool) -> any {
        return <div style={{
            "display": "flex",
            "alignItems": "center",
            "gap": "12px",
            "padding": "16px",
            "borderBottom": "1px solid #e5e7eb"
        }}>
            <input
                type="checkbox"
                checked={completed}
                style={{
                    "width": "20px",
                    "height": "20px",
                    "cursor": "pointer"
                }}
            />
            <span style={{
                "flex": "1",
                "fontSize": "16px",
                "color": (("#9ca3af" if completed else "#1f2937")),
                "textDecoration": (("line-through" if completed else "none"))
            }}>
                {text}
            </span>
            <button style={{
                "padding": "6px 12px",
                "backgroundColor": "#ef4444",
                "color": "#ffffff",
                "border": "none",
                "borderRadius": "6px",
                "fontSize": "14px",
                "fontWeight": "500",
                "cursor": "pointer"
            }}>
                Delete
            </button>
        </div>;
    }

    # Todo List Container
    def TodoList() -> any {
        return <div style={{
            "backgroundColor": "#ffffff",
            "borderRadius": "12px",
            "boxShadow": "0 1px 3px rgba(0,0,0,0.1)",
            "overflow": "hidden"
        }}>
            <TodoItem text="Learn Jac basics" completed={True} />
            <TodoItem text="Build a todo app" completed={False} />
            <TodoItem text="Deploy to production" completed={False} />
        </div>;
    }

    # Footer Stats
    def TodoFooter() -> any {
        return <div style={{
            "display": "flex",
            "justifyContent": "space-between",
            "alignItems": "center",
            "marginTop": "24px",
            "padding": "16px",
            "backgroundColor": "#ffffff",
            "borderRadius": "12px",
            "boxShadow": "0 1px 3px rgba(0,0,0,0.1)"
        }}>
            <span style={{
                "color": "#6b7280",
                "fontSize": "14px"
            }}>
                2 items left
            </span>
            <button style={{
                "padding": "8px 16px",
                "backgroundColor": "#ef4444",
                "color": "#ffffff",
                "border": "none",
                "borderRadius": "6px",
                "fontSize": "14px",
                "fontWeight": "600",
                "cursor": "pointer"
            }}>
                Clear Completed
            </button>
        </div>;
    }

    # Main App
    def app() -> any {
        return <div style={{
            "maxWidth": "720px",
            "margin": "0 auto",
            "padding": "24px",
            "backgroundColor": "#f9fafb",
            "minHeight": "100vh",
            "fontFamily": "sans-serif"
        }}>
            <Header />
            <TodoInput />
            <FilterButtons />
            <TodoList />
            <TodoFooter />
        </div>;
    }
}
```

## Understanding the Layout

```
┌─────────────────────────────────────┐
│          📝 My Todo App             │  ← Header
├─────────────────────────────────────┤
│ [Input field...........] [Add]      │  ← TodoInput
├─────────────────────────────────────┤
│     [All] [Active] [Completed]      │  ← FilterButtons
├─────────────────────────────────────┤
│ ☑ Learn Jac basics      [Delete]    │  ← TodoList
│ ☐ Build a todo app      [Delete]    │     (multiple
│ ☐ Deploy to production  [Delete]    │      TodoItems)
├─────────────────────────────────────┤
│ 2 items left    [Clear Completed]   │  ← TodoFooter
└─────────────────────────────────────┘
```

## Testing Your UI

Save your `app.jac` file and check your browser. You should see:

- A centered, card-based layout
- Three hardcoded todos
- All buttons (they don't work yet!)
- Beautiful spacing and colors

**Try clicking things** - nothing happens! That's expected. In the next step, we'll add **state** to make it interactive.

## Empty State Handling

What if there are no todos? Let's add that:

```jac
def TodoList() -> any {
    let hasTodos = False;  # We'll make this dynamic later

    if hasTodos {
        return <div style={{
            "backgroundColor": "#ffffff",
            "borderRadius": "12px",
            "boxShadow": "0 1px 3px rgba(0,0,0,0.1)",
            "overflow": "hidden"
        }}>
            <TodoItem text="Learn Jac basics" completed={True} />
        </div>;
    } else {
        return <div style={{
            "backgroundColor": "#ffffff",
            "borderRadius": "12px",
            "boxShadow": "0 1px 3px rgba(0,0,0,0.1)",
            "padding": "40px",
            "textAlign": "center",
            "color": "#9ca3af"
        }}>
            No todos yet. Add one above!
        </div>;
    }
}
```

## Common Issues

### Issue: Components overlapping
**Solution**: Check your `gap` and `marginBottom` values in parent containers.

### Issue: Button not clickable
**Don't worry!** We haven't added click handlers yet. That comes in the next step.

### Issue: Layout broken on mobile
**Solution**: Make sure your parent container has:
```jac
{
    "maxWidth": "720px",
    "margin": "0 auto",
    "padding": "24px"
}
```

### Issue: Text overflowing
**Solution**: Add `"overflow": "hidden"` and `"textOverflow": "ellipsis"` to long text containers.

## What You Learned

- ✅ How to structure a complete application UI
- ✅ Breaking down complex UIs into small components
- ✅ Using Flexbox for layout
- ✅ Creating consistent spacing and styling
- ✅ Handling empty states
- ✅ Building a production-ready UI design

## Component Checklist

Before moving on, make sure you have:
- [ ] Header component
- [ ] TodoInput component
- [ ] FilterButtons component
- [ ] TodoItem component
- [ ] TodoList component
- [ ] TodoFooter component
- [ ] Main app component that combines everything

## Next Step

Your UI looks great but it's static! Let's make it **interactive** by adding **local state**.

👉 **[Continue to Step 5: Adding Local State](./step-05-local-state.md)**



