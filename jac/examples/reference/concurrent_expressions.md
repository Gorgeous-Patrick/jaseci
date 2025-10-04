Concurrent expressions in Jac enable asynchronous programming through the `flow` and `wait` keywords, allowing tasks to run concurrently and improving performance for I/O-bound or parallel operations.

**Flow Keyword - Starting Concurrent Tasks**

The `flow` keyword initiates concurrent execution of an expression, immediately returning a task or future object without blocking.

Line 29 demonstrates using `flow` with walker-node interaction: `t1 = flow A() spawn B("Hi")`. This spawns node A and walker B concurrently, returning a task handle that can be waited on later.

Lines 32-34 show concurrent function calls:
- `task1 = flow add(1, 10)` - starts add(1, 10) concurrently
- `task2 = flow add(2, 11)` - starts add(2, 11) concurrently
- `print("All are started")` - executes immediately without waiting

Both `add` calls run in parallel. The print statement executes right away because `flow` doesn't block - it returns immediately after scheduling the tasks.

**Wait Keyword - Collecting Results**

The `wait` keyword blocks until a concurrent task completes and returns its result.

Lines 37-38 demonstrate waiting for task completion:
- `res1 = wait task1` - blocks until task1 finishes, returns its result
- `res2 = wait task2` - blocks until task2 finishes, returns its result

Lines 40-41 print the results after both tasks complete.

**Concurrent Execution Model**

The `add` function (lines 19-25) includes `sleep(2)` calls to simulate long-running operations. When called with `flow`:
1. Both `add` calls start nearly simultaneously
2. Program continues to line 34 without waiting
3. When `wait` is called, execution blocks until the task completes
4. If a task has already finished, `wait` returns immediately

**Implementation Details**

Under the hood, Jac's `flow`/`wait` concurrency uses Python's standard `concurrent.futures.ThreadPoolExecutor`:
- `flow` submits the expression as a callable to a shared `ThreadPoolExecutor` and returns a `Future`-like handle
- `wait` calls the underlying future's `.result()` to retrieve the value
- The thread pool is shared across the entire program with a default size based on CPU count
- Exception propagation works naturally—if the background computation raises an exception, `wait` re-raises it in the calling thread
- Best suited for I/O-bound or mixed workloads; CPU-bound speedups are subject to Python's Global Interpreter Lock (GIL) like ordinary threads
- This is **thread-based** concurrency, distinct from Python's event-loop based `async`/`await` model

**Node and Walker Concurrency**

Lines 5-17 define a node A with an `entry` ability and walker B. Line 29 shows that `flow` works with walker-node spawning, enabling concurrent graph traversal and node processing.

**Benefits**

Concurrent expressions allow:
- Parallel I/O operations (network requests, file I/O)
- Improved responsiveness by not blocking on long-running operations
- Explicit control over when to wait for results
- Expression-level concurrency that composes naturally with other Jac features
- Parallel map patterns through list comprehensions with `flow`/`wait`

**Comparison with async/await**

While similar in concept to async/await in other languages, `flow`/`wait` differs in important ways:
- `flow`/`wait` is **thread-based**, using `ThreadPoolExecutor`
- `async`/`await` is **event-loop based**, requiring special async functions
- You can mix both when appropriate: use `flow` for blocking I/O or CPU-bound work; use `async`/`await` for event-driven I/O
- `flow`/`wait` works anywhere expressions are valid, including comprehensions and argument lists