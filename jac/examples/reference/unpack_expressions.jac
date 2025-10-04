# Unpack expressions - Unpacking with * and **

def combine_via_func(a: int, b: int, c: int, d: int) -> int {
    return a + b + c + d;
}

with entry {
    # List unpacking with *
    first_list = [1, 2, 3, 4, 5];
    second_list = [5, 8, 7, 6, 9];
    combined_list = [*first_list, *second_list];
    print(combined_list);

    # Dictionary unpacking with **
    first_dict = {'a':1, 'b':2 };
    second_dict = {'c':3, 'd':4 };

    # Combining dictionaries using dictionary unpacking
    combined_dict = {**first_dict, **second_dict };

    # Unpacking in function calls
    print(combine_via_func(**combined_dict));
    print(combine_via_func(**first_dict, **second_dict));

    # Unpacking in assignment
    # a, *rest, b = [1, 2, 3, 4, 5];
}
