# Collection values

with entry {
    # Dict comprehension
    squares = {num: num ** 2  for num in range(1, 6)};
    print("Dict compr:", squares);

    # Set comprehension with filter
    even_squares_set = {num ** 2  for num in range(1, 11) if num % 2 == 0};
    print("Set compr:", even_squares_set);

    # Generator comprehension
    squares_generator = (num ** 2  for num in range(1, 6));
    print("Gen compr:", list(squares_generator));

    # List comprehension with filter
    squares_list = [num ** 2 for num in range(1, 6) if num != 3];
    print("List compr:", squares_list);

    # Multiple for clauses in comprehension
    combined = [x * y for x in [1, 2, 3] for y in [10, 20]];
    print("Multiple for:", combined);

    # Multiple if clauses in comprehension
    filtered = [x for x in range(20) if x % 2 == 0 if x % 3 == 0];
    print("Multiple if:", filtered);

    # Async comprehension (requires async context)
    # async_list = [x async for x in async_generator()];

    # Dictionary literal
    dict_literal = {"a": "b", "c": "d"};
    print("Dict:", dict_literal);

    # Dictionary with unpacking (STAR_POW)
    base_dict = {"x": 1, "y": 2};
    expanded_dict = {**base_dict, "z": 3};
    print("Dict unpack:", expanded_dict);

    # Set literal
    set_literal = {"a", "b", "c"};
    print("Set:", set_literal);

    # Tuple literal
    tuple_literal = ("a", "b", "c");
    print("Tuple:", tuple_literal);

    # List literal
    list_literal = ['a', 'b', 'c'];
    print("List:", list_literal);

    # Empty collections
    empty_list = [];
    empty_dict = {};
    empty_tuple = ();
    empty_set = set();  # Note: {} is empty dict, not empty set
    print("Empty:", empty_list, empty_dict, empty_tuple, empty_set);

    # Collections with trailing comma
    list_with_comma = [1, 2, 3,];
    dict_with_comma = {"a": 1, "b": 2,};
    tuple_with_comma = (1, 2, 3,);
    print("With comma:", list_with_comma, dict_with_comma, tuple_with_comma);

    # Nested comprehensions
    matrix = [[i * j for j in range(3)] for i in range(3)];
    print("Matrix:", matrix);
}
