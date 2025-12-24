"""Implementation file for stub_hover.jac."""

impl MyServer.process(self: MyServer, data: str) -> str {
    return self.name + ": " + data;
}

impl MyServer.handle(self: MyServer, request: int) -> None {
    print(f"Handling request {request}");
}
