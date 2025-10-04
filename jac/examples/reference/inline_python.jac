# Inline python - Embedding Python code in Jac

with entry {
    print("hello ");
}

# Python code block using ::py:: delimiters
::py::
def foo():
    print("world")

foo()
::py::
