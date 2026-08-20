#ifndef LOCUSTA_H_
#define LOCUSTA_H_
#include <stddef.h>

/** @brief installs a signal handler to trigger a migration via locusta
 *  @param[in] source The source address for memory to migrate.
 *  @param[in] size The size (in pages) of the memory area to migrate.
 *  @returns 0 on success, <0 on failure.
 */
int setup_migration(void *source, size_t size);

/// Disables the migration handler
void destroy_migration_handler(void);

#endif // LOCUSTA_H_
