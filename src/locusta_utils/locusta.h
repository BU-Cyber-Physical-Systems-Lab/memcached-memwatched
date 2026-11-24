#ifndef LOCUSTA_H_
#define LOCUSTA_H_
#include <stddef.h>
#include <stdint.h>

/// The base signal to use for migration
#define MIGRATION_SIGNAL SIGRTMIN
/// Signal for restarting the periodic_migration process
#define RESTART_SIGNAL SIGRTMAX
/// Number of dummy signals
#define DUMMY_SIGNALS 1
/// Max number of software migration destinations
#define SW_DSTS 4
/// Max number of software modes
#define SW_MODES 4
/// Max number of hardware migration destinations
#define HW_DSTS 3
/// Max number of hardware modes
#define HW_MODES 1

/** @brief installs a signal handler to trigger a heap migration.
 *  @param[in] source The source address for memory to migrate.
 *  @param[in] offset The migration offset;
 *  @param[in] size The size (in pages) of the memory area to migrate.
 *  @param[in] verbose The amount of logs to print (0 print only errors).
 *  @returns 0 on success, <0 on failure.
 *  @details
 *  If offset is not NULL, then a premigration to the selected memory location
 * is triggered.
 */
int setup_migration(void *source, size_t offset, size_t size,int verbose);

/// Disables the migration handler
void destroy_migration_handler(void);

/// Sync with the periodic migration tool, ensuring migrations start after setup
/// is done (requires periodic_migration to start before benchmark with -w flag)
int start_periodic_migration_tool(void);

#endif // LOCUSTA_H_
