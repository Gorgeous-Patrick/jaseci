# Step 1: Project Setup

In this first step, you'll create a new Jac application from scratch and understand the basic project structure.

## What is a Jac App?

Think of a Jac app like a Python package, but it includes:
- **Backend logic** (similar to Flask/FastAPI routes)
- **Frontend UI** (the visual interface)
- **Data structures** (nodes and edges, like a database schema)
- All in one `.jac` file!

## Creating Your Project

Let's create a new Jac application called "todo-app":

```bash
jac create_jac_app todo-app
```

This command creates a new directory with everything you need:

```
todo-app/
├── app.jac           # Your main application file (we'll work here!)
├── package.json      # Node.js dependencies (auto-managed)
├── vite.config.js    # Build configuration (you can ignore this)
└── README.md         # Basic instructions
```

Navigate into your new project:

```bash
cd todo-app
```

## Understanding `app.jac`

Open `app.jac` in your code editor. You'll see a basic template. Let's understand what's there:

```jac
# This is app.jac - your entire application will live here!
```

**Key concept**: Unlike traditional web development where you have separate files for:
- Backend code (Python/Node.js)
- Frontend code (JavaScript/React)
- Database models (SQL/ORM)

In Jac, **everything lives in one file** (or a few files if your app grows large).

## The Entry Point: `def app()`

Every Jac frontend application needs a main entry point. This is a special function called `app()`:

```jac
cl {
    def app() -> any {
        return <div>
            <h1>Hello, Jac!</h1>
        </div>;
    }
}
```

Let's break this down:

### `cl { ... }`
- `cl` stands for "client"
- Everything inside `cl { }` runs in the **browser** (frontend)
- Think of it like a decorator in Python that says "this code runs on the client-side"

### `def app() -> any`
- This is your **main entry point** - like `if __name__ == "__main__":` in Python
- It must be called `app` (by convention)
- Returns `any` because it returns JSX (HTML-like syntax)

### The `return <div>...</div>`
- This looks like HTML, but it's **JSX** (JavaScript XML)
- You can write HTML directly in your Jac code!
- It gets compiled to efficient React code under the hood

## Running Your App

Let's see your app in action! In your terminal, run:

```bash
jac serve app.jac
```

You'll see output like:

```
INFO:     Started server process [12345]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://127.0.0.1:8000
```

This starts a **single unified server** on port 8000 that:
1. Exposes your walkers as API endpoints (backend)
2. Serves your frontend application
3. Auto-refreshes when you save changes (Coming soon...)

Open your browser and go to: **http://localhost:8000/page/app**

You should see "Hello, Jac!" displayed!

## Your First Edit

Let's make a small change to confirm everything works. Update your `app.jac`:

```jac
cl {
    def app() -> any {
        return <div>
            <h1>My Todo App</h1>
            <p>Building something awesome with Jac!</p>
        </div>;
    }
}
```

Save the file, and your browser will automatically refresh with the new content. Magic! 🎉

## Understanding the Development Workflow

Here's what happens when you run `jac serve app.jac`:

1. **Jac compiler** reads your `.jac` file
2. **Backend code** (walkers) → Converted to API endpoints
3. **Frontend code** (`cl` blocks) → Compiled to JavaScript
4. **Single server** serves both frontend AND backend on the same port
5. **Auto-reload** watches for changes and refreshes (Coming soon...)

**Python analogy**: This is like running `uvicorn main:app --reload` for FastAPI, but it also compiles and serves your React frontend - all in one unified server!

## Common Issues

### Issue: Port 8000 already in use
**Solution**: Kill the process using port 8000, or specify a different port:
```bash
jac serve app.jac --port 8080
```

### Issue: Module not found errors
**Solution**: Make sure you're in the correct directory:
```bash
cd todo-app
ls  # Should see app.jac
```

### Issue: Browser shows blank page
**Solution**: Check the terminal for errors. Make sure your `app()` function has a `return` statement.

## What You Learned

- ✅ How to create a new Jac application
- ✅ The basic structure of a Jac app
- ✅ What `cl { }` means (client-side code)
- ✅ The `def app()` entry point
- ✅ How to run and see your app
- ✅ JSX basics (HTML in your code)

## Next Step

Now that you have a running app, let's learn about **components** - reusable UI building blocks!

👉 **[Continue to Step 2: Components Basics](./step-02-components.md)**



