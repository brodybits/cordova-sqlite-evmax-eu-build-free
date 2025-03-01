/*
 * Copyright (c) 2012-present Christopher J. Brody (aka Chris Brody)
 * Copyright (C) 2011 Davide Bertola
 *
 * License for this version: GPL v3 (http://www.gnu.org/licenses/gpl.txt) or commercial license.
 * Contact for commercial license: info@litehelpers.net
 */

#import "SQLitePlugin.h"

#import "sqlite3.h"

#import "sqlite3_regexp.h"

#import "sqlite3_base64.h"

#import "sqlite3_eu.h"

// Defines Macro to only log lines when in DEBUG mode
#ifdef DEBUG
#   define DLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);
#else
#   define DLog(...)
#endif

#if !__has_feature(objc_arc)
#   error "Missing objc_arc feature"
#endif

// CustomPSPDFThreadSafeMutableDictionary interface copied from
// CustomPSPDFThreadSafeMutableDictionary.m:
//
// Dictionary-Subclasss whose primitive operations are thread safe.
@interface CustomPSPDFThreadSafeMutableDictionary : NSMutableDictionary
@end

@implementation SQLitePlugin

@synthesize openDBs;
@synthesize appDBPaths;

-(void)pluginInitialize
{
    DLog(@"Initializing SQLitePlugin");

    {
        openDBs = [CustomPSPDFThreadSafeMutableDictionary dictionaryWithCapacity:0];
        appDBPaths = [NSMutableDictionary dictionaryWithCapacity:0];

        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex: 0];
        DLog(@"Detected docs path: %@", docs);
        [appDBPaths setObject: docs forKey:@"docs"];

        NSString *libs = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex: 0];
        DLog(@"Detected Library path: %@", libs);
        [appDBPaths setObject: libs forKey:@"libs"];

        NSString *nosync = [libs stringByAppendingPathComponent:@"LocalDatabase"];
        NSError *err;

        // GENERAL NOTE: no `nosync` directory path entry to be added
        // to appDBPaths map in case of any isses creating the
        // required directory or setting the resource value for
        // NSURLIsExcludedFromBackupKey
        //
        // This is to avoid potential for issue raised here:
        // https://github.com/xpbrew/cordova-sqlite-storage/issues/907

        if ([[NSFileManager defaultManager] fileExistsAtPath: nosync])
        {
            DLog(@"no cloud sync directory already exists at path: %@", nosync);
        }
        else
        {
            if ([[NSFileManager defaultManager] createDirectoryAtPath: nosync withIntermediateDirectories:NO attributes: nil error:&err])
            {
                DLog(@"no cloud sync directory created with path: %@", nosync);
            }
            else
            {
                // STOP HERE & LOG WITH INTERNAL PLUGIN ERROR:
                NSLog(@"INTERNAL PLUGIN ERROR: could not create no cloud sync directory at path: %@", nosync);
                return;
            }
        }

        {
            {
                // Set the resource value for NSURLIsExcludedFromBackupKey
                NSURL *nosyncURL = [ NSURL fileURLWithPath: nosync];
                if (![nosyncURL setResourceValue: [NSNumber numberWithBool: YES] forKey: NSURLIsExcludedFromBackupKey error: &err])
                {
                    // STOP HERE & LOG WITH INTERNAL PLUGIN ERROR:
                    NSLog(@"INTERNAL PLUGIN ERROR: error setting nobackup flag in LocalDatabase directory: %@", err);
                    return;
                }

                // now ready to add `nosync` entry to appDBPaths:
                DLog(@"no cloud sync at path: %@", nosync);
                [appDBPaths setObject: nosync forKey:@"nosync"];
            }
        }
    }
}

-(id) getDBPath:(NSString *)dbFile at:(NSString *)atkey {
    if (dbFile == NULL) {
        return NULL;
    }

    NSString *dbdir = [appDBPaths objectForKey:atkey];
    if (dbdir == NULL) {
        // INTERNAL PLUGIN ERROR:
        return NULL;
    }

    NSString *dbPath = [dbdir stringByAppendingPathComponent: dbFile];
    return dbPath;
}

