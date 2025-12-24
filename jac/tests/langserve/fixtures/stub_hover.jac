"""Test fixture for hover on type annotations in method stubs with impl files."""

class MyServer {
    has name: str = "server";

    def process(self: MyServer, data: str) -> str;
    def handle(self: MyServer, request: int) -> None;
}
