#include "sqlite3_eu.h"

#include <ctype.h>

#include <stdint.h>

#include <string.h>

#include <stdio.h>

#define EU_MAP_SIZE 0x2000

#define US_ASCII_MAX 0x7f

static uint16_t eu_upper_map[EU_MAP_SIZE] = { 0x30 };
static uint16_t eu_lower_map[EU_MAP_SIZE] = { 0x30 };

#define EU_MAP_ENTRY(lower, upper) \
  do { \
    eu_upper_map[lower] = upper; \
    eu_lower_map[upper] = lower; \
  } while(0)

static
void init_map() {
  {
    int i;

    for (i=0; i<EU_MAP_SIZE; ++i) {
      eu_upper_map[i] = i;
      eu_lower_map[i] = i;
    }

    for (i=0; i<US_ASCII_MAX; ++i) {
      eu_upper_map[i] = toupper(i);
    }

    for (i=0; i<US_ASCII_MAX; ++i) {
      eu_lower_map[i] = tolower(i);
    }
  }

  EU_MAP_ENTRY(0x00E4, 0x00C4);
  EU_MAP_ENTRY(0x00E0, 0x00C0);
  EU_MAP_ENTRY(0x00E1, 0x00C1);
  EU_MAP_ENTRY(0x00E2, 0x00C2);
  EU_MAP_ENTRY(0x00E3, 0x00C3);
  EU_MAP_ENTRY(0x00E5, 0x00C5);
  EU_MAP_ENTRY(0x01CE, 0x01CD);
  EU_MAP_ENTRY(0x0105, 0x0104);
  EU_MAP_ENTRY(0x0103, 0x0102);
  EU_MAP_ENTRY(0x00E6, 0x00C6);
  EU_MAP_ENTRY(0x0101, 0x0100);
  EU_MAP_ENTRY(0x00E7, 0x00C7);
  EU_MAP_ENTRY(0x0107, 0x0106);
  EU_MAP_ENTRY(0x0109, 0x0108);
  EU_MAP_ENTRY(0x010D, 0x010C);
  EU_MAP_ENTRY(0x0111, 0x0110);
  EU_MAP_ENTRY(0x010F, 0x010E);
  EU_MAP_ENTRY(0x00F0, 0x00D0);
  EU_MAP_ENTRY(0x00E8, 0x00C8);
  EU_MAP_ENTRY(0x00E9, 0x00C9);
  EU_MAP_ENTRY(0x00EA, 0x00CA);
  EU_MAP_ENTRY(0x00EB, 0x00CB);
  EU_MAP_ENTRY(0x011B, 0x011A);
  EU_MAP_ENTRY(0x0119, 0x0118);
  EU_MAP_ENTRY(0x0117, 0x0116);
  EU_MAP_ENTRY(0x0113, 0x0112);
  EU_MAP_ENTRY(0x011D, 0x011C);
  EU_MAP_ENTRY(0x0123, 0x0122);
  EU_MAP_ENTRY(0x011F, 0x011E);
  EU_MAP_ENTRY(0x0125, 0x0124);
  EU_MAP_ENTRY(0x00EC, 0x00CC);
  EU_MAP_ENTRY(0x00ED, 0x00CD);
  EU_MAP_ENTRY(0x00EE, 0x00CE);
  EU_MAP_ENTRY(0x00EF, 0x00CF);
  EU_MAP_ENTRY(0x0131, 0x0049);
  EU_MAP_ENTRY(0x012B, 0x012A);
  EU_MAP_ENTRY(0x012F, 0x012E);
  EU_MAP_ENTRY(0x0135, 0x0134);
  EU_MAP_ENTRY(0x0137, 0x0136);
  EU_MAP_ENTRY(0x013A, 0x0139);
  EU_MAP_ENTRY(0x013C, 0x013B);
  EU_MAP_ENTRY(0x0142, 0x0141);
  EU_MAP_ENTRY(0x013E, 0x013D);
  EU_MAP_ENTRY(0x00F1, 0x00D1);
  EU_MAP_ENTRY(0x0144, 0x0143);
  EU_MAP_ENTRY(0x0148, 0x0147);
  EU_MAP_ENTRY(0x0146, 0x0145);
  EU_MAP_ENTRY(0x00F6, 0x00D6);
  EU_MAP_ENTRY(0x00F2, 0x00D2);
  EU_MAP_ENTRY(0x00F3, 0x00D3);
  EU_MAP_ENTRY(0x00F4, 0x00D4);
  EU_MAP_ENTRY(0x00F5, 0x00D5);
  EU_MAP_ENTRY(0x0151, 0x0150);
  EU_MAP_ENTRY(0x00F8, 0x00D8);
  EU_MAP_ENTRY(0x0153, 0x0152);
  EU_MAP_ENTRY(0x0155, 0x0154);
  EU_MAP_ENTRY(0x0159, 0x0158);
  EU_MAP_ENTRY(0x00DF, 0x1E9E);
  EU_MAP_ENTRY(0x015B, 0x015A);
  EU_MAP_ENTRY(0x015D, 0x015C);
  EU_MAP_ENTRY(0x015F, 0x015E);
  EU_MAP_ENTRY(0x0161, 0x0160);
  EU_MAP_ENTRY(0x0219, 0x0218);
  EU_MAP_ENTRY(0x0165, 0x0164);
  EU_MAP_ENTRY(0x0163, 0x0162);
  EU_MAP_ENTRY(0x00FE, 0x00DE);
  EU_MAP_ENTRY(0x021B, 0x021A);
  EU_MAP_ENTRY(0x00FC, 0x00DC);
  EU_MAP_ENTRY(0x00F9, 0x00D9);
  EU_MAP_ENTRY(0x00FA, 0x00DA);
  EU_MAP_ENTRY(0x00FB, 0x00DB);
  EU_MAP_ENTRY(0x0171, 0x0170);
  EU_MAP_ENTRY(0x0169, 0x0168);
  EU_MAP_ENTRY(0x0173, 0x0172);
  EU_MAP_ENTRY(0x016F, 0x016E);
  EU_MAP_ENTRY(0x016B, 0x016A);
  EU_MAP_ENTRY(0x0175, 0x0174);
  EU_MAP_ENTRY(0x00FD, 0x00DD);
  EU_MAP_ENTRY(0x00FF, 0x0178);
  EU_MAP_ENTRY(0x0177, 0x0176);
  EU_MAP_ENTRY(0x017A, 0x0179);
  EU_MAP_ENTRY(0x017E, 0x017D);
  EU_MAP_ENTRY(0x017C, 0x017B);
}

