# For statements

with entry {
    # For-in loop (Python-style)
    for i in "ban" {
        print(i);
    }

    # For-in with range
    for j in range(1, 3) {
        print(j);
    }

    # For-to-by loop (C-style)
    for k=1 to k<3 by k+=1  {
        print(k);
    }

    # For with else clause (executes when loop completes normally)
    for x in [1, 2, 3] {
        print(x);
    } else {
        print("For loop completed");
    }

    # For with break (else won't execute)
    for num in range(10) {
        if num == 5 {
            break;
        }
        print(num);
    } else {
        print("Won't print due to break");
    }

    # Async for loop
    # async for item in async_iterable {
    #     print(item);
    # }

    # Nested for loops
    for i in "ban" {
        for j in range(1, 3) {
            for k=1 to k<3 by k+=1  {
                print(i, j, k);
            }
        }
    }
}
