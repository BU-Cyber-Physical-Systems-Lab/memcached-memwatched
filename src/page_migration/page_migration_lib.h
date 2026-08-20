#ifndef __PAGE_MIGRATION_H
#define __PAGE_MIGRATION_H

#include <unistd.h>

enum migration_engine {
    MIGRATION_ENGINE_SW = 0,
    MIGRATION_ENGINE_LOCUSTA = 1
};

struct migration_dst {
    const char *name;
    enum migration_engine engine;
    int id;
    size_t size;
};

enum migration_mode {
    MIGRATION_MODE_SYNC = 0,
    MIGRATION_MODE_SYNC_LIGHT = 1,
    MIGRATION_MODE_SYNC_NO_COPY = 2,
    MIGRATION_MODE_ASYNC = 3
};

/**
 * @brief List available migration destinations for the specified migration engine.
 * @param engine The migration engine to query.
 * @param dst_list Pointer to an array of migration_dst structures to be filled with the available destinations.
 * @param dst_count Pointer to a size_t variable that will be set to the number of available destinations.
 * @return 0 on success, or a negative error code on failure.
 */
int migration_list_destinations(enum migration_engine engine, struct migration_dst **dst_list, size_t *dst_count);

/**
 * @brief Migrate pages to the specified destination using the specified migration engine and mode.
 * @param base_addr The base address of the pages to migrate.
 * @param page_count The number of pages to migrate.
 * @param engine The migration engine to use for the migration.
 * @param dst_id The ID of the destination to migrate the pages to.
 * @param mode The migration mode to use for the migration.
 * @return 0 on success, or a negative error code on failure.
 */
int migrate_pages_to_dst(void *base_addr, size_t page_count, enum migration_engine engine, int dst_id, enum migration_mode mode);

/**
 * @brief Perform any necessary cleanup when the migration library is unloaded, the program exits or the migrated pages are freed.
 * Not calling this function if Locusta is used will result in system crashes. 
 * This function shall be called before the program exits or the migrated pages are freed.
 */
void migration_cleanup(void);

#endif