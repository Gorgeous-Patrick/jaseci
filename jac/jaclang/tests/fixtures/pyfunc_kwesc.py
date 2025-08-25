


def foo(type= 90):
    """This is a function with a docstring."""
    return type

print(foo(type=89))

def bar(node= 12, *args,**kwargs):
    """This is another function with a docstring."""
    return node, args, kwargs

print(str(bar(node=13, a=1, b=2)))