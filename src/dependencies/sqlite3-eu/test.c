#include "sqlite3_eu.h"

#include <assert.h>

#include <stdio.h>

#include <string.h>

#define TESTTRACE(...) printf(__VA_ARGS__)

#define TESTLOG(text) printf("* %s\n", text)

int assert_result_matches(void * expected_vp, int result_count, char ** result, char ** ignored2)
{
  const char * expected = (const char *) expected_vp;

  assert(result_count == 1);
  TESTTRACE("check string result: %s\n", result[0]);
  assert(!strcmp(result[0], expected));
  TESTTRACE("- OK\n\n");
  return 0;
}

int assert_result_is_null(void * ignored, int result_count, char ** result, char ** ignored2)
{
  assert(result_count == 1);
  if (!!result[0]) TESTTRACE("UNEXPECTED RESULT TEXT: %s\n", result[0]);
  assert(result[0] == NULL);
  TESTTRACE("- OK\n\n");
  return 0;
}

int main() {
  sqlite3 * db;
  sqlite3_open(":memory:", &db);

  sqlite3_eu_init(db, "UPPER_EU", "LOWER_EU");

  TESTLOG("TRY SELECT UPPER_EU with mixed string");

  sqlite3_exec(db, "SELECT UPPER_EU('Alice 😊 é 😊 á 😊 ß 😊 €123')",
    assert_result_matches, "ALICE 😊 É 😊 Á 😊 ẞ 😊 €123", NULL);

  TESTLOG("TRY SELECT UPPER_EU with empty string");

  sqlite3_exec(db, "SELECT UPPER_EU('')", assert_result_matches, "", NULL);

  TESTLOG("TRY SELECT LOWER_EU with mixed string");

  sqlite3_exec(db, "SELECT LOWER_EU('DE100 😊 Chris DEF 😊 ẞ 😊 Á 😊 É 😊 €456')",
    assert_result_matches, "de100 😊 chris def 😊 ß 😊 á 😊 é 😊 €456", NULL);

  // test for brodybits/sqlite3-eu#1
  // ref:
  // - https://github.com/brodybits/sqlite3-eu/pull/1
  // - https://github.com/mobilexag/cordova-sqlite-evplus-ext-free/issues/34
  TESTLOG("TRY SELECT UPPER_EU with mixed string - test brodybits/sqlite3-eu#1 (PR #1)");
  sqlite3_exec(db, "SELECT UPPER_EU('đ ď ð abc')",
    assert_result_matches, "Đ Ď Ð ABC", NULL);

  // TBD STRANGE RESULT for this operation:
  TESTLOG("SELECT LOWER_EU(9e999)");
  sqlite3_exec(db, "SELECT LOWER_EU(9e999)",
    assert_result_matches, "ınf", NULL);

  // TBD STRANGE RESULT for this operation:
  TESTLOG("SELECT HEX(LOWER_EU(9e999))");
  sqlite3_exec(db, "SELECT HEX(LOWER_EU(9e999))",
    assert_result_matches, "C4B16E66", NULL);

  TESTLOG("SELECT LOWER_EU(null)");
  sqlite3_exec(db, "SELECT LOWER_EU(null)", assert_result_is_null, NULL, NULL);

  // TEST TODO: check that all UPPER_EU / LOWER_EU entries
  // are mapped correctly
  // (and none would be broken in the future)

  // built-in UPPER / LOWER tests for comparison:

  TESTLOG("TRY SELECT UPPER('') for comparison");
  sqlite3_exec(db, "SELECT UPPER('')", assert_result_matches, "", NULL);

  TESTLOG("SELECT LOWER(9e999) for comparison");
  sqlite3_exec(db, "SELECT LOWER(9e999)", assert_result_matches, "inf", NULL);

  TESTLOG("SELECT HEX(LOWER(9e999)) for comparison");
  sqlite3_exec(db, "SELECT HEX(LOWER(9e999))", assert_result_matches, "696E66", NULL);

  TESTLOG("SELECT LOWER(null) for comparison");
  sqlite3_exec(db, "SELECT LOWER(null)", assert_result_is_null, NULL, NULL);

  return 0;
}
