# Building a Full-Stack Todo App with Jac: Complete Walkthrough

Welcome to this comprehensive guide on building a complete, production-ready Todo application using Jac! This tutorial is specifically designed for **Python developers** who are new to frontend development.

## What You'll Build

By the end of this guide, you'll have created a fully functional Todo application with:

- ✅ **User authentication** (signup and login)
- ✅ **Protected routes** (dashboard only accessible when logged in)
- ✅ **Full CRUD operations** (Create, Read, Update, Delete todos)
- ✅ **Persistent data** (stored on the backend)
- ✅ **Modern UI** with inline styling
- ✅ **Client-side routing** (multiple pages without page reloads)

## Why Jac for Frontend Development?

If you're coming from Python, you'll love Jac because:

- **Familiar syntax**: Jac feels like Python with superpowers
- **Full-stack in one language**: Write both backend (walkers, nodes) and frontend (UI components) in the same file
- **No separate frontend/backend**: Your data structures and API endpoints are automatically connected
- **Type safety**: Optional type hints like Python 3.5+
- **React under the hood**: You get all the power of React without learning JavaScript first

## Prerequisites

Before starting, you should have:

- **Python 3.12 or higher** installed on your system
  - Download: [https://www.python.org/downloads/](https://www.python.org/downloads/)
- **Node.js 20 or higher** and npm installed (required for frontend dependencies)
  - Download: [https://nodejs.org/](https://nodejs.org/) (npm is included with Node.js)
- A code editor (VS Code recommended with Jac extension)
  - Download: [https://code.visualstudio.com/](https://code.visualstudio.com/)
- Basic Python knowledge
- Basic understanding of HTML/CSS concepts (helpful but not required)

### Quick Setup Check

Verify your environment is ready by running:

```bash
python --version    # Should show Python 3.12+
node --version      # Should show Node 20+
npm --version       # Should show npm
jac --version       # Should show Jac is installed
```

If Jac is not installed, run:

```bash
pip install jac-client
```

> **Note:** If you have previously installed `jaclang`, please uninstall it first using `pip uninstall jaclang`. The required version of `jaclang` will be installed automatically as a dependency of `jac-client`, so you do not need to install it separately.

## What You'll Learn

This walkthrough is divided into 10 progressive steps:

1. **[Step 1: Project Setup](./step-01-setup.md)** - Creating a new Jac app from scratch
2. **[Step 2: Components Basics](./step-02-components.md)** - Understanding and creating your first component
3. **[Step 3: Styling](./step-03-styling.md)** - Adding inline styles to make your app beautiful
4. **[Step 4: Building the UI](./step-04-todo-ui.md)** - Creating the todo interface
5. **[Step 5: Local State](./step-05-local-state.md)** - Managing component state with `useState`
6. **[Step 6: Side Effects](./step-06-effects.md)** - Using `useEffect` for data loading
7. **[Step 7: Routing](./step-07-routing.md)** - Adding multiple pages with React Router
8. **[Step 8: Backend with Walkers](./step-08-walkers.md)** - Creating backend logic with walkers
9. **[Step 9: Authentication](./step-09-authentication.md)** - Adding user signup and login
10. **[Step 10: Final Integration](./step-10-final.md)** - Putting it all together

## Learning Approach

Each step builds on the previous one, so **follow them in order**. We'll:

- Start simple and add complexity gradually
- Explain *why* we're doing something before showing *how*
- Use analogies to connect frontend concepts with Python concepts you already know
- Show complete, working code at each step

## Time Commitment

- **Quick path**: 2-3 hours (following along and typing the code)
- **Learning path**: 4-6 hours (experimenting and understanding each concept)

## Getting Help

- If you get stuck, each step has a **"Common Issues"** section
- The complete final code is available in the last step for reference
- Check the [Jac Documentation](https://www.jac-lang.org) for API details

## Ready to Start?

Let's dive in! Head to **[Step 1: Project Setup](./step-01-setup.md)** to create your first Jac application.

---

## Want to Learn More About React?

Once you complete this guide, if you want to dive deeper into React concepts (the framework powering Jac's frontend), check out:

- [React Official Documentation](https://react.dev/learn)
- [React Hooks Guide](https://react.dev/reference/react)

These resources will help you understand the underlying React patterns that Jac uses, but they're **not required** to build great apps with Jac!