-(void)echoStringValue: (CDVInvokedUrlCommand*)command
{
    CDVPluginResult * pluginResult = nil;
    NSMutableDictionary * options = [command.arguments objectAtIndex:0];

    NSString * string_value = [options objectForKey:@"value"];

    DLog(@"echo string value: %@", string_value);

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:string_value];
    [self.commandDelegate sendPluginResult:pluginResult callbackId: command.callbackId];
}

-(void)open: (CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        [self openNow: command];
    }];
}

-(void)openNow: (CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSMutableDictionary *options = [command.arguments objectAtIndex:0];

    NSString *dbfilename = [options objectForKey:@"name"];

    NSString *dblocation = [options objectForKey:@"dblocation"];
    if (dblocation == NULL) dblocation = @"docs";
    // DLog(@"using db location: %@", dblocation);

    NSString *dbname = [self getDBPath:dbfilename at:dblocation];

    if (!sqlite3_threadsafe()) {
        // INTERNAL PLUGIN ERROR:
        NSLog(@"INTERNAL PLUGIN ERROR: sqlite3_threadsafe() returns false value");
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"INTERNAL PLUGIN ERROR: sqlite3_threadsafe() returns false value"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId: command.callbackId];
        return;
    } else if (dbname == NULL) {
        // INTERNAL PLUGIN ERROR - NOT EXPECTED:
        NSLog(@"INTERNAL PLUGIN ERROR (NOT EXPECTED): open with database name missing");
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"INTERNAL PLUGIN ERROR: open with database name missing"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId: command.callbackId];
        return;
    } else {
        NSValue *dbPointer = [openDBs objectForKey:dbfilename];

        if (dbPointer != NULL) {
            // NO LONGER EXPECTED due to BUG 666 workaround solution:
            // DLog(@"Reusing existing database connection for db name %@", dbfilename);
            NSLog(@"INTERNAL PLUGIN ERROR: database already open for db name: %@ (db file name: %@)", dbname, dbfilename);
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"INTERNAL PLUGIN ERROR: database already open"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId: command.callbackId];
            return;
        }

        @synchronized(self) {
            const char *name = [dbname UTF8String];
            sqlite3 *db;

            DLog(@"open full db path: %@", dbname);

            if (sqlite3_open(name, &db) != SQLITE_OK) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Unable to open DB"];
                [self.commandDelegate sendPluginResult:pluginResult callbackId: command.callbackId];
                return;
            } else {
                // TBD IGNORE result:
                const char * err1;
                sqlite3_db_config(db, SQLITE_DBCONFIG_DEFENSIVE, 1, NULL);
                sqlite3_regexp_init(db, &err1);

                sqlite3_base64_init(db);

                sqlite3_eu_init(db, "UPPER", "LOWER");

                // for SQLCipher version:
                // NSString *dbkey = [options objectForKey:@"key"];
                // const char *key = NULL;
                // if (dbkey != NULL) key = [dbkey UTF8String];
                // if (key != NULL) sqlite3_key(db, key, strlen(key));

                // Attempt to read the SQLite master table [to support SQLCipher version]:
                if(sqlite3_exec(db, (const char*)"SELECT count(*) FROM sqlite_master;", NULL, NULL, NULL) == SQLITE_OK) {
                    dbPointer = [NSValue valueWithPointer:db];
                    [openDBs setObject: dbPointer forKey: dbfilename];
                    NSMutableDictionary * fjinfo = [NSMutableDictionary dictionaryWithCapacity:0];
                    [fjinfo setObject: [NSNumber numberWithInt:-1] forKey:@"dbid"];
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:fjinfo];
                } else {
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Unable to open DB with key"];
                    // XXX TODO: close the db handle & [perhaps] remove from openDBs!!
                }
            }
        }
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId: command.callbackId];

    // DLog(@"open cb finished ok");
}

