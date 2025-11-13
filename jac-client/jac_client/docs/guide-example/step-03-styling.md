# Step 3: Adding Inline Styles

In this step, you'll learn how to make your components beautiful using inline styles.

## What are Inline Styles?

In traditional HTML, you might write:

```html
<div style="color: blue; font-size: 20px;">Hello</div>
```

In Jac (using JSX), styles are written as **dictionaries** (objects):

```jac
<div style={{"color": "blue", "fontSize": "20px"}}>Hello</div>
```

**Python analogy**: Just like passing a dictionary to a function!

```python
# Python
styles = {"color": "blue", "fontSize": "20px"}
print(styles)

# Jac/JSX
<div style={{"color": "blue", "fontSize": "20px"}}>Hello</div>
```

## Basic Styling Syntax

### Single Style Property

```jac
cl {
    def app() -> any {
        return <div style={{"color": "blue"}}>
            <h1>Blue Text</h1>
        </div>;
    }
}
```

### Multiple Style Properties

```jac
cl {
    def app() -> any {
        return <div style={{
            "color": "blue",
            "fontSize": "20px",
            "padding": "10px",
            "backgroundColor": "#f0f0f0"
        }}>
            <h1>Styled Text</h1>
        </div>;
    }
}
```

### Important Notes:

1. **camelCase property names**:
   - CSS: `background-color` → JSX: `"backgroundColor"`
   - CSS: `font-size` → JSX: `"fontSize"`
   - CSS: `margin-top` → JSX: `"marginTop"`

2. **String values** need quotes:
   - ✅ `"color": "blue"`
   - ✅ `"padding": "10px"`
   - ✅ `"fontSize": "20px"`

3. **Double curly braces** `{{ }}`:
   - Outer `{}`: "I'm inserting a Jac value"
   - Inner `{}`: "This is a dictionary/object"

## Creating a Styled Button

Let's style a button component:

```jac
cl {
    def StyledButton(text: str) -> any {
        return <button style={{
            "padding": "12px 24px",
            "backgroundColor": "#3b82f6",
            "color": "white",
            "border": "none",
            "borderRadius": "8px",
            "fontSize": "16px",
            "fontWeight": "600",
            "cursor": "pointer"
        }}>
            {text}
        </button>;
    }

    def app() -> any {
        return <div>
            <h1>My Todo App</h1>
            <StyledButton text="Add Todo" />
            <StyledButton text="Clear All" />
        </div>;
    }
}
```

## Common CSS Properties

Here are the most common properties you'll use:

### Layout & Spacing
```jac
{
    "display": "flex",           # Flexbox layout
    "flexDirection": "column",   # Stack vertically
    "gap": "16px",              # Space between children
    "padding": "20px",          # Inner spacing
    "margin": "10px",           # Outer spacing
}
```

### Colors & Backgrounds
```jac
{
    "color": "#1f2937",              # Text color
    "backgroundColor": "#ffffff",     # Background color
    "border": "1px solid #e5e7eb",   # Border
    "boxShadow": "0 1px 3px rgba(0,0,0,0.1)"  # Shadow
}
```

### Typography
```jac
{
    "fontSize": "16px",
    "fontWeight": "600",      # Bold (100-900)
    "fontFamily": "sans-serif",
    "textAlign": "center",
    "lineHeight": "1.5"
}
```

### Borders & Corners
```jac
{
    "borderRadius": "8px",    # Rounded corners
    "border": "1px solid #ccc",
    "borderBottom": "2px solid blue"
}
```

## Styling the Todo Item

Let's create a nicely styled todo item:

```jac
cl {
    def TodoItem(text: str, completed: bool) -> any {
        return <div style={{
            "display": "flex",
            "alignItems": "center",
            "gap": "12px",
            "padding": "16px",
            "backgroundColor": "#ffffff",
            "borderRadius": "8px",
            "border": "1px solid #e5e7eb",
            "marginBottom": "8px"
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
                "color": "white",
                "border": "none",
                "borderRadius": "6px",
                "fontSize": "14px",
                "cursor": "pointer"
            }}>
                Delete
            </button>
        </div>;
    }

    def app() -> any {
        return <div style={{
            "maxWidth": "720px",
            "margin": "0 auto",
            "padding": "24px",
            "backgroundColor": "#f9fafb",
            "minHeight": "100vh"
        }}>
            <h1 style={{
                "textAlign": "center",
                "color": "#1f2937",
                "marginBottom": "24px"
            }}>
                My Todos
            </h1>

            <TodoItem text="Learn Jac" completed={True} />
            <TodoItem text="Build Todo App" completed={False} />
            <TodoItem text="Deploy App" completed={False} />
        </div>;
    }
}
```

## Conditional Styling

You can change styles based on props:

