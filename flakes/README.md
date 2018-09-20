# Adding new flakiness patterns

1. Add a regular expression to `patterns.txt`

2. Add a test in `tests` directory:
   The test comprises two files: 

   * `xxx.in.txt` that contains some lines that should match a pattern.
     It's recommended to use a piece from real-world logs.
     Please include at least one non-matching line.

     At the top of this file, describe the error and why we recheck it.

   * `xxx.out.txt` that contains only matching lines from `xxx.in.txt`.

3. Run `./run-tests.sh` to verify correctness of a pattern.