-(void) close: (CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        [self closeNow: command];
    }];
}

-(void)closeNow: (CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSMutableDictionary *options = [command.arguments objectAtIndex:0];

    NSString *dbFileName = [options objectForKey:@"path"];

    if (dbFileName == NULL) {
        // Should not happen:
        DLog(@"No db name specified for close");
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"INTERNAL PLUGIN ERROR: You must specify database path"];
    } else {
        NSValue *val = [openDBs objectForKey:dbFileName];
        sqlite3 *db = [val pointerValue];

        if (db == NULL) {
            // Should not happen:
            DLog(@"close: db name was not open: %@", dbFileName);
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"INTERNAL PLUGIN ERROR: Specified db was not open"];
        }
        else {
            DLog(@"close db name: %@", dbFileName);
            sqlite3_close (db);
            [openDBs removeObjectForKey:dbFileName];
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"DB closed"];
        }
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId: command.callbackId];
}

-(void) delete: (CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        [self deleteNow: command];
    }];
}

-(void)deleteNow: (CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSMutableDictionary *options = [command.arguments objectAtIndex:0];

    NSString *dbFileName = [options objectForKey:@"path"];

    NSString *dblocation = [options objectForKey:@"dblocation"];
    if (dblocation == NULL) dblocation = @"docs";

    if (dbFileName==NULL) {
        // Should not happen:
        DLog(@"No db name specified for delete");
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"INTERNAL PLUGIN ERROR: You must specify database path"];
    } else {
        NSString *dbPath = [self getDBPath:dbFileName at:dblocation];

        if (dbPath == NULL) {
            // INTERNAL PLUGIN ERROR - NOT EXPECTED:
            NSLog(@"INTERNAL PLUGIN ERROR (NOT EXPECTED): delete with no valid database path found");
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: @"INTERNAL PLUGIN ERROR: delete with no valid database path found"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId: command.callbackId];
            return;
        }

        if ([[NSFileManager defaultManager]fileExistsAtPath:dbPath]) {
            DLog(@"delete full db path: %@", dbPath);
            [[NSFileManager defaultManager]removeItemAtPath:dbPath error:nil];
            [openDBs removeObjectForKey:dbFileName];
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"DB deleted"];
        } else {
            DLog(@"delete: db was not found: %@", dbPath);
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"The database does not exist on that path"];
        }
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


-(void) fj: (CDVInvokedUrlCommand*)command
{
    [self.commandDelegate runInBackground:^{
        [self fjnow: command];
    }];
}

