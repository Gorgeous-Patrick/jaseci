# Context managers

with entry {
    # Basic with statement with as binding
    with open(__file__, 'r') as file {}

    # With expression without as
    # with some_context_manager() {
    #     print("No binding");
    # }

    # Multiple expressions in expr_as_list
    # with open("file1.txt") as f1, open("file2.txt") as f2 {
    #     data1 = f1.read();
    #     data2 = f2.read();
    # }

    # Async with (for async context managers)
    # async with async_context_manager() as resource {
    #     data = await resource.fetch();
    # }

    # With statement for resource management
    class Resource {
        def __enter__(self: Resource) -> Resource {
            print("Acquiring resource");
            return self;
        }

        def __exit__(
            self: Resource, 
            exc_type: `Optional[Type[BaseException]], 
            exc_val: `Optional[BaseException], 
            exc_tb: `Optional[`TracebackType]
            ) -> None {
            print("Releasing resource");
        }
    }

    with Resource() as r {
        print("Using resource");
    }

    # Nested with statements
    # with context1() as c1 {
    #     with context2() as c2 {
    #         print("Nested contexts");
    #     }
    # }
}