```jac
cl {
    def StatusBadge(status: str) -> any {
        let bgColor = "gray";
        let textColor = "white";

        if status == "completed" {
            bgColor = "#22c55e";  # Green
        } elif status == "pending" {
            bgColor = "#eab308";  # Yellow
        } elif status == "urgent" {
            bgColor = "#ef4444";  # Red
        }

        return <span style={{
            "padding": "4px 12px",
            "backgroundColor": bgColor,
            "color": textColor,
            "borderRadius": "12px",
            "fontSize": "14px",
            "fontWeight": "600"
        }}>
            {status}
        </span>;
    }

    def app() -> any {
        return <div style={{"padding": "20px"}}>
            <StatusBadge status="completed" />
            <StatusBadge status="pending" />
            <StatusBadge status="urgent" />
        </div>;
    }
}
```

## Reusing Style Objects

To avoid repetition, store styles in variables:

```jac
cl {
    def app() -> any {
        # Define common styles
        let buttonStyle = {
            "padding": "12px 24px",
            "border": "none",
            "borderRadius": "8px",
            "fontSize": "16px",
            "cursor": "pointer",
            "fontWeight": "600"
        };

        let primaryButtonStyle = {
            "padding": buttonStyle["padding"],
            "border": buttonStyle["border"],
            "borderRadius": buttonStyle["borderRadius"],
            "fontSize": buttonStyle["fontSize"],
            "cursor": buttonStyle["cursor"],
            "fontWeight": buttonStyle["fontWeight"],
            "backgroundColor": "#3b82f6",
            "color": "white"
        };

        let dangerButtonStyle = {
            "padding": buttonStyle["padding"],
            "border": buttonStyle["border"],
            "borderRadius": buttonStyle["borderRadius"],
            "fontSize": buttonStyle["fontSize"],
            "cursor": buttonStyle["cursor"],
            "fontWeight": buttonStyle["fontWeight"],
            "backgroundColor": "#ef4444",
            "color": "white"
        };

        return <div>
            <button style={primaryButtonStyle}>Save</button>
            <button style={dangerButtonStyle}>Delete</button>
        </div>;
    }
}
```

## Layout with Flexbox

Flexbox makes it easy to arrange items:

```jac
cl {
    def app() -> any {
        return <div style={{
            "display": "flex",
            "flexDirection": "column",  # Stack vertically
            "gap": "16px",              # Space between items
            "padding": "20px"
        }}>
            {/* Header */}
            <div style={{
                "backgroundColor": "#3b82f6",
                "color": "white",
                "padding": "20px",
                "borderRadius": "8px"
            }}>
                <h1>Header</h1>
            </div>

            {/* Content */}
            <div style={{
                "display": "flex",
                "gap": "16px"  # Horizontal spacing
            }}>
                <div style={{
                    "flex": "1",
                    "backgroundColor": "#f3f4f6",
                    "padding": "20px",
                    "borderRadius": "8px"
                }}>
                    Sidebar
                </div>
                <div style={{
                    "flex": "3",
                    "backgroundColor": "#ffffff",
                    "padding": "20px",
                    "borderRadius": "8px"
                }}>
                    Main Content
                </div>
            </div>
        </div>;
    }
}
```

## Color Palettes to Use

Here are some nice, modern color combinations:

### Blue Theme (Professional)
```jac
{
    "primary": "#3b82f6",      # Blue
    "background": "#f9fafb",   # Light gray
    "text": "#1f2937",         # Dark gray
    "border": "#e5e7eb",       # Light border
    "success": "#22c55e",      # Green
    "danger": "#ef4444"        # Red
}
```

### Purple Theme (Creative)
```jac
{
    "primary": "#8b5cf6",      # Purple
    "background": "#faf5ff",   # Light purple
    "text": "#1e1b4b",         # Dark blue
    "border": "#e9d5ff",       # Light purple border
    "success": "#10b981",      # Emerald
    "danger": "#f43f5e"        # Rose
}
```

## Common Issues

### Issue: Styles not applying
**Check**:
- Did you use double curly braces `{{ }}`?
- Are property names in quotes? `"padding"` not `padding`
- Are values in quotes? `"20px"` not `20px`

### Issue: CSS property not working
**Solution**: Convert kebab-case to camelCase:
- `background-color` → `"backgroundColor"`
- `font-weight` → `"fontWeight"`
- `margin-top` → `"marginTop"`

### Issue: Number values
**Use strings** for CSS values:
- ✅ `"padding": "20px"`
- ❌ `"padding": 20`

## What You Learned

- ✅ How to write inline styles in Jac
- ✅ CSS property naming (camelCase)
- ✅ Common CSS properties for layout, colors, and typography
- ✅ Conditional styling based on props
- ✅ Reusing style objects
- ✅ Flexbox basics for layout

## Practice Exercise

Try styling a complete todo card with:
1. A colored border on the left
2. A rounded profile avatar
3. A hover effect (we'll learn interactive styles later)
4. Different background colors for completed vs pending

## Next Step

Now that your components look great, let's build the complete **Todo UI**!

👉 **[Continue to Step 4: Building the Todo UI](./step-04-todo-ui.md)**