static
void apply_eu_string_map(uint16_t * eu_string_map, sqlite3_context * context, int argc, sqlite3_value ** argv) {
  if (argc < 1 || sqlite3_value_type(argv[0]) == SQLITE_NULL) {
    sqlite3_result_null(context);
  } else if (sqlite3_value_bytes(argv[0]) == 0) {
    // empty string:
    sqlite3_result_text(context, "", 0, NULL);
  } else {
    // THANKS for guidance:
    // http://www.sqlite.org/cgi/src/artifact/43916c1d8e6da5d1
    // (src/func.c:hexFunc)
    sqlite3_value * first = argv[0];

    const uint8_t * in = sqlite3_value_text16le(first);

    const int inlen = sqlite3_value_bytes16(first);

    uint8_t * out = sqlite3_malloc(inlen);

    int i;

    for (i=0; i<inlen; i += 2) {
      uint8_t u0 = in[i];
      uint8_t u1 = in[i+1];

      uint16_t u = (u1 << 8) | u0;

      if (u < EU_MAP_SIZE) {
        int16_t uo = eu_string_map[u];
        out[i] = uo & 0xff;
        out[i+1] = uo >> 8;
      } else {
        out[i] = u0;
        out[i+1] = u1;
      }
    }

    sqlite3_result_text16le(context, out, inlen, sqlite3_free);
  }
}

static
void sqlite3_upper_eu(sqlite3_context * context, int argc, sqlite3_value ** argv) {
  apply_eu_string_map(eu_upper_map, context, argc, argv);
}

static
void sqlite3_lower_eu(sqlite3_context * context, int argc, sqlite3_value ** argv) {
  apply_eu_string_map(eu_lower_map, context, argc, argv);
}

int sqlite3_eu_init(sqlite3 * db, const char * upper_eu_name, const char * lower_eu_name)
{
    init_map();

    /* TBD ignore result for now, at least */

    sqlite3_create_function_v2(db, upper_eu_name, 1, SQLITE_ANY | SQLITE_DETERMINISTIC, NULL, sqlite3_upper_eu, NULL, NULL, NULL);

    sqlite3_create_function_v2(db, lower_eu_name, 1, SQLITE_ANY | SQLITE_DETERMINISTIC, NULL, sqlite3_lower_eu, NULL, NULL, NULL);

    return SQLITE_OK;
}
