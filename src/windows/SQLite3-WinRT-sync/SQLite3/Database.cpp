#include "Winerror.h"

#include "Database.h"
#include "Statement.h"


#include "sqlite3_base64.h"

#include "sqlite3_eu.h"

namespace SQLite3
{
  Database::Database(Platform::String^ dbPath)
    : sqlite(nullptr)
  {
    int ret = sqlite3_open16(dbPath->Data(), &sqlite);

    if (ret != SQLITE_OK)
    {
      sqlite3_close(sqlite);

      HRESULT hresult = MAKE_HRESULT(SEVERITY_ERROR, FACILITY_ITF, ret);
      throw ref new Platform::COMException(hresult);
    }

    sqlite3_db_config(sqlite, SQLITE_DBCONFIG_DEFENSIVE, 1, NULL);
    sqlite3_base64_init(sqlite);
    sqlite3_eu_init(sqlite, "UPPER", "LOWER");
  }

  Database::~Database()
  {
    if (sqlite != nullptr) sqlite3_close(sqlite);
  }

  Statement^ Database::Prepare(Platform::String^ sql)
  {
    return ref new Statement(this, sql);
  }

  int Database::closedb()
  {
    int rc = sqlite3_close(sqlite);
	if (rc == SQLITE_OK) sqlite = nullptr;
	return rc;
  }

  int Database::close_v2()
  {
    int rc = sqlite3_close_v2(sqlite);
	if (rc == SQLITE_OK) sqlite = nullptr;
	return rc;
  }

  int Database::LastInsertRowid()
  {
    return sqlite3_last_insert_rowid(sqlite);
  }

  int Database::TotalChanges()
  {
    return sqlite3_total_changes(sqlite);
  }
  // FUTURE TBD CLEANUP NEEDED:
  Platform::String^ Database::ErrMessage() { return ref new Platform::String(static_cast<const wchar_t*>(errmsg.c_str())); }
}