-(void) fjnow: (CDVInvokedUrlCommand*)command
{
    NSMutableDictionary *options = [command.arguments objectAtIndex:0];
    NSMutableArray *results = [NSMutableArray arrayWithCapacity:0];
    NSMutableDictionary *dbargs = [options objectForKey:@"dbargs"];
    NSNumber *flen = [options objectForKey:@"flen"];
    NSMutableArray *flatlist = [options objectForKey:@"flatlist"];
    int sc = [flen integerValue];

    NSString *dbFileName = [dbargs objectForKey:@"dbname"];

    CDVPluginResult* pluginResult;

    // Skip flatlist items that are used by Android-sqlite-evcore-native-driver
    int ai = 2;

    @synchronized(self) {
        for (int i=0; i<sc; ++i) {
            NSString *sql = [flatlist objectAtIndex:(ai++)];
            NSNumber *pc = [flatlist objectAtIndex:(ai++)];
            int params_count = [pc integerValue];

            [self fjsql:sql withParams:flatlist first:ai count:params_count onDatabaseName:dbFileName results:results];
            ai += params_count;
        }

        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:results];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

-(void)fjsql: (NSString*)sql withParams: (NSMutableArray*)params first: (int)first count:(int)params_count onDatabaseName: (NSString*)dbFileName results: (NSMutableArray*)results
{
    NSValue *dbPointer = [openDBs objectForKey:dbFileName];

    sqlite3 *db = [dbPointer pointerValue];

    const char *sql_stmt = [sql UTF8String];
    NSDictionary *error = nil;
    sqlite3_stmt *statement;
    int result, i, column_type, count;
    int previousRowsAffected, nowRowsAffected, diffRowsAffected;
    long long nowInsertId;
    BOOL keepGoing = YES;
    BOOL hasInsertId;

    NSMutableArray *resultRows = [NSMutableArray arrayWithCapacity:0];
    NSMutableDictionary *entry;
    NSObject *columnValue;
    NSString *columnName;
    NSObject *insertId;
    NSObject *rowsAffected;

    hasInsertId = NO;
    previousRowsAffected = sqlite3_total_changes(db);

    if (sqlite3_prepare_v2(db, sql_stmt, -1, &statement, NULL) != SQLITE_OK) {
        error = [SQLitePlugin captureSQLiteErrorFromDb:db];
        keepGoing = NO;
    } else if (params != NULL) {
        for (int b = 0; b < params_count; b++) {
          // FUTURE TBD fix indentation:
          result =
            [self bindStatement:statement withArg:[params objectAtIndex:(first+b)] atIndex:(b+1)];
            if (result != SQLITE_OK) {
                error = [SQLitePlugin captureSQLiteErrorFromDb:db];
                keepGoing = NO;
                break;
            }
        }
    }

    BOOL hasRows = NO;

    while (keepGoing) {
        result = sqlite3_step (statement);
        switch (result) {

            case SQLITE_ROW:
                if (!hasRows) [results addObject:@"okrows"];
                hasRows = YES;
                i = 0;
                entry = [NSMutableDictionary dictionaryWithCapacity:0];
                count = sqlite3_column_count(statement);

                [results addObject:[NSNumber numberWithInt:count]];

                while (i < count) {
                    columnValue = nil;
                    columnName = [NSString stringWithFormat:@"%s", sqlite3_column_name(statement, i)];

                    [results addObject:columnName];

                    column_type = sqlite3_column_type(statement, i);
                    switch (column_type) {
#if 0 // XXX SQLITE_NULL is now last
                        case SQLITE_NULL:
                            columnValue = [NSNull null];
                            break;
#endif
                        case SQLITE_INTEGER:
                            columnValue = [NSNumber numberWithLongLong: sqlite3_column_int64(statement, i)];
                            break;
                        case SQLITE_FLOAT:
                            columnValue = [NSNumber numberWithDouble: sqlite3_column_double(statement, i)];
                            break;
                        // Handles both TEXT & BLOB:
                        case SQLITE_BLOB:
                        case SQLITE_TEXT:
                            columnValue = [[NSString alloc] initWithBytes:(char *)sqlite3_column_text(statement, i)
                                                                   length:sqlite3_column_bytes(statement, i)
                                                                 encoding:NSUTF8StringEncoding];
                            break;
                        case SQLITE_NULL:
                        // just in case (should not happen):
                        default:
                            columnValue = [NSNull null];
                            break;
                    }

                    [results addObject:columnValue];

                    i++;
                }
                [resultRows addObject:entry];
                break;

            case SQLITE_DONE:
                if (hasRows) [results addObject:@"endrows"];
                nowRowsAffected = sqlite3_total_changes(db);
                diffRowsAffected = nowRowsAffected - previousRowsAffected;
                rowsAffected = [NSNumber numberWithInt:diffRowsAffected];
                nowInsertId = sqlite3_last_insert_rowid(db);
                if (diffRowsAffected > 0 && nowInsertId != 0) {
                    hasInsertId = YES;
                    insertId = [NSNumber numberWithLongLong:nowInsertId];
                }
                else insertId = [NSNumber numberWithLongLong:-1];
                keepGoing = NO;
                break;

            default:
                error = [SQLitePlugin captureSQLiteErrorFromDb:db];
                keepGoing = NO;
        }
    }

    sqlite3_finalize (statement);

    if (error) {
        /* add error with result.message: */

        // XXX FUTURE TBD: include full error object instead (??)
        [results addObject:@"error"];
        [results addObject:[error objectForKey:@"code"]];
        [results addObject:@"extra"]; // ignored (for now)
        [results addObject:[error objectForKey:@"message"]];

        return;
    }

    if (!hasRows) {
        if (diffRowsAffected > 0) {
            [results addObject:@"ch2"];
            [results addObject:rowsAffected];
            [results addObject:insertId];
        } else {
            [results addObject:@"ok"];
        }
    }
}

-(int)bindStatement:(sqlite3_stmt *)statement withArg:(NSObject *)arg atIndex:(int)argIndex
{
    int bindResult = SQLITE_ERROR;

    if ([arg isEqual:[NSNull null]]) {
        // bind null:
        bindResult = sqlite3_bind_null(statement, argIndex);
    } else if ([arg isKindOfClass:[NSNumber class]]) {
        // bind NSNumber (int64 or double):
        NSNumber *numberArg = (NSNumber *)arg;
        const char *numberType = [numberArg objCType];

        // Bind each number as INTEGER (long long int) or REAL (double):
        if (strcmp(numberType, @encode(int)) == 0 ||
            strcmp(numberType, @encode(long long int)) == 0) {
            bindResult = sqlite3_bind_int64(statement, argIndex, [numberArg longLongValue]);
        } else {
            bindResult = sqlite3_bind_double(statement, argIndex, [numberArg doubleValue]);
        }
    } else {
        // bind NSString (text):
        NSString *stringArg;

        if ([arg isKindOfClass:[NSString class]]) {
            stringArg = (NSString *)arg;
        } else {
            stringArg = [arg description]; // convert to text
        }

        // always bind text string as UTF-8 (sqlite does internal conversion if necessary):
        NSData *data = [stringArg dataUsingEncoding:NSUTF8StringEncoding];
        bindResult = sqlite3_bind_text(statement, argIndex, data.bytes, (int)data.length, SQLITE_TRANSIENT);
    }

    return bindResult;
}

-(void)dealloc
{
    int i;
    NSArray *keys = [openDBs allKeys];
    NSValue *pointer;
    NSString *key;
    sqlite3 *db;

    /* close db the user forgot */
    for (i=0; i<[keys count]; i++) {
        key = [keys objectAtIndex:i];
        pointer = [openDBs objectForKey:key];
        db = [pointer pointerValue];
        sqlite3_close (db);
    }
}

+(NSDictionary *)captureSQLiteErrorFromDb:(struct sqlite3 *)db
{
    int code = sqlite3_errcode(db);
    int webSQLCode = [SQLitePlugin mapSQLiteErrorCode:code];
#if INCLUDE_SQLITE_ERROR_INFO
    int extendedCode = sqlite3_extended_errcode(db);
#endif
    const char *message = sqlite3_errmsg(db);

    NSMutableDictionary *error = [NSMutableDictionary dictionaryWithCapacity:4];

    [error setObject:[NSNumber numberWithInt:webSQLCode] forKey:@"code"];
    [error setObject:[NSString stringWithUTF8String:message] forKey:@"message"];

#if INCLUDE_SQLITE_ERROR_INFO
    [error setObject:[NSNumber numberWithInt:code] forKey:@"sqliteCode"];
    [error setObject:[NSNumber numberWithInt:extendedCode] forKey:@"sqliteExtendedCode"];
    [error setObject:[NSString stringWithUTF8String:message] forKey:@"sqliteMessage"];
#endif

    return error;
}

+(int)mapSQLiteErrorCode:(int)code
{
    // map the sqlite error code to
    // the websql error code
    switch(code) {
        case SQLITE_ERROR:
            return SYNTAX_ERR_;
        case SQLITE_FULL:
            return QUOTA_ERR;
        case SQLITE_CONSTRAINT:
            return CONSTRAINT_ERR;
        default:
            return UNKNOWN_ERR;
    }
}

@end /* vim: set expandtab : */
