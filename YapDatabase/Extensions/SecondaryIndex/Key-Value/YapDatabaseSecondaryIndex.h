#import <Foundation/Foundation.h>

#import "YapAbstractDatabaseExtension.h"

#import "YapDatabaseSecondaryIndexConnection.h"
#import "YapDatabaseSecondaryIndexTransaction.h"

#import "YapDatabaseSecondaryIndexSetup.h"

/**
 * Welcome to YapDatabase!
 *
 * https://github.com/yaptv/YapDatabase
 *
 * The project wiki has a wealth of documentation if you have any questions.
 * https://github.com/yaptv/YapDatabase/wiki
 *
 * YapDatabaseSecondaryIndex is an extension which allows you to add additional indexes.
 * That is, it allows you to create index(es) within sqlite for particular properties of your objects.
 * You can then issue queries to find or enumerate objects using the indexes. (e.g. age >= 62)
 * This allows for increased flexibility above the traditional key-value model.
**/

/**
 * The block handles extracting the column values for the secondary indexes.
 *
 * When you add or update rows in the databse the block is invoked.
 * Your block can inspect the row and determine if it contains any values that should be added to the secondary indexes.
 * If not, the  block can simply return.
 * Otherwise the block should extract any values and add them to the given dictionary.
 *
 * After the block returns, the dictionary parameter will be inspected,
 * and any set values will be automatically inserted/updated within the sqlite indexes.
 *
 * You should choose a block type that takes the minimum number of required parameters.
 * The extension can make various optimizations based on required parameters of the block.
 * For example, if metadata isn't required, then the extension can ignore metadata-only updates.
**/
typedef id YapDatabaseSecondaryIndexBlock; // One of the YapDatabaseSecondaryIndexWith_X_Block types below.

typedef void (^YapDatabaseSecondaryIndexWithKeyBlock)      \
                                        (NSMutableDictionary *dict, NSString *key);
typedef void (^YapDatabaseSecondaryIndexWithObjectBlock)   \
                                        (NSMutableDictionary *dict, NSString *key, id object);
typedef void (^YapDatabaseSecondaryIndexWithMetadataBlock) \
                                        (NSMutableDictionary *dict, NSString *key, id metadata);
typedef void (^YapDatabaseSecondaryIndexWithRowBlock)      \
                                        (NSMutableDictionary *dict, NSString *key, id object, id metadata);

/**
 * Use this enum to specify what kind of block you're passing.
**/
typedef enum {
	YapDatabaseSecondaryIndexBlockTypeWithKey       = 101,
	YapDatabaseSecondaryIndexBlockTypeWithObject    = 102,
	YapDatabaseSecondaryIndexBlockTypeWithMetadata  = 103,
	YapDatabaseSecondaryIndexBlockTypeWithRow       = 104
} YapDatabaseSecondaryIndexBlockType;


@interface YapDatabaseSecondaryIndex : YapAbstractDatabaseExtension

/* Inherited from YapAbstractDatabaseExtension

@property (nonatomic, strong, readonly) NSString *registeredName;

*/

/**
 * Creates a new secondary index extension.
 * After creation, you'll need to register the extension with the database system.
 *
 * @param setup
 * 
 *   A YapDatabaseSecondaryIndexSetup instance allows you to specify the column names and type.
 *   The column names can be whatever you want, with a few exceptions for reserved names such as "rowid".
 *   The types can reflect numbers or text.
 * 
 * @param block
 * 
 *   Pass a block that is one of the following types:
 *    - YapDatabaseSecondaryIndexWithKeyBlock
 *    - YapDatabaseSecondaryIndexWithObjectBlock
 *    - YapDatabaseSecondaryIndexWithMetadataBlock
 *    - YapDatabaseSecondaryIndexWithRowBlock
 * 
 * @param blockType
 * 
 *   Pass the blockType enum that matches the passed block.
 *
 * @see YapDatabaseSecondaryIndexSetup
 * @see YapAbstractDatabase registerExtension:withName:
**/
- (id)initWithSetup:(YapDatabaseSecondaryIndexSetup *)setup
              block:(YapDatabaseSecondaryIndexBlock)block
          blockType:(YapDatabaseSecondaryIndexBlockType)blockType;

@end
