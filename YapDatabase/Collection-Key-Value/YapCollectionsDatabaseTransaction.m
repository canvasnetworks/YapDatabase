#import "YapCollectionsDatabaseTransaction.h"
#import "YapCollectionsDatabasePrivate.h"
#import "YapAbstractDatabaseExtensionPrivate.h"
#import "YapDatabaseString.h"
#import "YapDatabaseLogging.h"
#import "YapCache.h"
#import "YapCollectionKey.h"
#import "YapTouch.h"
#import "YapNull.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_INFO;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapCollectionsDatabaseReadTransaction {
	
/* From YapAbstractDatabasePrivate.h & YapCollectionsDatabasePrivate.h:
 
@protected
	BOOL isMutated; // Used for "mutation during enumeration" protection

@public
	BOOL isReadWriteTransaction;
	__unsafe_unretained YapCollectionsDatabaseConnection *connection;

*/
}

- (id)initWithConnection:(YapAbstractDatabaseConnection *)aConnection isReadWriteTransaction:(BOOL)flag
{
	if ((self = [super initWithConnection:aConnection isReadWriteTransaction:flag]))
	{
		connection = (YapCollectionsDatabaseConnection *)aConnection;
	}
	return self;
}

@synthesize connection = connection;

#pragma mark Count

- (NSUInteger)numberOfCollections
{
	sqlite3_stmt *statement = [connection getCollectionCountStatement];
	if (statement == NULL) return 0;
	
	// SELECT COUNT(DISTINCT collection) AS NumberOfRows FROM "database2";
	
	NSUInteger result = 0;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		result = (NSUInteger)sqlite3_column_int64(statement, 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getCollectionCountStatement': %d %s",
		            status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_reset(statement);
	
	return result;
}

- (NSUInteger)numberOfKeysInCollection:(NSString *)collection
{
	if (collection == nil) collection = @"";
	
	sqlite3_stmt *statement = [connection getKeyCountForCollectionStatement];
	if (statement == NULL) return 0;
	
	// SELECT COUNT(*) AS NumberOfRows FROM "database2" WHERE "collection" = ?;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	
	NSUInteger result = 0;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		result = (NSUInteger)sqlite3_column_int64(statement, 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getKeyCountForCollectionStatement': %d %s",
		            status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	
	return result;
}

- (NSUInteger)numberOfKeysInAllCollections
{
	sqlite3_stmt *statement = [connection getKeyCountForAllStatement];
	if (statement == NULL) return 0;
	
	// SELECT COUNT(*) AS NumberOfRows FROM "database2";
	
	NSUInteger result = 0;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		result = (NSUInteger)sqlite3_column_int64(statement, 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getKeyCountForAllStatement': %d %s",
		            status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_reset(statement);
	
	return result;
}

#pragma mark List

- (NSArray *)allCollections
{
	sqlite3_stmt *statement = [connection enumerateCollectionsStatement];
	if (statement == NULL) return nil;
	
	// SELECT DISTINCT "collection" FROM "database2";";
	
	NSMutableArray *result = [NSMutableArray array];
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		do
		{
			const unsigned char *text = sqlite3_column_text(statement, 0);
			int textSize = sqlite3_column_bytes(statement, 0);
			
			NSString *collection = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			[result addObject:collection];
			
		} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
	}
	
	sqlite3_reset(statement);
	
	return result;
}

- (NSArray *)allKeysInCollection:(NSString *)collection
{
	NSUInteger count = [self numberOfKeysInCollection:collection];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];
	
	[self _enumerateKeysInCollection:collection usingBlock:^(int64_t rowid, NSString *key, BOOL *stop) {
		
		[result addObject:key];
	}];
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal (using rowid)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)getRowid:(int64_t *)rowidPtr forKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) {
		if (rowidPtr) *rowidPtr = 0;
		return NO;
	}
	if (collection == nil) collection = @"";
	
	sqlite3_stmt *statement = [connection getRowidForKeyStatement];
	if (statement == NULL) {
		if (rowidPtr) *rowidPtr = 0;
		return NO;
	}
	
	// SELECT "rowid" FROM "database2" WHERE "collection" = ? AND "key" = ?;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length,  SQLITE_STATIC);
	
	int64_t rowid = 0;
	BOOL result = NO;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		rowid = sqlite3_column_int64(statement, 0);
		result = YES;
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getRowidForKeyStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	FreeYapDatabaseString(&_key);
	
	if (rowidPtr) *rowidPtr = rowid;
	return result;
}

- (BOOL)getKey:(NSString **)keyPtr collection:(NSString **)collectionPtr forRowid:(int64_t)rowid
{
	sqlite3_stmt *statement = [connection getKeyForRowidStatement];
	if (statement == NULL) {
		if (keyPtr) *keyPtr = nil;
		if (collectionPtr) *collectionPtr = nil;
		return NO;
	}
	
	// SELECT "collection", "key" FROM "database2" WHERE "rowid" = ?;
	
	sqlite3_bind_int64(statement, 1, rowid);
	
	NSString *collection = nil;
	NSString *key = nil;
	BOOL result = NO;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		const unsigned char *text0 = sqlite3_column_text(statement, 0);
		int textSize0 = sqlite3_column_bytes(statement, 0);
		
		const unsigned char *text1 = sqlite3_column_text(statement, 1);
		int textSize1 = sqlite3_column_bytes(statement, 1);
		
		collection = [[NSString alloc] initWithBytes:text0 length:textSize0 encoding:NSUTF8StringEncoding];
		key        = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
		
		result = YES;
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getKeyForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (keyPtr) *keyPtr = key;
	if (collectionPtr) *collectionPtr = collection;
	return result;
}

- (BOOL)getKey:(NSString **)keyPtr
    collection:(NSString **)collectionPtr
        object:(id *)objectPtr
      forRowid:(int64_t)rowid
{
	sqlite3_stmt *statement = [connection getDataForRowidStatement];
	if (statement == NULL) {
		if (keyPtr) *keyPtr = nil;
		if (collectionPtr) *collectionPtr = nil;
		if (objectPtr) *objectPtr = nil;
		return NO;
	}
	
	// SELECT "collection", "key", "data" FROM "database2" WHERE "rowid" = ?;
	
	sqlite3_bind_int64(statement, 1, rowid);
	
	NSString *collection = nil;
	NSString *key = nil;
	id object = nil;
	BOOL result = NO;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		const unsigned char *text0 = sqlite3_column_text(statement, 0);
		int textSize0 = sqlite3_column_bytes(statement, 0);
		
		const unsigned char *text1 = sqlite3_column_text(statement, 1);
		int textSize1 = sqlite3_column_bytes(statement, 1);
		
		collection = [[NSString alloc] initWithBytes:text0 length:textSize0 encoding:NSUTF8StringEncoding];
		key        = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
		
		YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		object = [connection->objectCache objectForKey:cacheKey];
		if (object == nil)
		{
			const void *blob = sqlite3_column_blob(statement, 2);
			int blobSize = sqlite3_column_bytes(statement, 2);
			
			// Performance tuning:
			// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
			
			NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			object = connection->database->objectDeserializer(collection, key, data);
			
			if (object)
				[connection->objectCache setObject:object forKey:cacheKey];
		}
		
		result = YES;
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getDataForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (keyPtr) *keyPtr = key;
	if (collectionPtr) *collectionPtr = collection;
	if (objectPtr) *objectPtr = object;
	return result;
}

- (BOOL)getKey:(NSString **)keyPtr
    collection:(NSString **)collectionPtr
      metadata:(id *)metadataPtr
      forRowid:(int64_t)rowid
{
	sqlite3_stmt *statement = [connection getMetadataForRowidStatement];
	if (statement == NULL) {
		if (keyPtr) *keyPtr = nil;
		if (collectionPtr) *collectionPtr = nil;
		if (metadataPtr) *metadataPtr = nil;
		return NO;
	}
	
	// SELECT "collection", "key", "metadata" FROM "database2" WHERE "rowid" = ?;
	
	sqlite3_bind_int64(statement, 1, rowid);
	
	NSString *collection = nil;
	NSString *key = nil;
	id metadata = nil;
	BOOL result = NO;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		const unsigned char *text0 = sqlite3_column_text(statement, 0);
		int textSize0 = sqlite3_column_bytes(statement, 0);
		
		const unsigned char *text1 = sqlite3_column_text(statement, 1);
		int textSize1 = sqlite3_column_bytes(statement, 1);
		
		collection = [[NSString alloc] initWithBytes:text0 length:textSize0 encoding:NSUTF8StringEncoding];
		key        = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
		
		YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		metadata = [connection->metadataCache objectForKey:cacheKey];
		if (metadata)
		{
			if (metadata == [YapNull null])
				metadata = nil;
		}
		else
		{
			const void *blob = sqlite3_column_blob(statement, 2);
			int blobSize = sqlite3_column_bytes(statement, 2);
			
			if (blobSize > 0)
			{
				// Performance tuning:
				// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
				
				NSData *mData = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
				metadata = connection->database->metadataDeserializer(collection, key, mData);
			}
			
			if (metadata)
				[connection->metadataCache setObject:metadata forKey:cacheKey];
			else
				[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
		}
		
		result = YES;
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getMetadataForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (keyPtr) *keyPtr = key;
	if (collectionPtr) *collectionPtr = collection;
	if (metadataPtr) *metadataPtr = metadata;
	return result;
}

- (BOOL)getKey:(NSString **)keyPtr
    collection:(NSString **)collectionPtr
        object:(id *)objectPtr
      metadata:(id *)metadataPtr
      forRowid:(int64_t)rowid
{
	sqlite3_stmt *statement = [connection getAllForRowidStatement];
	if (statement == NULL) {
		if (keyPtr) *keyPtr = nil;
		if (collectionPtr) *collectionPtr = nil;
		if (objectPtr) *objectPtr = nil;
		if (metadataPtr) *metadataPtr = nil;
		return NO;
	}
	
	// SELECT "collection", "key", "data", "metadata" FROM "database2" WHERE "rowid" = ?;
	
	sqlite3_bind_int64(statement, 1, rowid);
	
	NSString *collection = nil;
	NSString *key = nil;
	id object = nil;
	id metadata = nil;
	BOOL result = NO;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		const unsigned char *text0 = sqlite3_column_text(statement, 0);
		int textSize0 = sqlite3_column_bytes(statement, 0);
		
		const unsigned char *text1 = sqlite3_column_text(statement, 1);
		int textSize1 = sqlite3_column_bytes(statement, 1);
		
		collection = [[NSString alloc] initWithBytes:text0 length:textSize0 encoding:NSUTF8StringEncoding];
		key        = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
		
		YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		object = [connection->objectCache objectForKey:cacheKey];
		if (object == nil)
		{
			const void *blob = sqlite3_column_blob(statement, 2);
			int blobSize = sqlite3_column_bytes(statement, 2);
			
			// Performance tuning:
			// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
			
			NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
			object = connection->database->objectDeserializer(collection, key, data);
			
			if (object)
				[connection->objectCache setObject:object forKey:cacheKey];
		}
		
		metadata = [connection->metadataCache objectForKey:cacheKey];
		if (metadata)
		{
			if (metadata == [YapNull null])
				metadata = nil;
		}
		else
		{
			const void *blob = sqlite3_column_blob(statement, 3);
			int blobSize = sqlite3_column_bytes(statement, 3);
			
			if (blobSize > 0)
			{
				// Performance tuning:
				// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
				
				NSData *mData = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
				metadata = connection->database->metadataDeserializer(collection, key, mData);
			}
			
			if (metadata)
				[connection->metadataCache setObject:metadata forKey:cacheKey];
			else
				[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
		}
		
		result = YES;
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getKeyForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (keyPtr) *keyPtr = key;
	if (collectionPtr) *collectionPtr = collection;
	if (objectPtr) *objectPtr = object;
	if (metadataPtr) *metadataPtr = metadata;
	return result;
}

- (BOOL)hasRowForRowid:(int64_t)rowid
{
	sqlite3_stmt *statement = [connection getCountForRowidStatement];
	if (statement == NULL) return NO;
	
	// SELECT COUNT(*) AS NumberOfRows FROM "database2" WHERE "rowid" = ?;
	
	sqlite3_bind_int64(statement, 1, rowid);
	
	BOOL result = NO;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		result = (sqlite3_column_int64(statement, 0) > 0);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getCountForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Primitive
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSData *)primitiveDataForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return nil;
	if (collection == nil) collection = @"";
	
	sqlite3_stmt *statement = [connection getDataForKeyStatement];
	if (statement == NULL) return nil;
	
	NSData *result = nil;
	
	// SELECT "data" FROM "database2" WHERE "collection" = ? AND "key" = ?;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length,  SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		result = [[NSData alloc] initWithBytes:blob length:blobSize];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getDataForKeyStatement': %d %s, key(%@)",
		                                                    status, sqlite3_errmsg(connection->db), key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	FreeYapDatabaseString(&_key);

	return result;
}

- (NSData *)primitiveMetadataForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return nil;
	if (collection == nil) collection = @"";
	
	sqlite3_stmt *statement = [connection getMetadataForKeyStatement];
	if (statement == NULL) return nil;
	
	// SELECT "metadata" FROM "database2" WHERE "collection" = ? AND "key" = ? ;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	NSData *result = nil;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		result = [[NSData alloc] initWithBytes:blob length:blobSize];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getDataForKeyStatement': %d %s, key(%@)",
					status, sqlite3_errmsg(connection->db), key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	FreeYapDatabaseString(&_key);
	
	return result;
}

