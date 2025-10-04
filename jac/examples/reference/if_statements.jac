# If statements

with entry {
    x = 15;

    # If with elif and else
    if 0 <= x<= 5 {
        print("Not Bad");
    } elif 6 <= x<= 10 {
        print("Average");
    } else {
        print("Good Enough");
    }

    # If without else/elif
    if x > 0 {
        print("Positive");
    }

    # If with elif but no else
    if x < 0 {
        print("Negative");
    } elif x == 0 {
        print("Zero");
    }

    # Multiple elif chains
    if x < 5 {
        print("Very low");
    } elif x < 10 {
        print("Low");
    } elif x < 15 {
        print("Medium");
    } elif x < 20 {
        print("High");
    } else {
        print("Very high");
    }

    # Nested if statements
    if x > 10 {
        if x > 20 {
            print("Greater than 20");
        } else {
            print("Between 10 and 20");
        }
    }
}
