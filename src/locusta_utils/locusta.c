#include "locusta.h"
#include "page_migration_lib.h"
#include <signal.h>
#include <stdio.h>
#include <string.h>

/// Signal to trigger sync migration
#define MIG_SYNC_SIG SIGRTMIN
/// Signal to trigger async migration
#define MIG_ASYNC_SIG SIGRTMIN + 2
/// Size of the migration in pages
static size_t migration_size = -1;
/// Source address of the migration
static void *migration_source = NULL;
/// destination for sync migration
static int sync_dst_id = -1;
/// destination for async migration
static int async_dst_id = -1;

/** @brief handler of the migration using locusta library
 *  @param[in] sig Signal number
 *  @param[in] info siginfo_t, unused.
 *  @param[in] ucontext userland context before signal, unused.
 */
static void locusta_handler(int sig, siginfo_t *info, void *ucontext) {
  int res, dst_id;
  enum migration_engine engine;
  enum migration_mode mode;
  if (migration_source != NULL) {
    fprintf(stderr, "ERROR: Migration source is NULL!\n");
    return;
  }
  if (migration_size <= 0) {
    fprintf(stderr, "ERROR: Invalid migration page count!\n");
    return;
  }
  // get list of destinations for migration (according to engine type)
  if (sig == MIG_SYNC_SIG) {
    mode = MIGRATION_MODE_SYNC;
    dst_id = sync_dst_id;
    engine = MIGRATION_ENGINE_SW;
  } else {
    if (sig == MIG_ASYNC_SIG) {
      mode = MIGRATION_MODE_ASYNC;
      dst_id = async_dst_id;
      engine = MIGRATION_ENGINE_LOCUSTA;
    } else {
      fprintf(stderr, "Invalid migration signal\n");
      return;
    }
    res = migrate_pages_to_dst(migration_source, migration_size, engine, dst_id,
                               mode);
    if (res < 0) {
      perror("Migration failed!");
    }
  }
}

static inline void print_destinations(struct migration_dst **dsts,
                                      size_t count) {
  int i;
  for (i = 0; i < count; i++) {
    printf("%d: %s, size: %ld\n", i, dsts[i]->name, dsts[i]->size);
  }
}

int setup_migration(void *source, size_t size) {
  int res = -1;
  struct migration_dst **sync_dsts = NULL, **async_dsts = NULL;
  size_t *sync_dsts_count = NULL, *async_dsts_count;
  sigset_t mask;
  if (source == NULL) {
    fprintf(stderr, "NULL migration destination!\n");
    return -1;
  }
  if (size == 0) {
    fprintf(stderr, "Invalid size for migration area!\n");
    return -1;
  }
  res = sigfillset(&mask);
  if (res < 0) {
    perror("Cannot fill signal mask while setting up locusta signal handler\n");
    return res;
  }
  struct sigaction locusta_action = {
      .sa_mask = mask, .sa_sigaction = locusta_handler, .sa_flags = SA_SIGINFO};
  // get syn migration destinations
  res = migration_list_destinations(MIGRATION_ENGINE_SW, sync_dsts,
                                    sync_dsts_count);
  if (res < 0) {
    perror("Cannot enumerate sync migration destiantions!");
    return res;
  }
  printf("Sync destiantions for migration:\n");
  print_destinations(sync_dsts, *sync_dsts_count);
  sync_dst_id = sync_dsts[0]->id; // select 1st software destination
  res = migration_list_destinations(MIGRATION_ENGINE_LOCUSTA, async_dsts,
                                    async_dsts_count);
  if (res < 0) {
    perror("Cannot enumerate sync migration destiantions!");
    return res;
  }
  printf("Async destinations for migration:\n");
  print_destinations(async_dsts, *async_dsts_count);
  async_dst_id = async_dsts[0]->id; // select 1st locusta destination
  res = sigaction(MIG_SYNC_SIG, &locusta_action, NULL);
  if (res < 0) {
    perror("Cannot setup locusta signal handler for sync migration\n");
  }
  res = sigaction(MIG_ASYNC_SIG, &locusta_action, NULL);
  if (res < 0) {
    perror("Cannot setup locusta signal handler for async migration\n");
  }
  migration_source = source;
  migration_size = size;
  return res;
}

void destroy_migration_handler(void) {
  int res;
  sigset_t mask;
  res = sigemptyset(&mask);
  if (res < 0) {
    perror("Cannot empty signal mask while removing up locusta signal "
           "handler\n");
  }
  res = sigaddset(&mask, MIG_ASYNC_SIG);
  if (res < 0) {
    fprintf(stderr,
            "Cannot add %s to signal mask while removing up locusta signal "
            "handler\n",
            strsignal(MIG_ASYNC_SIG));
  }
  res = sigaddset(&mask, MIG_SYNC_SIG);
  if (res < 0) {
    fprintf(stderr,
            "Cannot add %s to signal mask while removing up locusta signal "
            "handler\n",
            strsignal(MIG_SYNC_SIG));
  }
  res = sigprocmask(SIG_BLOCK, &mask, NULL);
  if (res < 0) {
    perror("Cannot block migration signals while removing up locusta signal "
           "handler\n");
  }
  migration_cleanup();
}