- (BOOL)getPrimitiveData:(NSData **)dataPtr
       primitiveMetadata:(NSData **)metadataPtr
                  forKey:(NSString *)key
            inCollection:(NSString *)collection
{
	if (key == nil) {
		if (dataPtr) *dataPtr = nil;
		if (metadataPtr) *metadataPtr = nil;
		return NO;
	}
	if (collection == nil) collection = @"";
		
	sqlite3_stmt *statement = [connection getAllForKeyStatement];
	if (statement == NULL) {
		if (dataPtr) *dataPtr = nil;
		if (metadataPtr) *metadataPtr = nil;
		return NO;
	}
	
	NSData *data = nil;
	NSData *metadata = nil;
	
	BOOL found = NO;
	
	// SELECT "data", "metadata" FROM "database2" WHERE "collection" = ? AND "key" = ? ;
		
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
		
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
		
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		const void *oBlob = sqlite3_column_blob(statement, 0);
		int oBlobSize = sqlite3_column_bytes(statement, 0);
		
		const void *mBlob = sqlite3_column_blob(statement, 1);
		int mBlobSize = sqlite3_column_bytes(statement, 1);
		
		if (dataPtr)
		{
			data = [NSData dataWithBytes:(void *)oBlob length:oBlobSize];
		}
		
		if (metadataPtr)
		{
			metadata = [NSData dataWithBytes:(void *)mBlob length:mBlobSize];
		}
		
		found = YES;
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getAllForKeyStatement': %d %s",
		                                                   status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	FreeYapDatabaseString(&_key);
	
	if (dataPtr) *dataPtr = data;
	if (metadataPtr) *metadataPtr = metadata;
	
	return found;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Object & Metadata
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)objectForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return nil;
	if (collection == nil) collection = @"";
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	id object = [connection->objectCache objectForKey:cacheKey];
	if (object)
		return object;
	
	sqlite3_stmt *statement = [connection getDataForKeyStatement];
	if (statement == NULL) return nil;
	
	// SELECT "data" FROM "database2" WHERE "collection" = ? AND "key" = ?;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		// Performance tuning:
		// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
		// Be sure not to call sqlite3_reset until we're done with the data.
		
		NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
		object = connection->database->objectDeserializer(collection, key, data);
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getDataForKeyStatement': %d %s, key(%@)",
		                                                    status, sqlite3_errmsg(connection->db), key);
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	FreeYapDatabaseString(&_key);
	
	if (object)
		[connection->objectCache setObject:object forKey:cacheKey];
	
	return object;
}

- (BOOL)hasObjectForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return NO;
	if (collection == nil) collection = @"";
	
	// Shortcut:
	// We may not need to query the database if we have the key in any of our caches.
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	if ([connection->metadataCache objectForKey:cacheKey]) return YES;
	if ([connection->objectCache objectForKey:cacheKey]) return YES;
	
	// The normal SQL way
	
	return [self getRowid:NULL forKey:key inCollection:collection];
}

- (BOOL)getObject:(id *)objectPtr metadata:(id *)metadataPtr forKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil)
	{
		if (objectPtr) *objectPtr = nil;
		if (metadataPtr) *metadataPtr = nil;
		
		return NO;
	}
	if (collection == nil) collection = @"";
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	id object = [connection->objectCache objectForKey:cacheKey];
	id metadata = [connection->metadataCache objectForKey:cacheKey];
	
	BOOL found = NO;
	
	if (object && metadata)
	{
		// Both object and metadata were in cache.
		found = YES;
		
		// Need to check for empty metadata placeholder from cache.
		if (metadata == [YapNull null])
			metadata = nil;
	}
	else if (!object && metadata)
	{
		// Metadata was in cache.
		found = YES;
		
		// Need to check for empty metadata placeholder from cache.
		if (metadata == [YapNull null])
			metadata = nil;
		
		// Missing object. Fetch individually if requested.
		if (objectPtr)
			object = [self objectForKey:key inCollection:collection];
	}
	else if (object && !metadata)
	{
		// Object was in cache.
		found = YES;
		
		// Missing metadata. Fetch individually if requested.
		if (metadataPtr)
			metadata = [self metadataForKey:key inCollection:collection];
	}
	else // (!object && !metadata)
	{
		// Both object and metadata are missing.
		// Fetch via query.
		
		sqlite3_stmt *statement = [connection getAllForKeyStatement];
		if (statement)
		{
			// SELECT "data", "metadata" FROM "database2" WHERE "collection" = ? AND "key" = ? ;
			
			YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
			sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
			
			YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
			sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
			
			int status = sqlite3_step(statement);
			if (status == SQLITE_ROW)
			{
				if (connection->needsMarkSqlLevelSharedReadLock)
					[connection markSqlLevelSharedReadLockAcquired];
				
				const void *oBlob = sqlite3_column_blob(statement, 0);
				int oBlobSize = sqlite3_column_bytes(statement, 0);
				
				const void *mBlob = sqlite3_column_blob(statement, 1);
				int mBlobSize = sqlite3_column_bytes(statement, 1);
				
				if (objectPtr)
				{
					NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
					object = connection->database->objectDeserializer(collection, key, oData);
				}
				
				if (metadataPtr && mBlobSize > 0)
				{
					NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
					metadata = connection->database->metadataDeserializer(collection, key, mData);
				}
				
				found = YES;
			}
			else if (status == SQLITE_ERROR)
			{
				YDBLogError(@"Error executing 'getAllForKeyStatement': %d %s",
				                                                   status, sqlite3_errmsg(connection->db));
			}
			
			if (object)
			{
				[connection->objectCache setObject:object forKey:cacheKey];
				
				if (metadata)
					[connection->metadataCache setObject:metadata forKey:cacheKey];
				else
					[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
			}
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
			FreeYapDatabaseString(&_collection);
			FreeYapDatabaseString(&_key);
		}
	}
	
	if (objectPtr) *objectPtr = object;
	if (metadataPtr) *metadataPtr = metadata;
	
	return found;
}

