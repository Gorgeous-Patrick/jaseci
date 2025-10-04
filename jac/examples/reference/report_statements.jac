# Report statements - Used in walker context to return data

walker DataCollector {
    has collected: list = [];

    can process with `root entry {
        # Report single value
        report "Processing started";

        # Report expression result
        report 42 * 2;

        # Report variable
        report self.collected;

        # Report complex expression
        report {"status": "complete", "count": len(self.collected)};
    }
}

with entry {
    # Reports are typically used in walker contexts
    w = DataCollector();
    w spawn root;
    # In actual execution, report statements would return values to caller
}
