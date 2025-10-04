This example demonstrates the fundamental concept of walker abilities and the special `entry` ability that serves as the walker's entry point when spawned.

**Walker Declaration and Entry Point**

Lines 3-9 define a walker named `Visitor` with a single ability called `self_destruct`. The `with entry` clause on line 4 marks this ability as the entry point, which means it will be executed automatically when the walker is spawned. Entry abilities serve as the initialization or main execution logic for a walker.

**Disengage Statement**

Line 6 demonstrates the `disengage` statement, which is a control flow statement unique to walkers. When `disengage` is executed, it immediately terminates the walker's execution and destroys the walker instance. Any code after `disengage` in the same ability will not execute. This is why line 5 prints "get's here" but line 7 never executes and doesn't print "but not here".

**Walker Spawning**

Lines 11-13 show the module-level entry point using `with entry`. Line 12 demonstrates how to spawn a walker using the `spawn` operation: `root spawn Visitor()`. This spawns an instance of the `Visitor` walker on the `root` node (which is the implicit root of the spatial graph). When spawned, the walker's entry ability (`self_destruct`) is automatically invoked.

**Execution Flow**

1. The module entry point executes (line 11-13)
2. A `Visitor` walker is spawned on the root node
3. The walker's `self_destruct` entry ability is invoked
4. "get's here" is printed
5. `disengage` terminates the walker
6. "but not here" is never reached