- (id)metadataForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (key == nil) return nil;
	if (collection == nil) collection = @"";
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	id metadata = [connection->metadataCache objectForKey:cacheKey];
	if (metadata)
	{
		if (metadata == [YapNull null])
			return nil;
		else
			return metadata;
	}
	
	sqlite3_stmt *statement = [connection getMetadataForKeyStatement];
	if (statement == NULL) return nil;
	
	// SELECT "metadata" FROM "database2" WHERE "collection" = ? AND "key" = ? ;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
	
	BOOL found = NO;
	NSData *metadataData = nil;
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		found = YES;
		
		const void *blob = sqlite3_column_blob(statement, 0);
		int blobSize = sqlite3_column_bytes(statement, 0);
		
		// Performance tuning:
		//
		// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
		// But be sure not to call sqlite3_reset until we're done with the data.
		
		if (blobSize > 0)
			metadataData = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
	}
	else if (status == SQLITE_ERROR)
	{
		YDBLogError(@"Error executing 'getMetadataForKeyStatement': %d %s",
		                                                        status, sqlite3_errmsg(connection->db));
	}
	
	if (found)
	{
		if (metadataData)
			metadata = connection->database->metadataDeserializer(collection, key, metadataData);
		
		if (metadata)
			[connection->metadataCache setObject:metadata forKey:cacheKey];
		else
			[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	FreeYapDatabaseString(&_key);
	
	return metadata;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Enumerate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Fast enumeration over all the collections in the database.
 * 
 * This uses a "SELECT collection FROM database" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)enumerateCollectionsUsingBlock:(void (^)(NSString *collection, BOOL *stop))block
{
	if (block == NULL) return;
	
	sqlite3_stmt *statement = [connection enumerateCollectionsStatement];
	if (statement == NULL) return;
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT DISTINCT "collection" FROM "database2";
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		do
		{
			const unsigned char *text = sqlite3_column_text(statement, 0);
			int textSize = sqlite3_column_bytes(statement, 0);
			
			NSString *collection = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			block(collection, &stop);
			
			if (stop || isMutated) break;
			
		} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
	}
	
	if ((status != SQLITE_DONE) && !stop && !isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_reset(statement);
	
	if (isMutated && !stop)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * This method is rarely needed, but may be helpful in certain situations.
 * 
 * This method may be used if you have the key, but not the collection for a particular item.
 * Please note that this is not the ideal situation.
 * 
 * Since there may be numerous collections for a given key, this method enumerates all possible collections.
**/
- (void)enumerateCollectionsForKey:(NSString *)key usingBlock:(void (^)(NSString *collection, BOOL *stop))block
{
	if (key == nil) return;
	if (block == NULL) return;
	
	sqlite3_stmt *statement = [connection enumerateCollectionsForKeyStatement];
	if (statement == NULL) return;
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "collection" FROM "database2" WHERE "key" = ?;
	
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	sqlite3_bind_text(statement, 1, _key.str, _key.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		do
		{
			const unsigned char *text = sqlite3_column_text(statement, 0);
			int textSize = sqlite3_column_bytes(statement, 0);
			
			NSString *collection = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			block(collection, &stop);
			
			if (stop || isMutated) break;
			
		} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
	}
	
	if ((status != SQLITE_DONE) && !stop && !isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_key);
	
	if (isMutated && !stop)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * Fast enumeration over all keys in the given collection.
 *
 * This uses a "SELECT key FROM database WHERE collection = ?" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)enumerateKeysInCollection:(NSString *)collection
                       usingBlock:(void (^)(NSString *key, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self _enumerateKeysInCollection:collection usingBlock:^(int64_t rowid, NSString *key, BOOL *stop) {
		
		block(key, stop);
	}];
}

/**
 * Fast enumeration over all keys in the given collection.
 *
 * This uses a "SELECT collection, key FROM database" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)enumerateKeysInAllCollectionsUsingBlock:(void (^)(NSString *collection, NSString *key, BOOL *stop))block
{
	if (block == NULL) return;
	
	[self _enumerateKeysInAllCollectionsUsingBlock:^(int64_t rowid, NSString *collection, NSString *key, BOOL *stop) {
		
		block(collection, key, stop);
	}];
}

/**
 * Fast enumeration over all keys and associated metadata in the given collection.
 * 
 * This uses a "SELECT key, metadata FROM database WHERE collection = ?" operation and steps over the results.
 * 
 * If you only need to enumerate over certain items (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the deserialization step for those items you're not interested in.
 * 
 * Keep in mind that you cannot modify the collection mid-enumeration (just like any other kind of enumeration).
**/
- (void)enumerateKeysAndMetadataInCollection:(NSString *)collection
                                  usingBlock:(void (^)(NSString *key, id metadata, BOOL *stop))block
{
	[self enumerateKeysAndMetadataInCollection:collection usingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over all keys and associated metadata in the given collection.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
 * 
 * Keep in mind that you cannot modify the collection mid-enumeration (just like any other kind of enumeration).
**/
- (void)enumerateKeysAndMetadataInCollection:(NSString *)collection
                                  usingBlock:(void (^)(NSString *key, id metadata, BOOL *stop))block
                                  withFilter:(BOOL (^)(NSString *key))filter
{
	if (block == NULL) return;
	
	if (filter)
	{
		[self _enumerateKeysAndMetadataInCollection:collection
		                                 usingBlock:^(int64_t rowid, NSString *key, id metadata, BOOL *stop) {
		
			block(key, metadata, stop);
			
		} withFilter:^BOOL(int64_t rowid, NSString *key) {
			
			return filter(key);
		}];
	}
	else
	{
		[self _enumerateKeysAndMetadataInCollection:collection
		                                 usingBlock:^(int64_t rowid, NSString *key, id metadata, BOOL *stop) {
		
			block(key, metadata, stop);
			
		} withFilter:NULL];
	}
}

/**
 * Fast enumeration over all key/metadata pairs in all collections.
 * 
 * This uses a "SELECT metadata FROM database ORDER BY collection ASC" operation, and steps over the results.
 * 
 * If you only need to enumerate over certain objects (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the deserialization step for those objects you're not interested in.
 * 
 * Keep in mind that you cannot modify the database mid-enumeration (just like any other kind of enumeration).
**/
- (void)enumerateKeysAndMetadataInAllCollectionsUsingBlock:
                                        (void (^)(NSString *collection, NSString *key, id metadata, BOOL *stop))block
{
	[self enumerateKeysAndMetadataInAllCollectionsUsingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over all key/metadata pairs in all collections.
 *
 * This uses a "SELECT metadata FROM database ORDER BY collection ASC" operation and steps over the results.
 * 
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
 *
 * Keep in mind that you cannot modify the database mid-enumeration (just like any other kind of enumeration).
 **/
- (void)enumerateKeysAndMetadataInAllCollectionsUsingBlock:
                                        (void (^)(NSString *collection, NSString *key, id metadata, BOOL *stop))block
                             withFilter:(BOOL (^)(NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	
	if (filter)
	{
		[self _enumerateKeysAndMetadataInAllCollectionsUsingBlock:
		    ^(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop) {
			
			block(collection, key, metadata, stop);
			
		} withFilter:^BOOL(int64_t rowid, NSString *collection, NSString *key) {
			
			return filter(collection, key);
		}];
	}
	else
	{
		[self _enumerateKeysAndMetadataInAllCollectionsUsingBlock:
		    ^(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop) {
			
			block(collection, key, metadata, stop);
			
		} withFilter:NULL];
	}
}

/**
 * Fast enumeration over all objects in the database.
 *
 * This uses a "SELECT key, object from database WHERE collection = ?" operation, and then steps over the results,
 * deserializing each object, and then invoking the given block handler.
 *
 * If you only need to enumerate over certain objects (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those objects you're not interested in.
**/
- (void)enumerateKeysAndObjectsInCollection:(NSString *)collection
                                 usingBlock:(void (^)(NSString *key, id object, BOOL *stop))block
{
	[self enumerateKeysAndObjectsInCollection:collection usingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over objects in the database for which you're interested in.
 * The filter block allows you to decide which objects you're interested in.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
**/
- (void)enumerateKeysAndObjectsInCollection:(NSString *)collection
                                 usingBlock:(void (^)(NSString *key, id object, BOOL *stop))block
                                 withFilter:(BOOL (^)(NSString *key))filter
{
	if (block == NULL) return;
	
	if (filter)
	{
		[self _enumerateKeysAndObjectsInCollection:collection
		                                usingBlock:^(int64_t rowid, NSString *key, id object, BOOL *stop) {
			
			block(key, object, stop);
			
		} withFilter:^BOOL(int64_t rowid, NSString *key) {
			
			return filter(key);
		}];
	}
	else
	{
		[self _enumerateKeysAndObjectsInCollection:collection
		                                usingBlock:^(int64_t rowid, NSString *key, id object, BOOL *stop) {
			
			block(key, object, stop);
			
		} withFilter:NULL];
	}
}

/**
 * Enumerates all key/object pairs in all collections.
 *
 * The enumeration is sorted by collection. That is, it will enumerate fully over a single collection
 * before moving onto another collection.
 *
 * If you only need to enumerate over certain objects (e.g. subset of collections, or keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those objects you're not interested in.
**/
- (void)enumerateKeysAndObjectsInAllCollectionsUsingBlock:
                            (void (^)(NSString *collection, NSString *key, id object, BOOL *stop))block
{
	[self enumerateKeysAndObjectsInAllCollectionsUsingBlock:block withFilter:NULL];
}

/**
 * Enumerates all key/object pairs in all collections.
 * The filter block allows you to decide which objects you're interested in.
 *
 * The enumeration is sorted by collection. That is, it will enumerate fully over a single collection
 * before moving onto another collection.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given
 * collection/key pair. If the filter block returns NO, then the block handler is skipped for the given pair,
 * which avoids the cost associated with deserializing the object.
**/
- (void)enumerateKeysAndObjectsInAllCollectionsUsingBlock:
                            (void (^)(NSString *collection, NSString *key, id object, BOOL *stop))block
                 withFilter:(BOOL (^)(NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	
	if (filter)
	{
		[self _enumerateKeysAndObjectsInAllCollectionsUsingBlock:
		    ^(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop) {
			
			block(collection, key, object, stop);
			
		} withFilter:^BOOL(int64_t rowid, NSString *collection, NSString *key) {
			
			return filter(collection, key);
		}];
	}
	else
	{
		[self _enumerateKeysAndObjectsInAllCollectionsUsingBlock:
		    ^(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop) {
			
			block(collection, key, object, stop);
			
		} withFilter:NULL];
	}
}

/**
 * Fast enumeration over all rows in the database.
 *
 * This uses a "SELECT key, data, metadata from database WHERE collection = ?" operation,
 * and then steps over the results, deserializing each object & metadata, and then invoking the given block handler.
 *
 * If you only need to enumerate over certain rows (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those rows you're not interested in.
**/
- (void)enumerateRowsInCollection:(NSString *)collection
                       usingBlock:(void (^)(NSString *key, id object, id metadata, BOOL *stop))block
{
	[self enumerateRowsInCollection:collection usingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over rows in the database for which you're interested in.
 * The filter block allows you to decide which rows you're interested in.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object & metadata.
**/
- (void)enumerateRowsInCollection:(NSString *)collection
                       usingBlock:(void (^)(NSString *key, id object, id metadata, BOOL *stop))block
                       withFilter:(BOOL (^)(NSString *key))filter
{
	if (block == NULL) return;
	
	if (filter)
	{
		[self _enumerateRowsInCollection:collection
		                      usingBlock:^(int64_t rowid, NSString *key, id object, id metadata, BOOL *stop) {
			
			block(key, object, metadata, stop);
			
		} withFilter:^BOOL(int64_t rowid, NSString *key) {
			
			return filter(key);
		}];
	}
	else
	{
		[self _enumerateRowsInCollection:collection
		                      usingBlock:^(int64_t rowid, NSString *key, id object, id metadata, BOOL *stop) {
			
			block(key, object, metadata, stop);
			
		} withFilter:NULL];
	}
}

/**
 * Enumerates all rows in all collections.
 * 
 * The enumeration is sorted by collection. That is, it will enumerate fully over a single collection
 * before moving onto another collection.
 * 
 * If you only need to enumerate over certain rows (e.g. subset of collections, or keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those objects you're not interested in.
**/
- (void)enumerateRowsInAllCollectionsUsingBlock:
                            (void (^)(NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block
{
	[self enumerateRowsInAllCollectionsUsingBlock:block withFilter:NULL];
}

/**
 * Enumerates all rows in all collections.
 * The filter block allows you to decide which objects you're interested in.
 *
 * The enumeration is sorted by collection. That is, it will enumerate fully over a single collection
 * before moving onto another collection.
 * 
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given
 * collection/key pair. If the filter block returns NO, then the block handler is skipped for the given pair,
 * which avoids the cost associated with deserializing the object.
**/
- (void)enumerateRowsInAllCollectionsUsingBlock:
                            (void (^)(NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block
                 withFilter:(BOOL (^)(NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	
	if (filter)
	{
		[self _enumerateRowsInAllCollectionsUsingBlock:
		    ^(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop) {
			
			block(collection, key, object, metadata, stop);
			
		} withFilter:^BOOL(int64_t rowid, NSString *collection, NSString *key) {
			
			return filter(collection, key);
		}];
	}
	else
	{
		[self _enumerateRowsInAllCollectionsUsingBlock:
		    ^(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop) {
			
			block(collection, key, object, metadata, stop);
			
		} withFilter:NULL];
	}
}

/**
 * Enumerates over the given list of keys (unordered).
 *
 * This method is faster than fetching individual items as it optimizes cache access.
 * That is, it will first enumerate over items in the cache and then fetch items from the database,
 * thus optimizing the cache and reducing query size.
 *
 * If any keys are missing from the database, the 'metadata' parameter will be nil.
 *
 * IMPORTANT:
 * Due to cache optimizations, the items may not be enumerated in the same order as the 'keys' parameter.
**/
- (void)enumerateMetadataForKeys:(NSArray *)keys
                    inCollection:(NSString *)collection
             unorderedUsingBlock:(void (^)(NSUInteger keyIndex, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	if ([keys count] == 0) return;
	if (collection == nil) collection = @"";
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	// Check the cache first (to optimize cache)
	
	NSMutableArray *missingIndexes = [NSMutableArray arrayWithCapacity:[keys count]];
	NSUInteger keyIndex = 0;
	
	for (NSString *key in keys)
	{
		YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		id metadata = [connection->metadataCache objectForKey:cacheKey];
		if (metadata)
		{
			if (metadata == [YapNull null])
				block(keyIndex, nil, &stop);
			else
				block(keyIndex, metadata, &stop);
			
			if (stop || isMutated) break;
		}
		else
		{
			[missingIndexes addObject:@(keyIndex)];
		}
		
		keyIndex++;
	}
	
	if (stop) {
		return;
	}
	if (isMutated) {
		@throw [self mutationDuringEnumerationException];
		return;
	}
	if ([missingIndexes count] == 0) {
		return;
	}
	
	// Go to database for any missing keys (if needed)
	
	// Sqlite has an upper bound on the number of host parameters that may be used in a single query.
	// We need to watch out for this in case a large array of keys is passed.
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(connection->db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	
	do
	{
		// Determine how many parameters to use in the query
		
		NSUInteger numKeyParams = MIN([missingIndexes count], (maxHostParams-1)); // minus 1 for collection param
		
		// Create the SQL query:
		// SELECT "key", "metadata" FROM "database2" WHERE "collection" = ? AND key IN (?, ?, ...);
		
		NSUInteger capacity = 80 + (numKeyParams * 3);
		NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
		
		[query appendString:@"SELECT \"key\", \"metadata\" FROM \"database2\""];
		[query appendString:@" WHERE \"collection\" = ? AND \"key\" IN ("];
		
		NSUInteger i;
		for (i = 0; i < numKeyParams; i++)
		{
			if (i == 0)
				[query appendFormat:@"?"];
			else
				[query appendFormat:@", ?"];
		}
		
		[query appendString:@");"];
		
		sqlite3_stmt *statement;
		
		int status = sqlite3_prepare_v2(connection->db, [query UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'metadataForKeys' statement: %d %s",
						status, sqlite3_errmsg(connection->db));
			break; // Break from do/while. Still need to free _collection.
		}
		
		// Bind parameters.
		// And move objects from the missingIndexes array into keyIndexDict.
		
		NSMutableDictionary *keyIndexDict = [NSMutableDictionary dictionaryWithCapacity:numKeyParams];
		
		sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
		
		for (i = 0; i < numKeyParams; i++)
		{
			NSNumber *keyIndexNumber = [missingIndexes objectAtIndex:i];
			NSString *key = [keys objectAtIndex:[keyIndexNumber unsignedIntegerValue]];
			
			[keyIndexDict setObject:keyIndexNumber forKey:key];
			
			sqlite3_bind_text(statement, (int)(i + 2), [key UTF8String], -1, SQLITE_TRANSIENT);
		}
		
		[missingIndexes removeObjectsInRange:NSMakeRange(0, numKeyParams)];
		
		// Execute the query and step over the results
		
		status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			if (connection->needsMarkSqlLevelSharedReadLock)
				[connection markSqlLevelSharedReadLockAcquired];
			
			do
			{
				const unsigned char *text = sqlite3_column_text(statement, 0);
				int textSize = sqlite3_column_bytes(statement, 0);
				
				const void *blob = sqlite3_column_blob(statement, 1);
				int blobSize = sqlite3_column_bytes(statement, 1);
				
				NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				NSUInteger keyIndex = [[keyIndexDict objectForKey:key] unsignedIntegerValue];
				
				NSData *data = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
				
				id metadata = data ? connection->database->metadataDeserializer(collection, key, data) : nil;
				
				if (metadata)
				{
					YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					
					[connection->metadataCache setObject:metadata forKey:cacheKey];
				}
				
				block(keyIndex, metadata, &stop);
				
				[keyIndexDict removeObjectForKey:key];
				
				if (stop || isMutated) break;
				
			} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
		}
		
		if ((status != SQLITE_DONE) && !stop && !isMutated)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_finalize(statement);
		statement = NULL;
		
		if (stop) {
			FreeYapDatabaseString(&_collection);
			return;
		}
		if (isMutated) {
			FreeYapDatabaseString(&_collection);
			@throw [self mutationDuringEnumerationException];
			return;
		}
		
		// If there are any remaining items in the keyIndexDict,
		// then those items didn't exist in the database.
		
		for (NSNumber *keyIndexNumber in [keyIndexDict objectEnumerator])
		{
			block([keyIndexNumber unsignedIntegerValue], nil, &stop);
			
			// Do NOT add keys to the cache that don't exist in the database.
			
			if (stop || isMutated) break;
		}
		
		if (stop) {
			FreeYapDatabaseString(&_collection);
			return;
		}
		if (isMutated) {
			FreeYapDatabaseString(&_collection);
			@throw [self mutationDuringEnumerationException];
			return;
		}
		
		
	} while ([missingIndexes count] > 0);
	
	FreeYapDatabaseString(&_collection);
}

/**
 * Enumerates over the given list of keys (unordered).
 *
 * This method is faster than fetching individual items as it optimizes cache access.
 * That is, it will first enumerate over items in the cache and then fetch items from the database,
 * thus optimizing the cache and reducing query size.
 *
 * If any keys are missing from the database, the 'object' parameter will be nil.
 *
 * IMPORTANT:
 * Due to cache optimizations, the items may not be enumerated in the same order as the 'keys' parameter.
**/
- (void)enumerateObjectsForKeys:(NSArray *)keys
                   inCollection:(NSString *)collection
            unorderedUsingBlock:(void (^)(NSUInteger keyIndex, id object, BOOL *stop))block
{
	if (block == NULL) return;
	if ([keys count] == 0) return;
	if (collection == nil) collection = @"";
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	// Check the cache first (to optimize cache)
	
	NSMutableArray *missingIndexes = [NSMutableArray arrayWithCapacity:[keys count]];
	NSUInteger keyIndex = 0;
	
	for (NSString *key in keys)
	{
		YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		id object = [connection->objectCache objectForKey:cacheKey];
		if (object)
		{
			block(keyIndex, object, &stop);
			
			if (stop || isMutated) break;
		}
		else
		{
			[missingIndexes addObject:@(keyIndex)];
		}
		
		keyIndex++;
	}
	
	if (stop) {
		return;
	}
	if (isMutated) {
		@throw [self mutationDuringEnumerationException];
		return;
	}
	if ([missingIndexes count] == 0) {
		return;
	}
	
	// Go to database for any missing keys (if needed)
	
	// Sqlite has an upper bound on the number of host parameters that may be used in a single query.
	// We need to watch out for this in case a large array of keys is passed.
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(connection->db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	
	do
	{
		// Determine how many parameters to use in the query
		
		NSUInteger numKeyParams = MIN([missingIndexes count], (maxHostParams-1)); // minus 1 for collection param
		
		// Create the SQL query:
		// SELECT "key", "data" FROM "database2" WHERE "collection" = ? AND key IN (?, ?, ...);
		
		NSUInteger capacity = 80 + (numKeyParams * 3);
		NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
		
		[query appendString:@"SELECT \"key\", \"data\" FROM \"database2\""];
		[query appendString:@" WHERE \"collection\" = ? AND \"key\" IN ("];
		
		NSUInteger i;
		for (i = 0; i < numKeyParams; i++)
		{
			if (i == 0)
				[query appendFormat:@"?"];
			else
				[query appendFormat:@", ?"];
		}
		
		[query appendString:@");"];
		
		sqlite3_stmt *statement;
		
		int status = sqlite3_prepare_v2(connection->db, [query UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'objectsForKeys' statement: %d %s",
						status, sqlite3_errmsg(connection->db));
			break; // Break from do/while. Still need to free _collection.
		}
		
		// Bind parameters.
		// And move objects from the missingIndexes array into keyIndexDict.
		
		NSMutableDictionary *keyIndexDict = [NSMutableDictionary dictionaryWithCapacity:numKeyParams];
		
		sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
		
		for (i = 0; i < numKeyParams; i++)
		{
			NSNumber *keyIndexNumber = [missingIndexes objectAtIndex:i];
			NSString *key = [keys objectAtIndex:[keyIndexNumber unsignedIntegerValue]];
			
			[keyIndexDict setObject:keyIndexNumber forKey:key];
			
			sqlite3_bind_text(statement, (int)(i + 2), [key UTF8String], -1, SQLITE_TRANSIENT);
		}
		
		[missingIndexes removeObjectsInRange:NSMakeRange(0, numKeyParams)];
		
		// Execute the query and step over the results
		
		status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			if (connection->needsMarkSqlLevelSharedReadLock)
				[connection markSqlLevelSharedReadLockAcquired];
			
			do
			{
				const unsigned char *text = sqlite3_column_text(statement, 0);
				int textSize = sqlite3_column_bytes(statement, 0);
				
				const void *blob = sqlite3_column_blob(statement, 1);
				int blobSize = sqlite3_column_bytes(statement, 1);
				
				NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				NSUInteger keyIndex = [[keyIndexDict objectForKey:key] unsignedIntegerValue];
				
				NSData *objectData = [NSData dataWithBytesNoCopy:(void *)blob length:blobSize freeWhenDone:NO];
				id object = connection->database->objectDeserializer(collection, key, objectData);
				
				if (object)
				{
					YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					[connection->objectCache setObject:object forKey:cacheKey];
				}
				
				block(keyIndex, object, &stop);
				
				[keyIndexDict removeObjectForKey:key];
				
				if (stop || isMutated) break;
				
			} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
		}
		
		if ((status != SQLITE_DONE) && !stop && !isMutated)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_finalize(statement);
		statement = NULL;
		
		if (stop) {
			FreeYapDatabaseString(&_collection);
			return;
		}
		if (isMutated) {
			FreeYapDatabaseString(&_collection);
			@throw [self mutationDuringEnumerationException];
			return;
		}
		
		// If there are any remaining items in the keyIndexDict,
		// then those items didn't exist in the database.
		
		for (NSNumber *keyIndexNumber in [keyIndexDict objectEnumerator])
		{
			block([keyIndexNumber unsignedIntegerValue], nil, &stop);
			
			// Do NOT add keys to the cache that don't exist in the database.
			
			if (stop || isMutated) break;
		}
		
		if (stop) {
			FreeYapDatabaseString(&_collection);
			return;
		}
		if (isMutated) {
			FreeYapDatabaseString(&_collection);
			@throw [self mutationDuringEnumerationException];
			return;
		}
		
		
	} while ([missingIndexes count] > 0);
	
	FreeYapDatabaseString(&_collection);
}

/**
 * Enumerates over the given list of keys (unordered).
 *
 * This method is faster than fetching individual items as it optimizes cache access.
 * That is, it will first enumerate over items in the cache and then fetch items from the database,
 * thus optimizing the cache and reducing query size.
 *
 * If any keys are missing from the database, the 'object' parameter will be nil.
 *
 * IMPORTANT:
 * Due to cache optimizations, the items may not be enumerated in the same order as the 'keys' parameter.
**/
- (void)enumerateRowsForKeys:(NSArray *)keys
                inCollection:(NSString *)collection
         unorderedUsingBlock:(void (^)(NSUInteger keyIndex, id object, id metadata, BOOL *stop))block
{
	if (block == NULL) return;
	if ([keys count] == 0) return;
	if (collection == nil) collection = @"";
	
	isMutated = NO; // mutation during enumeration protection
	__block BOOL stop = NO;
	
	// Check the cache first (to optimize cache)
	
	NSMutableArray *missingIndexes = [NSMutableArray arrayWithCapacity:[keys count]];
	NSUInteger keyIndex = 0;
	
	for (NSString *key in keys)
	{
		YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		id object = [connection->objectCache objectForKey:cacheKey];
		if (object)
		{
			id metadata = [connection->metadataCache objectForKey:cacheKey];
			if (metadata)
			{
				if (metadata == [YapNull null])
					block(keyIndex, object, nil, &stop);
				else
					block(keyIndex, object, metadata, &stop);
				
				if (stop || isMutated) break;
			}
			else
			{
				[missingIndexes addObject:@(keyIndex)];
			}
		}
		else
		{
			[missingIndexes addObject:@(keyIndex)];
		}
		
		keyIndex++;
	}
	
	if (stop) {
		return;
	}
	if (isMutated) {
		@throw [self mutationDuringEnumerationException];
		return;
	}
	if ([missingIndexes count] == 0) {
		return;
	}
	
	// Go to database for any missing keys (if needed)
	
	// Sqlite has an upper bound on the number of host parameters that may be used in a single query.
	// We need to watch out for this in case a large array of keys is passed.
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(connection->db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	
	do
	{
		// Determine how many parameters to use in the query
		
		NSUInteger numKeyParams = MIN([missingIndexes count], (maxHostParams-1)); // minus 1 for collection param
		
		// Create the SQL query:
		// SELECT "key", "data", "metadata" FROM "database2" WHERE "collection" = ? AND key IN (?, ?, ...);
		
		NSUInteger capacity = 80 + (numKeyParams * 3);
		NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
		
		[query appendString:@"SELECT \"key\", \"data\", \"metadata\" FROM \"database2\""];
		[query appendString:@" WHERE \"collection\" = ? AND \"key\" IN ("];
		
		NSUInteger i;
		for (i = 0; i < numKeyParams; i++)
		{
			if (i == 0)
				[query appendFormat:@"?"];
			else
				[query appendFormat:@", ?"];
		}
		
		[query appendString:@");"];
		
		sqlite3_stmt *statement;
		
		int status = sqlite3_prepare_v2(connection->db, [query UTF8String], -1, &statement, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"Error creating 'objectsAndMetadataForKeys' statement: %d %s",
						status, sqlite3_errmsg(connection->db));
			break; // Break from do/while. Still need to free _collection.
		}
		
		// Bind parameters.
		// And move objects from the missingIndexes array into keyIndexDict.
		
		NSMutableDictionary *keyIndexDict = [NSMutableDictionary dictionaryWithCapacity:numKeyParams];
		
		sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
		
		for (i = 0; i < numKeyParams; i++)
		{
			NSNumber *keyIndexNumber = [missingIndexes objectAtIndex:i];
			NSString *key = [keys objectAtIndex:[keyIndexNumber unsignedIntegerValue]];
			
			[keyIndexDict setObject:keyIndexNumber forKey:key];
			
			sqlite3_bind_text(statement, (int)(i + 2), [key UTF8String], -1, SQLITE_TRANSIENT);
		}
		
		[missingIndexes removeObjectsInRange:NSMakeRange(0, numKeyParams)];
		
		// Execute the query and step over the results
		
		status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			if (connection->needsMarkSqlLevelSharedReadLock)
				[connection markSqlLevelSharedReadLockAcquired];
			
			do
			{
				const unsigned char *text = sqlite3_column_text(statement, 0);
				int textSize = sqlite3_column_bytes(statement, 0);
				
				NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				NSUInteger keyIndex = [[keyIndexDict objectForKey:key] unsignedIntegerValue];
				
				YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				id object = [connection->objectCache objectForKey:cacheKey];
				if (object == nil)
				{
					const void *oBlob = sqlite3_column_blob(statement, 1);
					int oBlobSize = sqlite3_column_bytes(statement, 1);
					
					NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
					object = connection->database->objectDeserializer(collection, key, oData);
					
					if (object)
						[connection->objectCache setObject:object forKey:cacheKey];
				}
				
				id metadata = [connection->metadataCache objectForKey:cacheKey];
				if (metadata)
				{
					if (metadata == [YapNull null])
						metadata = nil;
				}
				else
				{
					const void *mBlob = sqlite3_column_blob(statement, 2);
					int mBlobSize = sqlite3_column_bytes(statement, 2);
					
					if (mBlobSize > 0)
					{
						NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
						metadata = connection->database->metadataDeserializer(collection, key, mData);
					}
					
					if (metadata)
						[connection->metadataCache setObject:metadata forKey:cacheKey];
					else
						[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
				}
				
				block(keyIndex, object, metadata, &stop);
				
				[keyIndexDict removeObjectForKey:key];
				
				if (stop || isMutated) break;
				
			} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
		}
		
		if ((status != SQLITE_DONE) && !stop && !isMutated)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_finalize(statement);
		statement = NULL;
		
		if (stop) {
			FreeYapDatabaseString(&_collection);
			return;
		}
		if (isMutated) {
			FreeYapDatabaseString(&_collection);
			@throw [self mutationDuringEnumerationException];
			return;
		}
		
		// If there are any remaining items in the keyIndexDict,
		// then those items didn't exist in the database.
		
		for (NSNumber *keyIndexNumber in [keyIndexDict objectEnumerator])
		{
			block([keyIndexNumber unsignedIntegerValue], nil, nil, &stop);
			
			// Do NOT add keys to the cache that don't exist in the database.
			
			if (stop || isMutated) break;
		}
		
		if (stop) {
			FreeYapDatabaseString(&_collection);
			return;
		}
		if (isMutated) {
			FreeYapDatabaseString(&_collection);
			@throw [self mutationDuringEnumerationException];
			return;
		}
		
		
	} while ([missingIndexes count] > 0);
	
	FreeYapDatabaseString(&_collection);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal Enumerate (using rowid)
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Fast enumeration over all keys in the given collection.
 *
 * This uses a "SELECT key FROM database WHERE collection = ?" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)_enumerateKeysInCollection:(NSString *)collection
                        usingBlock:(void (^)(int64_t rowid, NSString *key, BOOL *stop))block
{
	if (block == NULL) return;
	if (collection == nil) collection = @"";
	
	sqlite3_stmt *statement = [connection enumerateKeysInCollectionStatement];
	if (statement == NULL) return;
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "key" FROM "database2" WHERE collection = ?;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		do
		{
			int64_t rowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text = sqlite3_column_text(statement, 1);
			int textSize = sqlite3_column_bytes(statement, 1);
			
			NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			block(rowid, key, &stop);
			
			if (stop || isMutated) break;
			
		} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
	}
	
	if ((status != SQLITE_DONE) && !stop && !isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	
	if (isMutated && !stop)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * Fast enumeration over all keys in select collections.
 *
 * This uses a "SELECT key FROM database WHERE collection = ?" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)_enumerateKeysInCollections:(NSArray *)collections
                         usingBlock:(void (^)(int64_t rowid, NSString *collection, NSString *key, BOOL *stop))block
{
	if (block == NULL) return;
	if ([collections count] == 0) return;
	
	sqlite3_stmt *statement = [connection enumerateKeysInCollectionStatement];
	if (statement == NULL) return;
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "key" FROM "database2" WHERE collection = ?;
	
	for (NSString *collection in collections)
	{
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			if (connection->needsMarkSqlLevelSharedReadLock)
				[connection markSqlLevelSharedReadLockAcquired];
			
			do
			{
				int64_t rowid = sqlite3_column_int64(statement, 0);
				
				const unsigned char *text = sqlite3_column_text(statement, 1);
				int textSize = sqlite3_column_bytes(statement, 1);
				
				NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				
				block(rowid, collection, key, &stop);
				
				if (stop || isMutated) break;
				
			} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
		}
		
		if ((status != SQLITE_DONE) && !stop && !isMutated)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_collection);
		
		if (isMutated && !stop)
		{
			@throw [self mutationDuringEnumerationException];
		}
			
		if (stop)
		{
			break;
		}
		
	} // end for (NSString *collection in collections)
}

/**
 * Fast enumeration over all keys in the given collection.
 *
 * This uses a "SELECT collection, key FROM database" operation,
 * and then steps over the results invoking the given block handler.
**/
- (void)_enumerateKeysInAllCollectionsUsingBlock:
                            (void (^)(int64_t rowid, NSString *collection, NSString *key, BOOL *stop))block
{
	if (block == NULL) return;
	
	sqlite3_stmt *statement = [connection enumerateKeysInAllCollectionsStatement];
	if (statement == NULL) return;
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "collection", "key" FROM "database2";
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		do
		{
			int64_t rowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text1 = sqlite3_column_text(statement, 1);
			int textSize1 = sqlite3_column_bytes(statement, 1);
			
			const unsigned char *text2 = sqlite3_column_text(statement, 2);
			int textSize2 = sqlite3_column_bytes(statement, 2);
			
			NSString *collection, *key;
			
			collection = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
			key        = [[NSString alloc] initWithBytes:text2 length:textSize2 encoding:NSUTF8StringEncoding];
			
			block(rowid, collection, key, &stop);
			
			if (stop || isMutated) break;
			
		} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
	}
	
	if ((status != SQLITE_DONE) && !stop && !isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_reset(statement);
	
	if (isMutated && !stop)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * Fast enumeration over all keys and associated metadata in the given collection.
 * 
 * This uses a "SELECT key, metadata FROM database WHERE collection = ?" operation and steps over the results.
 * 
 * If you only need to enumerate over certain items (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the deserialization step for those items you're not interested in.
 * 
 * Keep in mind that you cannot modify the collection mid-enumeration (just like any other kind of enumeration).
**/
- (void)_enumerateKeysAndMetadataInCollection:(NSString *)collection
                                   usingBlock:(void (^)(int64_t rowid, NSString *key, id metadata, BOOL *stop))block
{
	[self _enumerateKeysAndMetadataInCollection:collection usingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over all keys and associated metadata in the given collection.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
 * 
 * Keep in mind that you cannot modify the collection mid-enumeration (just like any other kind of enumeration).
**/
- (void)_enumerateKeysAndMetadataInCollection:(NSString *)collection
                                   usingBlock:(void (^)(int64_t rowid, NSString *key, id metadata, BOOL *stop))block
                                   withFilter:(BOOL (^)(int64_t rowid, NSString *key))filter;
{
	if (block == NULL) return;
	if (collection == nil) collection = @"";
	
	sqlite3_stmt *statement = [connection enumerateKeysAndMetadataInCollectionStatement];
	if (statement == NULL) return;
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "key", "metadata" FROM "database2" WHERE "collection" = ?;
	//
	// Performance tuning:
	// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
	//
	// Cache considerations:
	// Do we want to add the objects/metadata to the cache here?
	// If the cache is unlimited then we should.
	// Otherwise we should only add to the cache if its not full.
	// The cache should generally be reserved for items that are explicitly fetched,
	// and we don't want to crowd them out during enumerations.
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	
	BOOL unlimitedMetadataCacheLimit = (connection->metadataCacheLimit == 0);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		do
		{
			int64_t rowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text = sqlite3_column_text(statement, 1);
			int textSize = sqlite3_column_bytes(statement, 1);
			
			NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, key);
			if (invokeBlock)
			{
				YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
			
				id metadata = [connection->metadataCache objectForKey:cacheKey];
				if (metadata)
				{
					if (metadata == [YapNull null])
						metadata = nil;
				}
				else
				{
					const void *mBlob = sqlite3_column_blob(statement, 2);
					int mBlobSize = sqlite3_column_bytes(statement, 2);
					
					if (mBlobSize > 0)
					{
						NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
						metadata = connection->database->metadataDeserializer(collection, key, mData);
					}
					
					if (unlimitedMetadataCacheLimit ||
					    [connection->metadataCache count] < connection->metadataCacheLimit)
					{
						if (metadata)
							[connection->metadataCache setObject:metadata forKey:cacheKey];
						else
							[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
					}
				}
				
				block(rowid, key, metadata, &stop);
				
				if (stop || isMutated) break;
			}
			
		} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
	}
	
	if ((status != SQLITE_DONE) && !stop && !isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	
	if (isMutated && !stop)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * Fast enumeration over select keys and associated metadata in the given collection.
 * 
 * This uses a "SELECT key, metadata FROM database WHERE collection = ?" operation and steps over the results.
 * 
 * If you only need to enumerate over certain items (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the deserialization step for those items you're not interested in.
 * 
 * Keep in mind that you cannot modify the collection mid-enumeration (just like any other kind of enumeration).
**/
- (void)_enumerateKeysAndMetadataInCollections:(NSArray *)collections
                usingBlock:(void (^)(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop))block
{
	[self _enumerateKeysAndMetadataInCollections:collections usingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over selected keys and associated metadata in the given collection.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
 * 
 * Keep in mind that you cannot modify the collection mid-enumeration (just like any other kind of enumeration).
**/
- (void)_enumerateKeysAndMetadataInCollections:(NSArray *)collections
                usingBlock:(void (^)(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop))block
                withFilter:(BOOL (^)(int64_t rowid, NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	if ([collections count] == 0) return;
	
	sqlite3_stmt *statement = [connection enumerateKeysAndMetadataInCollectionStatement];
	if (statement == NULL) return;
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	BOOL unlimitedMetadataCacheLimit = (connection->metadataCacheLimit == 0);
	
	// SELECT "rowid", "key", "metadata" FROM "database2" WHERE "collection" = ?;
	//
	// Performance tuning:
	// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
	//
	// Cache considerations:
	// Do we want to add the objects/metadata to the cache here?
	// If the cache is unlimited then we should.
	// Otherwise we should only add to the cache if its not full.
	// The cache should generally be reserved for items that are explicitly fetched,
	// and we don't want to crowd them out during enumerations.
	
	for (NSString *collection in collections)
	{
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			if (connection->needsMarkSqlLevelSharedReadLock)
				[connection markSqlLevelSharedReadLockAcquired];
			
			do
			{
				int64_t rowid = sqlite3_column_int64(statement, 0);
				
				const unsigned char *text = sqlite3_column_text(statement, 1);
				int textSize = sqlite3_column_bytes(statement, 1);
				
				NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				
				BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, collection, key);
				if (invokeBlock)
				{
					YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
					id metadata = [connection->metadataCache objectForKey:cacheKey];
					if (metadata)
					{
						if (metadata == [YapNull null])
							metadata = nil;
					}
					else
					{
						const void *mBlob = sqlite3_column_blob(statement, 2);
						int mBlobSize = sqlite3_column_bytes(statement, 2);
						
						if (mBlobSize > 0)
						{
							NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
							metadata = connection->database->metadataDeserializer(collection, key, mData);
						}
						
						if (unlimitedMetadataCacheLimit ||
						    [connection->metadataCache count] < connection->metadataCacheLimit)
						{
							if (metadata)
								[connection->metadataCache setObject:metadata forKey:cacheKey];
							else
								[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
						}
					}
					
					block(rowid, collection, key, metadata, &stop);
					
					if (stop || isMutated) break;
				}
				
			} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
		}
		
		if ((status != SQLITE_DONE) && !stop && !isMutated)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_collection);
		
		if (isMutated && !stop)
		{
			@throw [self mutationDuringEnumerationException];
		}
		
		if (stop)
		{
			break;
		}
		
	} // end for (NSString *collection in collections)
}

/**
 * Fast enumeration over all key/metadata pairs in all collections.
 * 
 * This uses a "SELECT metadata FROM database ORDER BY collection ASC" operation, and steps over the results.
 * 
 * If you only need to enumerate over certain objects (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the deserialization step for those objects you're not interested in.
 * 
 * Keep in mind that you cannot modify the database mid-enumeration (just like any other kind of enumeration).
**/
- (void)_enumerateKeysAndMetadataInAllCollectionsUsingBlock:
                        (void (^)(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop))block
{
	[self _enumerateKeysAndMetadataInAllCollectionsUsingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over all key/metadata pairs in all collections.
 *
 * This uses a "SELECT metadata FROM database ORDER BY collection ASC" operation and steps over the results.
 * 
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
 *
 * Keep in mind that you cannot modify the database mid-enumeration (just like any other kind of enumeration).
 **/
- (void)_enumerateKeysAndMetadataInAllCollectionsUsingBlock:
                        (void (^)(int64_t rowid, NSString *collection, NSString *key, id metadata, BOOL *stop))block
             withFilter:(BOOL (^)(int64_t rowid, NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	
	sqlite3_stmt *statement = [connection enumerateKeysAndMetadataInAllCollectionsStatement];
	if (statement == NULL) return;
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "collection", "key", "metadata" FROM "database2" ORDER BY "collection" ASC;
	//
	// Performance tuning:
	// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
	//
	// Cache considerations:
	// Do we want to add the objects/metadata to the cache here?
	// If the cache is unlimited then we should.
	// Otherwise we should only add to the cache if its not full.
	// The cache should generally be reserved for items that are explicitly fetched,
	// and we don't want to crowd them out during enumerations.
	
	BOOL unlimitedMetadataCacheLimit = (connection->metadataCacheLimit == 0);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		do
		{
			int64_t rowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text1 = sqlite3_column_text(statement, 1);
			int textSize1 = sqlite3_column_bytes(statement, 1);
			
			const unsigned char *text2 = sqlite3_column_text(statement, 2);
			int textSize2 = sqlite3_column_bytes(statement, 2);
			
			NSString *collection, *key;
			
			collection = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
			key        = [[NSString alloc] initWithBytes:text2 length:textSize2 encoding:NSUTF8StringEncoding];
			
			BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, collection, key);
			if (invokeBlock)
			{
				YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				id metadata = [connection->metadataCache objectForKey:cacheKey];
				if (metadata)
				{
					if (metadata == [YapNull null])
						metadata = nil;
				}
				else
				{
					const void *mBlob = sqlite3_column_blob(statement, 3);
					int mBlobSize = sqlite3_column_bytes(statement, 3);
					
					if (mBlobSize > 0)
					{
						NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
						metadata = connection->database->metadataDeserializer(collection, key, mData);
					}
					
					if (unlimitedMetadataCacheLimit ||
					    [connection->metadataCache count] < connection->metadataCacheLimit)
					{
						if (metadata)
							[connection->metadataCache setObject:metadata forKey:cacheKey];
						else
							[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
					}
				}
				
				block(rowid, collection, key, metadata, &stop);
				
				if (stop || isMutated) break;
			}
			
		} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
	}
	
	if ((status != SQLITE_DONE) && !stop && !isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_reset(statement);
	
	if (isMutated && !stop)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * Fast enumeration over all objects in the database.
 *
 * This uses a "SELECT key, object from database WHERE collection = ?" operation, and then steps over the results,
 * deserializing each object, and then invoking the given block handler.
 *
 * If you only need to enumerate over certain objects (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those objects you're not interested in.
**/
- (void)_enumerateKeysAndObjectsInCollection:(NSString *)collection
                                  usingBlock:(void (^)(int64_t rowid, NSString *key, id object, BOOL *stop))block
{
	[self _enumerateKeysAndObjectsInCollection:collection usingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over objects in the database for which you're interested in.
 * The filter block allows you to decide which objects you're interested in.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
**/
- (void)_enumerateKeysAndObjectsInCollection:(NSString *)collection
                                  usingBlock:(void (^)(int64_t rowid, NSString *key, id object, BOOL *stop))block
                                  withFilter:(BOOL (^)(int64_t rowid, NSString *key))filter
{
	if (block == NULL) return;
	if (collection == nil) collection = @"";
	
	sqlite3_stmt *statement = [connection enumerateKeysAndObjectsInCollectionStatement];
	if (statement == NULL) return;
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "key", "data", FROM "database2" WHERE "collection" = ?;
	//
	// Performance tuning:
	// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
	//
	// Cache considerations:
	// Do we want to add the objects/metadata to the cache here?
	// If the cache is unlimited then we should.
	// Otherwise we should only add to the cache if its not full.
	// The cache should generally be reserved for items that are explicitly fetched,
	// and we don't want to crowd them out during enumerations.
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	
	BOOL unlimitedObjectCacheLimit = (connection->objectCacheLimit == 0);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		do
		{
			int64_t rowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text = sqlite3_column_text(statement, 1);
			int textSize = sqlite3_column_bytes(statement, 1);
			
			NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, key);
			if (invokeBlock)
			{
				YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				id object = [connection->objectCache objectForKey:cacheKey];
				if (object == nil)
				{
					const void *oBlob = sqlite3_column_blob(statement, 2);
					int oBlobSize = sqlite3_column_bytes(statement, 2);
					
					NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
					object = connection->database->objectDeserializer(collection, key, oData);
					
					if (unlimitedObjectCacheLimit || [connection->objectCache count] < connection->objectCacheLimit)
					{
						if (object)
							[connection->objectCache setObject:object forKey:cacheKey];
					}
				}
				
				block(rowid, key, object, &stop);
				
				if (stop || isMutated) break;
			}
			
		} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
	}
	
	if ((status != SQLITE_DONE) && !stop && !isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	
	if (isMutated && !stop)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * Fast enumeration over selected objects in the database.
 *
 * This uses a "SELECT key, object from database WHERE collection = ?" operation, and then steps over the results,
 * deserializing each object, and then invoking the given block handler.
 *
 * If you only need to enumerate over certain objects (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those objects you're not interested in.
**/
- (void)_enumerateKeysAndObjectsInCollections:(NSArray *)collections usingBlock:
                            (void (^)(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop))block
{
	[self _enumerateKeysAndObjectsInCollections:collections usingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over objects in the database for which you're interested in.
 * The filter block allows you to decide which objects you're interested in.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object.
**/
- (void)_enumerateKeysAndObjectsInCollections:(NSArray *)collections
                 usingBlock:(void (^)(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop))block
                 withFilter:(BOOL (^)(int64_t rowid, NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	if ([collections count] == 0) return;
	
	sqlite3_stmt *statement = [connection enumerateKeysAndObjectsInCollectionStatement];
	if (statement == NULL) return;
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	BOOL unlimitedObjectCacheLimit = (connection->objectCacheLimit == 0);
	
	// SELECT "rowid", "key", "data", FROM "database2" WHERE "collection" = ?;
	//
	// Performance tuning:
	// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
	//
	// Cache considerations:
	// Do we want to add the objects/metadata to the cache here?
	// If the cache is unlimited then we should.
	// Otherwise we should only add to the cache if its not full.
	// The cache should generally be reserved for items that are explicitly fetched,
	// and we don't want to crowd them out during enumerations.
	
	for (NSString *collection in collections)
	{
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			if (connection->needsMarkSqlLevelSharedReadLock)
				[connection markSqlLevelSharedReadLockAcquired];
			
			do
			{
				int64_t rowid = sqlite3_column_int64(statement, 0);
				
				const unsigned char *text = sqlite3_column_text(statement, 1);
				int textSize = sqlite3_column_bytes(statement, 1);
				
				NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				
				BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, collection, key);
				if (invokeBlock)
				{
					YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					
					id object = [connection->objectCache objectForKey:cacheKey];
					if (object == nil)
					{
						const void *oBlob = sqlite3_column_blob(statement, 2);
						int oBlobSize = sqlite3_column_bytes(statement, 2);
						
						NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
						object = connection->database->objectDeserializer(collection, key, oData);
						
						if (unlimitedObjectCacheLimit ||
						    [connection->objectCache count] < connection->objectCacheLimit)
						{
							if (object)
								[connection->objectCache setObject:object forKey:cacheKey];
						}
					}
					
					block(rowid, collection, key, object, &stop);
					
					if (stop || isMutated) break;
				}
				
			} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
		}
		
		if ((status != SQLITE_DONE) && !stop && !isMutated)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_collection);
		
		if (isMutated && !stop)
		{
			@throw [self mutationDuringEnumerationException];
		}
		
		if (stop)
		{
			break;
		}
		
	} // end for (NSString *collection in collections)
}

/**
 * Enumerates all key/object pairs in all collections.
 *
 * The enumeration is sorted by collection. That is, it will enumerate fully over a single collection
 * before moving onto another collection.
 *
 * If you only need to enumerate over certain objects (e.g. subset of collections, or keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those objects you're not interested in.
**/
- (void)_enumerateKeysAndObjectsInAllCollectionsUsingBlock:
                            (void (^)(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop))block
{
	[self _enumerateKeysAndObjectsInAllCollectionsUsingBlock:block withFilter:NULL];
}

/**
 * Enumerates all key/object pairs in all collections.
 * The filter block allows you to decide which objects you're interested in.
 *
 * The enumeration is sorted by collection. That is, it will enumerate fully over a single collection
 * before moving onto another collection.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given
 * collection/key pair. If the filter block returns NO, then the block handler is skipped for the given pair,
 * which avoids the cost associated with deserializing the object.
**/
- (void)_enumerateKeysAndObjectsInAllCollectionsUsingBlock:
                            (void (^)(int64_t rowid, NSString *collection, NSString *key, id object, BOOL *stop))block
                 withFilter:(BOOL (^)(int64_t rowid, NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	
	sqlite3_stmt *statement = [connection enumerateKeysAndObjectsInAllCollectionsStatement];
	if (statement == NULL) return;
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "collection", "key", "data" FROM "database2" ORDER BY \"collection\" ASC;";
	//           0           1         2       3
	
	BOOL unlimitedObjectCacheLimit = (connection->objectCacheLimit == 0);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		do
		{
			int64_t rowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text1 = sqlite3_column_text(statement, 1);
			int textSize1 = sqlite3_column_bytes(statement, 1);
			
			const unsigned char *text2 = sqlite3_column_text(statement, 2);
			int textSize2 = sqlite3_column_bytes(statement, 2);
			
			NSString *collection, *key;
			
			collection = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
			key        = [[NSString alloc] initWithBytes:text2 length:textSize2 encoding:NSUTF8StringEncoding];
			
			BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, collection, key);
			if (invokeBlock)
			{
				YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				id object = [connection->objectCache objectForKey:cacheKey];
				if (object == nil)
				{
					const void *oBlob = sqlite3_column_blob(statement, 3);
					int oBlobSize = sqlite3_column_bytes(statement, 3);
					
					NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
					object = connection->database->objectDeserializer(collection, key, oData);
					
					if (unlimitedObjectCacheLimit || [connection->objectCache count] < connection->objectCacheLimit)
					{
						if (object)
							[connection->objectCache setObject:object forKey:cacheKey];
					}
				}
				
				block(rowid, collection, key, object, &stop);
				
				if (stop || isMutated) break;
			}
			
		} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
	}
	
	if ((status != SQLITE_DONE) && !stop && !isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (isMutated && !stop)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * Fast enumeration over all rows in the database.
 *
 * This uses a "SELECT key, data, metadata from database WHERE collection = ?" operation,
 * and then steps over the results, deserializing each object & metadata, and then invoking the given block handler.
 *
 * If you only need to enumerate over certain rows (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those rows you're not interested in.
**/
- (void)_enumerateRowsInCollection:(NSString *)collection
                        usingBlock:(void (^)(int64_t rowid, NSString *key, id object, id metadata, BOOL *stop))block
{
	[self _enumerateRowsInCollection:collection usingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over rows in the database for which you're interested in.
 * The filter block allows you to decide which rows you're interested in.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object & metadata.
**/
- (void)_enumerateRowsInCollection:(NSString *)collection
                        usingBlock:(void (^)(int64_t rowid, NSString *key, id object, id metadata, BOOL *stop))block
                        withFilter:(BOOL (^)(int64_t rowid, NSString *key))filter
{
	if (block == NULL) return;
	if (collection == nil) collection = @"";
	
	sqlite3_stmt *statement = [connection enumerateRowsInCollectionStatement];
	if (statement == NULL) return;
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "key", "data", "metadata" FROM "database2" WHERE "collection" = ?;
	//
	// Performance tuning:
	// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
	//
	// Cache considerations:
	// Do we want to add the objects/metadata to the cache here?
	// If the cache is unlimited then we should.
	// Otherwise we should only add to the cache if its not full.
	// The cache should generally be reserved for items that are explicitly fetched,
	// and we don't want to crowd them out during enumerations.
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
	
	BOOL unlimitedObjectCacheLimit = (connection->objectCacheLimit == 0);
	BOOL unlimitedMetadataCacheLimit = (connection->metadataCacheLimit == 0);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		do
		{
			int64_t rowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text = sqlite3_column_text(statement, 1);
			int textSize = sqlite3_column_bytes(statement, 1);
			
			NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
			
			BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, key);
			if (invokeBlock)
			{
				YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				id object = [connection->objectCache objectForKey:cacheKey];
				if (object == nil)
				{
					const void *oBlob = sqlite3_column_blob(statement, 2);
					int oBlobSize = sqlite3_column_bytes(statement, 2);
					
					NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
					object = connection->database->objectDeserializer(collection, key, oData);
					
					if (unlimitedObjectCacheLimit || [connection->objectCache count] < connection->objectCacheLimit)
					{
						if (object)
							[connection->objectCache setObject:object forKey:cacheKey];
					}
				}
				
				id metadata = [connection->metadataCache objectForKey:cacheKey];
				if (metadata)
				{
					if (metadata == [YapNull null])
						metadata = nil;
				}
				else
				{
					const void *mBlob = sqlite3_column_blob(statement, 3);
					int mBlobSize = sqlite3_column_bytes(statement, 3);
					
					if (mBlobSize > 0)
					{
						NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
						metadata = connection->database->metadataDeserializer(collection, key, mData);
					}
					
					if (unlimitedMetadataCacheLimit ||
					    [connection->metadataCache count] < connection->metadataCacheLimit)
					{
						if (metadata)
							[connection->metadataCache setObject:metadata forKey:cacheKey];
						else
							[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
					}
				}
				
				block(rowid, key, object, metadata, &stop);
				
				if (stop || isMutated) break;
			}
			
		} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
	}
	
	if ((status != SQLITE_DONE) && !stop && !isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	FreeYapDatabaseString(&_collection);
	
	if (isMutated && !stop)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

/**
 * Fast enumeration over select rows in the database.
 *
 * This uses a "SELECT key, data, metadata from database WHERE collection = ?" operation,
 * and then steps over the results, deserializing each object & metadata, and then invoking the given block handler.
 *
 * If you only need to enumerate over certain rows (e.g. keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those rows you're not interested in.
**/
- (void)_enumerateRowsInCollections:(NSArray *)collections usingBlock:
                (void (^)(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block
{
	[self _enumerateRowsInCollections:collections usingBlock:block withFilter:NULL];
}

/**
 * Fast enumeration over rows in the database for which you're interested in.
 * The filter block allows you to decide which rows you're interested in.
 *
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given key.
 * If the filter block returns NO, then the block handler is skipped for the given key,
 * which avoids the cost associated with deserializing the object & metadata.
**/
- (void)_enumerateRowsInCollections:(NSArray *)collections
     usingBlock:(void (^)(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block
     withFilter:(BOOL (^)(int64_t rowid, NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	if ([collections count] == 0) return;
	
	sqlite3_stmt *statement = [connection enumerateRowsInCollectionStatement];
	if (statement == NULL) return;
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	BOOL unlimitedObjectCacheLimit = (connection->objectCacheLimit == 0);
	BOOL unlimitedMetadataCacheLimit = (connection->metadataCacheLimit == 0);
	
	// SELECT "rowid", "key", "data", "metadata" FROM "database2" WHERE "collection" = ?;
	//
	// Performance tuning:
	// Use dataWithBytesNoCopy to avoid an extra allocation and memcpy.
	//
	// Cache considerations:
	// Do we want to add the objects/metadata to the cache here?
	// If the cache is unlimited then we should.
	// Otherwise we should only add to the cache if its not full.
	// The cache should generally be reserved for items that are explicitly fetched,
	// and we don't want to crowd them out during enumerations.
	
	for (NSString *collection in collections)
	{
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			if (connection->needsMarkSqlLevelSharedReadLock)
				[connection markSqlLevelSharedReadLockAcquired];
			
			do
			{
				int64_t rowid = sqlite3_column_int64(statement, 0);
				
				const unsigned char *text = sqlite3_column_text(statement, 1);
				int textSize = sqlite3_column_bytes(statement, 1);
				
				NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				
				BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, collection, key);
				if (invokeBlock)
				{
					YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
					
					id object = [connection->objectCache objectForKey:cacheKey];
					if (object == nil)
					{
						const void *oBlob = sqlite3_column_blob(statement, 2);
						int oBlobSize = sqlite3_column_bytes(statement, 2);
						
						NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
						object = connection->database->objectDeserializer(collection, key, oData);
						
						if (unlimitedObjectCacheLimit ||
						    [connection->objectCache count] < connection->objectCacheLimit)
						{
							if (object)
								[connection->objectCache setObject:object forKey:cacheKey];
						}
					}
					
					id metadata = [connection->metadataCache objectForKey:cacheKey];
					if (metadata)
					{
						if (metadata == [YapNull null])
							metadata = nil;
					}
					else
					{
						const void *mBlob = sqlite3_column_blob(statement, 3);
						int mBlobSize = sqlite3_column_bytes(statement, 3);
						
						if (mBlobSize > 0)
						{
							NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
							metadata = connection->database->metadataDeserializer(collection, key, mData);
						}
						
						if (unlimitedMetadataCacheLimit ||
						    [connection->metadataCache count] < connection->metadataCacheLimit)
						{
							if (metadata)
								[connection->metadataCache setObject:metadata forKey:cacheKey];
							else
								[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
						}
					}
					
					block(rowid, collection, key, object, metadata, &stop);
					
					if (stop || isMutated) break;
				}
				
			} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
		}
		
		if ((status != SQLITE_DONE) && !stop && !isMutated)
		{
			YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_collection);
		
		if (isMutated && !stop)
		{
			@throw [self mutationDuringEnumerationException];
		}
		
		if (stop)
		{
			break;
		}
	
	} // end for (NSString *collection in collections)
}

/**
 * Enumerates all rows in all collections.
 * 
 * The enumeration is sorted by collection. That is, it will enumerate fully over a single collection
 * before moving onto another collection.
 * 
 * If you only need to enumerate over certain rows (e.g. subset of collections, or keys with a particular prefix),
 * consider using the alternative version below which provides a filter,
 * allowing you to skip the serialization step for those objects you're not interested in.
**/
- (void)_enumerateRowsInAllCollectionsUsingBlock:
                (void (^)(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block
{
	[self _enumerateRowsInAllCollectionsUsingBlock:block withFilter:NULL];
}

/**
 * Enumerates all rows in all collections.
 * The filter block allows you to decide which objects you're interested in.
 *
 * The enumeration is sorted by collection. That is, it will enumerate fully over a single collection
 * before moving onto another collection.
 * 
 * From the filter block, simply return YES if you'd like the block handler to be invoked for the given
 * collection/key pair. If the filter block returns NO, then the block handler is skipped for the given pair,
 * which avoids the cost associated with deserializing the object.
**/
- (void)_enumerateRowsInAllCollectionsUsingBlock:
                (void (^)(int64_t rowid, NSString *collection, NSString *key, id object, id metadata, BOOL *stop))block
     withFilter:(BOOL (^)(int64_t rowid, NSString *collection, NSString *key))filter
{
	if (block == NULL) return;
	
	sqlite3_stmt *statement = [connection enumerateRowsInAllCollectionsStatement];
	if (statement == NULL) return;
	
	isMutated = NO; // mutation during enumeration protection
	BOOL stop = NO;
	
	// SELECT "rowid", "collection", "key", "data", "metadata" FROM "database2" ORDER BY \"collection\" ASC;";
	//           0           1         2       3         4
	
	BOOL unlimitedObjectCacheLimit = (connection->objectCacheLimit == 0);
	BOOL unlimitedMetadataCacheLimit = (connection->metadataCacheLimit == 0);
	
	int status = sqlite3_step(statement);
	if (status == SQLITE_ROW)
	{
		if (connection->needsMarkSqlLevelSharedReadLock)
			[connection markSqlLevelSharedReadLockAcquired];
		
		do
		{
			int64_t rowid = sqlite3_column_int64(statement, 0);
			
			const unsigned char *text1 = sqlite3_column_text(statement, 1);
			int textSize1 = sqlite3_column_bytes(statement, 1);
			
			const unsigned char *text2 = sqlite3_column_text(statement, 2);
			int textSize2 = sqlite3_column_bytes(statement, 2);
			
			NSString *collection, *key;
			
			collection = [[NSString alloc] initWithBytes:text1 length:textSize1 encoding:NSUTF8StringEncoding];
			key        = [[NSString alloc] initWithBytes:text2 length:textSize2 encoding:NSUTF8StringEncoding];
			
			BOOL invokeBlock = (filter == NULL) ? YES : filter(rowid, collection, key);
			if (invokeBlock)
			{
				YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				id object = [connection->objectCache objectForKey:cacheKey];
				if (object == nil)
				{
					const void *oBlob = sqlite3_column_blob(statement, 3);
					int oBlobSize = sqlite3_column_bytes(statement, 3);
					
					NSData *oData = [NSData dataWithBytesNoCopy:(void *)oBlob length:oBlobSize freeWhenDone:NO];
					object = connection->database->objectDeserializer(collection, key, oData);
					
					if (unlimitedObjectCacheLimit || [connection->objectCache count] < connection->objectCacheLimit)
					{
						if (object)
							[connection->objectCache setObject:object forKey:cacheKey];
					}
				}
				
				id metadata = [connection->metadataCache objectForKey:cacheKey];
				if (metadata)
				{
					if (metadata == [YapNull null])
						metadata = nil;
				}
				else
				{
					const void *mBlob = sqlite3_column_blob(statement, 4);
					int mBlobSize = sqlite3_column_bytes(statement, 4);
					
					if (mBlobSize > 0)
					{
						NSData *mData = [NSData dataWithBytesNoCopy:(void *)mBlob length:mBlobSize freeWhenDone:NO];
						metadata = connection->database->metadataDeserializer(collection, key, mData);
					}
					
					if (unlimitedMetadataCacheLimit ||
					    [connection->metadataCache count] < connection->metadataCacheLimit)
					{
						if (metadata)
							[connection->metadataCache setObject:metadata forKey:cacheKey];
						else
							[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
					}
				}
				
				block(rowid, collection, key, object, metadata, &stop);
				
				if (stop || isMutated) break;
			}
			
		} while ((status = sqlite3_step(statement)) == SQLITE_ROW);
	}
	
	if ((status != SQLITE_DONE) && !stop && !isMutated)
	{
		YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (isMutated && !stop)
	{
		@throw [self mutationDuringEnumerationException];
	}
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapCollectionsDatabaseReadWriteTransaction

#pragma mark Primitive

- (void)setPrimitiveData:(NSData *)primitiveData forKey:(NSString *)key inCollection:(NSString *)collection
{
	[self setPrimitiveData:primitiveData forKey:key inCollection:collection withPrimitiveMetadata:nil];
}

- (void)setPrimitiveData:(NSData *)primitiveData
                  forKey:(NSString *)key
            inCollection:(NSString *)collection
   withPrimitiveMetadata:(NSData *)primitiveMetadata
{
	if (primitiveData == nil)
	{
		[self removeObjectForKey:key inCollection:collection];
		return;
	}
	
	if (key == nil) return;
	if (collection == nil) collection = @"";
	
	BOOL found = NO;
	int64_t rowid = 0;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	
	if (YES) // fetch rowid for key
	{
		sqlite3_stmt *statement = [connection getRowidForKeyStatement];
		if (statement == NULL) {
			FreeYapDatabaseString(&_collection);
			FreeYapDatabaseString(&_key);
			return;
		}
		
		// SELECT "rowid" FROM "database2" WHERE "collection" = ? AND "key" = ?;
		
		sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
		sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			rowid = sqlite3_column_int64(statement, 0);
			found = YES;
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"Error executing 'getRowidForKeyStatement': %d %s, key(%@)",
			            status, sqlite3_errmsg(connection->db), key);
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	
	BOOL set = YES;
	
	if (found) // update data for key
	{
		sqlite3_stmt *statement = [connection updateAllForRowidStatement];
		if (statement == NULL) {
			FreeYapDatabaseString(&_collection);
			FreeYapDatabaseString(&_key);
			return;
		}
		
		// UPDATE "database2" SET "data" = ?, "metadata" = ? WHERE "rowid" = ?;
		
		sqlite3_bind_blob(statement, 1, primitiveData.bytes, (int)primitiveData.length, SQLITE_STATIC);
		sqlite3_bind_blob(statement, 2, primitiveMetadata.bytes, (int)primitiveMetadata.length, SQLITE_STATIC);
		
		sqlite3_bind_int64(statement, 3, rowid);
		
		int status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"Error executing 'updateAllForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
			set = NO;
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	else // insert data for key
	{
		sqlite3_stmt *statement = [connection insertForRowidStatement];
		if (statement == NULL) {
			FreeYapDatabaseString(&_collection);
			FreeYapDatabaseString(&_key);
			return;
		}
		
		// INSERT INTO "database2" ("collection", "key", "data", "metadata") VALUES (?, ?, ?, ?);
		
		sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
		sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
		
		sqlite3_bind_blob(statement, 3, primitiveData.bytes, (int)primitiveData.length, SQLITE_STATIC);
		sqlite3_bind_blob(statement, 4, primitiveMetadata.bytes, (int)primitiveMetadata.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_DONE)
		{
			rowid = sqlite3_last_insert_rowid(connection->db);
		}
		else
		{
			YDBLogError(@"Error executing 'insertForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
			set = NO;
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	
	FreeYapDatabaseString(&_collection);
	FreeYapDatabaseString(&_key);
	
	if (!set) return;
	
	connection->hasDiskChanges = YES;
	isMutated = YES;  // mutation during enumeration protection
	
	if (found)
	{
		YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
		
		[connection->objectCache removeObjectForKey:cacheKey];
		[connection->objectChanges setObject:[YapNull null] forKey:cacheKey];
		
		[connection->metadataCache removeObjectForKey:cacheKey];
		[connection->metadataChanges setObject:[YapNull null] forKey:cacheKey];
		
		[[self extensions] enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
			
			__unsafe_unretained id <YapAbstractDatabaseExtensionTransaction_CollectionKeyValue>
			    extTransaction = extTransactionObj;
			
			[extTransaction handleRemoveObjectForKey:cacheKey.key        // mutable string protection
										inCollection:cacheKey.collection // mutable string protection
										   withRowid:rowid];
		}];
	}
}

- (void)setPrimitiveMetadata:(NSData *)primitiveMetadata forKey:(NSString *)key inCollection:(NSString *)collection
{
	if (collection == nil) collection = @"";
	
	int64_t rowid = 0;
	if (![self getRowid:&rowid forKey:key inCollection:collection]) return;
	
	sqlite3_stmt *statement = [connection updateMetadataForRowidStatement];
	if (statement == NULL) return;
	
	// UPDATE "database2" SET "metadata" = ? WHERE "rowid" = ?;
	//
	// To use SQLITE_STATIC on our data blob, we use the objc_precise_lifetime attribute.
	// This ensures the data isn't released until it goes out of scope.
	
	sqlite3_bind_blob(statement, 1, primitiveMetadata.bytes, (int)primitiveMetadata.length, SQLITE_STATIC);
	sqlite3_bind_int64(statement, 2, rowid);
	
	BOOL updated = YES;
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'updateMetadataForRowidStatement': %d %s",
					status, sqlite3_errmsg(connection->db));
		updated = NO;
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (!updated) return;
	
	connection->hasDiskChanges = YES;
	isMutated = YES;  // mutation during enumeration protection
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	[connection->metadataCache removeObjectForKey:cacheKey];
	[connection->metadataChanges setObject:[YapNull null] forKey:cacheKey];
	
	[[self extensions] enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
		
		__unsafe_unretained id <YapAbstractDatabaseExtensionTransaction_CollectionKeyValue>
		extTransaction = extTransactionObj;
		
		[extTransaction handleUpdateMetadata:nil
		                              forKey:cacheKey.key        // mutable string protection
		                        inCollection:cacheKey.collection // mutable string protection
		                           withRowid:rowid];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Object & Metadata
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection
{
	[self setObject:object forKey:key inCollection:collection withMetadata:nil];
}

- (void)setObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection withMetadata:(id)metadata
{
	if (object == nil)
	{
		[self removeObjectForKey:key inCollection:collection];
		return;
	}
	
	if (key == nil) return;
	if (collection == nil) collection = @"";
	
	if (connection->database->objectSanitizer)
	{
		object = connection->database->objectSanitizer(collection, key, object);
		if (object == nil)
		{
			YDBLogWarn(@"Object sanitizer returned nil for key(%@) object: %@", key, object);
			
			[self removeObjectForKey:key inCollection:collection];
			return;
		}
	}
	if (metadata && connection->database->metadataSanitizer)
	{
		metadata = connection->database->metadataSanitizer(collection, key, metadata);
		if (metadata == nil)
		{
			YDBLogWarn(@"Metadata sanitizer returned nil for key(%@) metadata: %@", key, metadata);
		}
	}
	
	BOOL found = NO;
	int64_t rowid = 0;
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	YapDatabaseString _key; MakeYapDatabaseString(&_key, key);
	
	if (YES) // fetch rowid for key
	{
		sqlite3_stmt *statement = [connection getRowidForKeyStatement];
		if (statement == NULL) {
			FreeYapDatabaseString(&_collection);
			FreeYapDatabaseString(&_key);
			return;
		}
		
		// SELECT "rowid" FROM "database2" WHERE "collection" = ? AND "key" = ?;
		
		sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
		sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_ROW)
		{
			rowid = sqlite3_column_int64(statement, 0);
			found = YES;
		}
		else if (status == SQLITE_ERROR)
		{
			YDBLogError(@"Error executing 'getRowidForKeyStatement': %d %s, key(%@)",
			            status, sqlite3_errmsg(connection->db), key);
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	
	BOOL set = YES;
	
	if (found) // update data for key
	{
		sqlite3_stmt *statement = [connection updateAllForRowidStatement];
		if (statement == NULL) {
			FreeYapDatabaseString(&_collection);
			FreeYapDatabaseString(&_key);
			return;
		}
		
		// UPDATE "database2" SET "data" = ?, "metadata" = ? WHERE "rowid" = ?;
		// 
		// To use SQLITE_STATIC on our data blob, we use the objc_precise_lifetime attribute.
		// This ensures the data isn't released until it goes out of scope.
		
		__attribute__((objc_precise_lifetime)) NSData *rawData =
		    connection->database->objectSerializer(collection, key, object);
		sqlite3_bind_blob(statement, 1, rawData.bytes, (int)rawData.length, SQLITE_STATIC);
		
		__attribute__((objc_precise_lifetime)) NSData *rawMeta =
		    metadata ? connection->database->metadataSerializer(collection, key, metadata) : nil;
		sqlite3_bind_blob(statement, 2, rawMeta.bytes, (int)rawMeta.length, SQLITE_STATIC);
		
		sqlite3_bind_int64(statement, 3, rowid);
		
		int status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"Error executing 'updateAllForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
			set = NO;
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	else // insert data for key
	{
		sqlite3_stmt *statement = [connection insertForRowidStatement];
		if (statement == NULL) {
			FreeYapDatabaseString(&_collection);
			FreeYapDatabaseString(&_key);
			return;
		}
		
		// INSERT INTO "database2" ("collection", "key", "data", "metadata") VALUES (?, ?, ?, ?);
		//
		// To use SQLITE_STATIC on our data blob, we use the objc_precise_lifetime attribute.
		// This ensures the data isn't released until it goes out of scope.
		
		sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
		sqlite3_bind_text(statement, 2, _key.str, _key.length, SQLITE_STATIC);
		
		__attribute__((objc_precise_lifetime)) NSData *rawData =
		    connection->database->objectSerializer(collection, key, object);
		sqlite3_bind_blob(statement, 3, rawData.bytes, (int)rawData.length, SQLITE_STATIC);
		
		__attribute__((objc_precise_lifetime)) NSData *rawMeta =
		    metadata ? connection->database->metadataSerializer(collection, key, metadata) : nil;
		sqlite3_bind_blob(statement, 4, rawMeta.bytes, (int)rawMeta.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status == SQLITE_DONE)
		{
			rowid = sqlite3_last_insert_rowid(connection->db);
		}
		else
		{
			YDBLogError(@"Error executing 'insertForRowidStatement': %d %s", status, sqlite3_errmsg(connection->db));
			set = NO;
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
	}
	
	FreeYapDatabaseString(&_collection);
	FreeYapDatabaseString(&_key);
	
	if (!set) return;
	
	connection->hasDiskChanges = YES;
	isMutated = YES;  // mutation during enumeration protection
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	id _object = nil;
	if (connection->objectPolicy == YapDatabasePolicyContainment) {
		_object = [YapNull null];
	}
	else if (connection->objectPolicy == YapDatabasePolicyShare) {
		_object = object;
	}
	else // if (connection->objectPolicy == YapDatabasePolicyCopy)
	{
		if ([object conformsToProtocol:@protocol(NSCopying)])
			_object = [object copy];
		else
			_object = [YapNull null];
	}
	
	[connection->objectCache setObject:object forKey:cacheKey];
	[connection->objectChanges setObject:_object forKey:cacheKey];
	
	if (metadata)
	{
		id _metadata = nil;
		if (connection->metadataPolicy == YapDatabasePolicyContainment) {
			_metadata = [YapNull null];
		}
		else if (connection->metadataPolicy == YapDatabasePolicyShare) {
			_metadata = metadata;
		}
		else // if (connection->metadataPolicy = YapDatabasePolicyCopy)
		{
			if ([metadata conformsToProtocol:@protocol(NSCopying)])
				_metadata = [metadata copy];
			else
				_metadata = [YapNull null];
		}
		
		[connection->metadataCache setObject:metadata forKey:cacheKey];
		[connection->metadataChanges setObject:_metadata forKey:cacheKey];
	}
	else
	{
		[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
		[connection->metadataChanges setObject:[YapNull null] forKey:cacheKey];
	}
	
	[[self extensions] enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
		
		__unsafe_unretained id <YapAbstractDatabaseExtensionTransaction_CollectionKeyValue>
		    extTransaction = extTransactionObj;

		if (found)
			[extTransaction handleUpdateObject:object
			                            forKey:cacheKey.key        // mutable string protection
			                      inCollection:cacheKey.collection // mutable string protection
			                      withMetadata:metadata
			                             rowid:rowid];
		else
			[extTransaction handleInsertObject:object
			                            forKey:cacheKey.key        // mutable string protection
			                      inCollection:cacheKey.collection // mutable string protection
			                      withMetadata:metadata
			                             rowid:rowid];
	}];
}

- (void)setMetadata:(id)metadata forKey:(NSString *)key inCollection:(NSString *)collection
{
	if (collection == nil) collection = @"";
	
	int64_t rowid = 0;
	if (![self getRowid:&rowid forKey:key inCollection:collection]) return;
	
	if (metadata && connection->database->metadataSanitizer)
	{
		metadata = connection->database->metadataSanitizer(collection, key, metadata);
		if (metadata == nil)
		{
			YDBLogWarn(@"Metadata sanitizer returned nil for key: %@", key);
		}
	}
	
	sqlite3_stmt *statement = [connection updateMetadataForRowidStatement];
	if (statement == NULL) return;
	
	// UPDATE "database2" SET "metadata" = ? WHERE "rowid" = ?;
	//
	// To use SQLITE_STATIC on our data blob, we use the objc_precise_lifetime attribute.
	// This ensures the data isn't released until it goes out of scope.
	
	__attribute__((objc_precise_lifetime)) NSData *rawMeta =
	    metadata ? connection->database->metadataSerializer(collection, key, metadata) : nil;
	sqlite3_bind_blob(statement, 1, rawMeta.bytes, (int)rawMeta.length, SQLITE_STATIC);
	
	sqlite3_bind_int64(statement, 2, rowid);
	
	BOOL updated = YES;
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'updateMetadataForRowidStatement': %d %s",
		                                                    status, sqlite3_errmsg(connection->db));
		updated = NO;
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (!updated) return;
	
	connection->hasDiskChanges = YES;
	isMutated = YES;  // mutation during enumeration protection
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	if (metadata)
	{
		id _metadata = nil;
		if (connection->metadataPolicy == YapDatabasePolicyContainment) {
			_metadata = [YapNull null];
		}
		else if (connection->metadataPolicy == YapDatabasePolicyShare) {
			_metadata = metadata;
		}
		else // if (connection->metadataPolicy = YapDatabasePolicyCopy)
		{
			if ([metadata conformsToProtocol:@protocol(NSCopying)])
				_metadata = [metadata copy];
			else
				_metadata = [YapNull null];
		}
		
		[connection->metadataCache setObject:metadata forKey:cacheKey];
		[connection->metadataChanges setObject:_metadata forKey:cacheKey];
	}
	else
	{
		[connection->metadataCache setObject:[YapNull null] forKey:cacheKey];
		[connection->metadataChanges setObject:[YapNull null] forKey:cacheKey];
	}
	
	[[self extensions] enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
		
		__unsafe_unretained id <YapAbstractDatabaseExtensionTransaction_CollectionKeyValue>
		    extTransaction = extTransactionObj;

		[extTransaction handleUpdateMetadata:metadata
		                              forKey:cacheKey.key        // mutable string protection
		                        inCollection:cacheKey.collection // mutable string protection
		                           withRowid:rowid];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Touch
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)touchObjectForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (collection == nil) collection = @"";
	
	int64_t rowid = 0;
	if (![self getRowid:&rowid forKey:key inCollection:collection]) return;
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	if ([connection->objectChanges objectForKey:cacheKey] == nil)
		[connection->objectChanges setObject:[YapTouch touch] forKey:cacheKey];
	
	if ([connection->metadataChanges objectForKey:cacheKey] == nil)
		[connection->metadataChanges setObject:[YapTouch touch] forKey:cacheKey];
	
	[[self extensions] enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
		
		__unsafe_unretained id <YapAbstractDatabaseExtensionTransaction_CollectionKeyValue>
		    extTransaction = extTransactionObj;

		[extTransaction handleTouchObjectForKey:cacheKey.key        // mutable string protection
			                       inCollection:cacheKey.collection // mutable string protection
			                       withRowid:rowid];
	}];
}

- (void)touchMetadataForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (collection == nil) collection = @"";
	
	int64_t rowid = 0;
	if (![self getRowid:&rowid forKey:key inCollection:collection]) return;
	
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	if ([connection->metadataChanges objectForKey:cacheKey] == nil)
		[connection->metadataChanges setObject:[YapTouch touch] forKey:cacheKey];
	
	[[self extensions] enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
		
		__unsafe_unretained id <YapAbstractDatabaseExtensionTransaction_CollectionKeyValue>
		    extTransaction = extTransactionObj;

		[extTransaction handleTouchMetadataForKey:cacheKey.key        // mutable string protection
			                         inCollection:cacheKey.collection // mutable string protection
			                            withRowid:rowid];
	}];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Remove
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)removeObjectForKey:(NSString *)key inCollection:(NSString *)collection
{
	if (collection == nil) collection = @"";
	
	int64_t rowid = 0;
	if (![self getRowid:&rowid forKey:key inCollection:collection]) return;
	
	sqlite3_stmt *statement = [connection removeForRowidStatement];
	if (statement == NULL) return;
	
	// DELETE FROM 'database' WHERE 'rowid' = ?;
	
	sqlite3_bind_int64(statement, 1, rowid);
	
	BOOL removed = YES;
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeForRowidStatement': %d %s, key(%@)",
		                                                   status, sqlite3_errmsg(connection->db), key);
		removed = NO;
	}
	
	sqlite3_clear_bindings(statement);
	sqlite3_reset(statement);
	
	if (!removed) return;
	
	connection->hasDiskChanges = YES;
	isMutated = YES;  // mutation during enumeration protection
	YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
	
	[connection->objectCache removeObjectForKey:cacheKey];
	[connection->metadataCache removeObjectForKey:cacheKey];
	
	[connection->objectChanges removeObjectForKey:cacheKey];
	[connection->metadataChanges removeObjectForKey:cacheKey];
	[connection->removedKeys addObject:cacheKey];
	
	[[self extensions] enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
		
		__unsafe_unretained id <YapAbstractDatabaseExtensionTransaction_CollectionKeyValue>
		    extTransaction = extTransactionObj;

		[extTransaction handleRemoveObjectForKey:cacheKey.key        // mutable string protection
		                            inCollection:cacheKey.collection // mutable string protection
		                               withRowid:rowid];
	}];
}

- (void)removeObjectsForKeys:(NSArray *)keys inCollection:(NSString *)collection
{
	NSUInteger keysCount = [keys count];
	
	if (keysCount == 0) return;
	if (keysCount == 1) {
		[self removeObjectForKey:[keys objectAtIndex:0] inCollection:collection];
		return;
	}
	
	if (collection == nil)
		collection = @"";
	else
		collection = [collection copy]; // mutable string protection
	
	NSMutableArray *foundKeys = nil;
	NSMutableArray *foundRowids = nil;
	
	// Sqlite has an upper bound on the number of host parameters that may be used in a single query.
	// We need to watch out for this in case a large array of keys is passed.
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(connection->db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	
	// Loop over the keys, and remove them in big batches.
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	
	NSUInteger keysIndex = 0;
	do
	{
		NSUInteger left = keysCount - keysIndex;
		NSUInteger numKeyParams = MIN(left, (maxHostParams-1)); // minus 1 for collectionParam
		
		if (foundKeys == nil)
		{
			foundKeys   = [NSMutableArray arrayWithCapacity:numKeyParams];
			foundRowids = [NSMutableArray arrayWithCapacity:numKeyParams];
		}
		else
		{
			[foundKeys removeAllObjects];
			[foundRowids removeAllObjects];
		}
		
		// Find rowids for keys
		
		if (YES)
		{
			// SELECT "key", "rowid" FROM "database2" WHERE "collection" = ? AND "key" IN (?, ?, ...);
		
			NSUInteger capacity = 100 + (numKeyParams * 3);
			NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
			
			[query appendString:
			    @"SELECT \"key\", \"rowid\" FROM \"database2\" WHERE \"collection\" = ? AND \"key\" IN ("];
			
			NSUInteger i;
			for (i = 0; i < numKeyParams; i++)
			{
				if (i == 0)
					[query appendFormat:@"?"];
				else
					[query appendFormat:@", ?"];
			}
			
			[query appendString:@");"];
			
			sqlite3_stmt *statement;
			
			int status = sqlite3_prepare_v2(connection->db, [query UTF8String], -1, &statement, NULL);
			if (status != SQLITE_OK)
			{
				YDBLogError(@"Error creating 'removeKeys:inCollection:' statement (A): %d %s",
				                                                              status, sqlite3_errmsg(connection->db));
				FreeYapDatabaseString(&_collection);
				return;
			}
			
			sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
			
			for (i = 0; i < numKeyParams; i++)
			{
				NSString *key = [keys objectAtIndex:(keysIndex + i)];
				sqlite3_bind_text(statement, (int)(i + 2), [key UTF8String], -1, SQLITE_TRANSIENT);
			}
			
			while ((status = sqlite3_step(statement)) == SQLITE_ROW)
			{
				const unsigned char *text = sqlite3_column_text(statement, 0);
				int textSize = sqlite3_column_bytes(statement, 0);
				
				int64_t rowid = sqlite3_column_int64(statement, 1);
				
				NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				
				[foundKeys addObject:key];
				[foundRowids addObject:@(rowid)];
			}
			
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"Error executing 'removeKeys:inCollection:' statement (A): %d %s",
				                                                               status, sqlite3_errmsg(connection->db));
			}
			
			sqlite3_finalize(statement);
			statement = NULL;
		}
		
		// Now remove all the matching rows
		
		NSUInteger foundCount = [foundRowids count];
		
		if (foundCount > 0)
		{
			// DELETE FROM "database2" WHERE "rowid" in (?, ?, ...);
			
			NSUInteger capacity = 50 + (foundCount * 3);
			NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
			
			[query appendString:@"DELETE FROM \"database2\" WHERE \"rowid\" IN ("];
			
			NSUInteger i;
			for (i = 0; i < foundCount; i++)
			{
				if (i == 0)
					[query appendFormat:@"?"];
				else
					[query appendFormat:@", ?"];
			}
			
			[query appendString:@");"];
			
			sqlite3_stmt *statement;
			
			int status = sqlite3_prepare_v2(connection->db, [query UTF8String], -1, &statement, NULL);
			if (status != SQLITE_OK)
			{
				YDBLogError(@"Error creating 'removeKeys:inCollection:' statement (B): %d %s",
							status, sqlite3_errmsg(connection->db));
				return;
			}
			
			for (i = 0; i < foundCount; i++)
			{
				int64_t rowid = [[foundRowids objectAtIndex:i] longLongValue];
				
				sqlite3_bind_int64(statement, (int)(i + 1), rowid);
			}
			
			status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"Error executing 'removeKeys:inCollection:' statement (B): %d %s",
							status, sqlite3_errmsg(connection->db));
			}
			
			sqlite3_finalize(statement);
			statement = NULL;
			
			connection->hasDiskChanges = YES;
			isMutated = YES;  // mutation during enumeration protection
			
			for (NSString *key in foundKeys)
			{
				YapCollectionKey *cacheKey = [[YapCollectionKey alloc] initWithCollection:collection key:key];
				
				[connection->objectCache removeObjectForKey:cacheKey];
				[connection->metadataCache removeObjectForKey:cacheKey];
				
				[connection->objectChanges removeObjectForKey:cacheKey];
				[connection->metadataChanges removeObjectForKey:cacheKey];
				[connection->removedKeys addObject:cacheKey];
			}
			
			[[self extensions] enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
				
				__unsafe_unretained id <YapAbstractDatabaseExtensionTransaction_CollectionKeyValue> extTransaction;
				    extTransaction = extTransactionObj;
				
				[extTransaction handleRemoveObjectsForKeys:foundKeys inCollection:collection withRowids:foundRowids];
			}];
			
		}
		
		// Move on to the next batch (if there's more)
		
		keysIndex += numKeyParams;
		
	} while (keysIndex < keysCount);
	
	
	FreeYapDatabaseString(&_collection);
}

- (void)removeAllObjectsInCollection:(NSString *)collection
{
	if (collection == nil)
		collection  = @"";
	else
		collection = [collection copy]; // mutable string protection
	
	// Purge the caches and changesets
	
	NSMutableArray *keysToRemove = [NSMutableArray array];
	
	void(^block)(id, BOOL*) = ^void (id key, BOOL *stop) {
		
		__unsafe_unretained YapCollectionKey *cacheKey = (YapCollectionKey *)key;
		if ([cacheKey.collection isEqualToString:collection])
		{
			[keysToRemove addObject:cacheKey];
		}
	};
	
	[connection->objectCache enumerateKeysWithBlock:block];
	[connection->objectCache removeObjectsForKeys:keysToRemove];
	
	[keysToRemove removeAllObjects];
	
	for (id key in [connection->objectChanges keyEnumerator]) {
		block(key, NULL);
	}
	[connection->objectChanges removeObjectsForKeys:keysToRemove];
	
	[keysToRemove removeAllObjects];
	
	[connection->metadataCache enumerateKeysWithBlock:block];
	[connection->metadataCache removeObjectsForKeys:keysToRemove];
	
	[keysToRemove removeAllObjects];
	
	for (id key in [connection->metadataChanges keyEnumerator]) {
		block(key, NULL);
	}
	[connection->metadataChanges removeObjectsForKeys:keysToRemove];
	
	[connection->removedCollections addObject:collection];
	
	// If there are no active extensions we can take a shortcut
	
	if ([[self extensions] count] == 0)
	{
		sqlite3_stmt *statement = [connection removeCollectionStatement];
		if (statement == NULL) return;
	
		// DELETE FROM "database2" WHERE "collection" = ?;
		
		YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
		sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
		
		int status = sqlite3_step(statement);
		if (status != SQLITE_DONE)
		{
			YDBLogError(@"Error executing 'removeCollectionStatement': %d %s, collection(%@)",
			                                                       status, sqlite3_errmsg(connection->db), collection);
		}
		
		sqlite3_clear_bindings(statement);
		sqlite3_reset(statement);
		FreeYapDatabaseString(&_collection);
		
		connection->hasDiskChanges = YES;
		isMutated = YES;  // mutation during enumeration protection
		
		return;
	} // end shortcut
	
	
	NSUInteger left = [self numberOfKeysInCollection:collection];
	
	NSMutableArray *foundKeys = nil;
	NSMutableArray *foundRowids = nil;
	
	// Sqlite has an upper bound on the number of host parameters that may be used in a single query.
	// We need to watch out for this in case a large array of keys is passed.
	
	NSUInteger maxHostParams = (NSUInteger) sqlite3_limit(connection->db, SQLITE_LIMIT_VARIABLE_NUMBER, -1);
	
	// Loop over the keys, and remove them in big batches.
	
	YapDatabaseString _collection; MakeYapDatabaseString(&_collection, collection);
	
	do
	{
		NSUInteger numKeyParams = MIN(left, maxHostParams-1); // minus 1 for collectionParam
		
		if (foundKeys == nil)
		{
			foundKeys   = [NSMutableArray arrayWithCapacity:numKeyParams];
			foundRowids = [NSMutableArray arrayWithCapacity:numKeyParams];
		}
		else
		{
			[foundKeys removeAllObjects];
			[foundRowids removeAllObjects];
		}
		
		NSUInteger foundCount = 0;
		
		// Find rowids for keys
		
		if (YES)
		{
			sqlite3_stmt *statement = [connection enumerateKeysInCollectionStatement];
			if (statement == NULL) {
				FreeYapDatabaseString(&_collection);
				return;
			}
			
			// SELECT "rowid", "key" FROM "database2" WHERE collection = ?;
			
			sqlite3_bind_text(statement, 1, _collection.str, _collection.length, SQLITE_STATIC);
			
			int status;
			while ((status = sqlite3_step(statement)) == SQLITE_ROW)
			{
				int64_t rowid = sqlite3_column_int64(statement, 0);
				
				const unsigned char *text = sqlite3_column_text(statement, 1);
				int textSize = sqlite3_column_bytes(statement, 1);
				
				NSString *key = [[NSString alloc] initWithBytes:text length:textSize encoding:NSUTF8StringEncoding];
				
				[foundKeys addObject:key];
				[foundRowids addObject:@(rowid)];
				
				if (++foundCount >= numKeyParams)
				{
					break;
				}
			}
			
			if ((foundCount < numKeyParams) && (status != SQLITE_DONE))
			{
				YDBLogError(@"%@ - sqlite_step error: %d %s", THIS_METHOD, status, sqlite3_errmsg(connection->db));
			}
			
			sqlite3_clear_bindings(statement);
			sqlite3_reset(statement);
		}
		
		// Now remove all the matching rows
		
		if (foundCount > 0)
		{
			// DELETE FROM "database2" WHERE "rowid" in (?, ?, ...);
			
			NSUInteger capacity = 50 + (foundCount * 3);
			NSMutableString *query = [NSMutableString stringWithCapacity:capacity];
			
			[query appendString:@"DELETE FROM \"database2\" WHERE \"rowid\" IN ("];
			
			NSUInteger i;
			for (i = 0; i < foundCount; i++)
			{
				if (i == 0)
					[query appendFormat:@"?"];
				else
					[query appendFormat:@", ?"];
			}
			
			[query appendString:@");"];
			
			sqlite3_stmt *statement;
			
			int status = sqlite3_prepare_v2(connection->db, [query UTF8String], -1, &statement, NULL);
			if (status != SQLITE_OK)
			{
				YDBLogError(@"Error creating 'removeAllObjectsInCollection:' statement: %d %s",
				            status, sqlite3_errmsg(connection->db));
				
				FreeYapDatabaseString(&_collection);
				return;
			}
			
			for (i = 0; i < foundCount; i++)
			{
				int64_t rowid = [[foundRowids objectAtIndex:i] longLongValue];
				
				sqlite3_bind_int64(statement, (int)(i + 1), rowid);
			}
			
			status = sqlite3_step(statement);
			if (status != SQLITE_DONE)
			{
				YDBLogError(@"Error executing 'removeAllObjectsInCollection:' statement: %d %s",
				            status, sqlite3_errmsg(connection->db));
			}
			
			sqlite3_finalize(statement);
			statement = NULL;
			
			connection->hasDiskChanges = YES;
			isMutated = YES;  // mutation during enumeration protection
			
			[[self extensions] enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
				
				__unsafe_unretained id <YapAbstractDatabaseExtensionTransaction_CollectionKeyValue> extTransaction;
				    extTransaction = extTransactionObj;
				
				[extTransaction handleRemoveObjectsForKeys:foundKeys inCollection:collection withRowids:foundRowids];
			}];
		}
		
		// Move on to the next batch (if there's more)
		
		left -= foundCount;
		
	} while((left > 0) && ([foundKeys count] > 0));
	
	
	FreeYapDatabaseString(&_collection);
}

- (void)removeAllObjectsInAllCollections
{
	sqlite3_stmt *statement = [connection removeAllStatement];
	if (statement == NULL) return;
	
	int status = sqlite3_step(statement);
	if (status != SQLITE_DONE)
	{
		YDBLogError(@"Error executing 'removeAllStatement': %d %s", status, sqlite3_errmsg(connection->db));
	}
	
	sqlite3_reset(statement);
	
	connection->hasDiskChanges = YES;
	isMutated = YES;  // mutation during enumeration protection
	
	[connection->objectCache removeAllObjects];
	[connection->metadataCache removeAllObjects];
	
	[connection->objectChanges removeAllObjects];
	[connection->metadataChanges removeAllObjects];
	[connection->removedKeys removeAllObjects];
	[connection->removedCollections removeAllObjects];
	connection->allKeysRemoved = YES;
	
	[[self extensions] enumerateKeysAndObjectsUsingBlock:^(id extNameObj, id extTransactionObj, BOOL *stop) {
		
		__unsafe_unretained id <YapAbstractDatabaseExtensionTransaction_CollectionKeyValue>
		    extTransaction = extTransactionObj;
		
		[extTransaction handleRemoveAllObjectsInAllCollections];
	}];
}

@end
