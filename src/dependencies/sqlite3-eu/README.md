# sqlite3-eu

Add EU string functions to sqlite3:

- `UPPER_EU`
- `LOWER_EU`

**LICENSE:** MIT

## External dependencies

- SQLite3

## Sample usage

```c
int cb(void * ignored1, int result_count, char ** result, char ** ignored2)
{
  printf("result count: %d\n", result_count);
  printf("first result: %s\n", result[0]);
  return 0;
}

int main() {
  sqlite3 * db;
  sqlite3_open(":memory:", &db);

  sqlite3_eu_init(db, "UPPER_EU", "LOWER_EU");

  sqlite3_exec(db, "SELECT UPPER_EU('Alice abc é á ß €123')", cb, NULL, NULL);

  sqlite3_exec(db, "SELECT LOWER_EU('Alice DEF 😊 ẞ Á É €456')", cb, NULL, NULL);

  return 0;
}
```

## How to test

- obtain `sqlite3.h` and `sqlite3.c` from recent SQLite amalgamation
- build `test` and run executable as follows (on a `*nix` workstation):
  - `cc test.c sqlite3.c sqlite3_eu.c -o test`
  - `./test`

## Known quirks

- Statements such as `SELECT LOWER_EU(9e999)` return results like `ınf`
