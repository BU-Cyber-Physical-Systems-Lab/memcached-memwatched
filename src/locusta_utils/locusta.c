#include "locusta.h"
#include "page_migration_lib.h"
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>

/// Size of the migration in pages
static size_t heap_size = -1;
/// Source address of the migration
static void *migration_source = NULL;
/// destinations for sync migration
static struct migration_dst *sw_dsts;
/// Number of detected sync destinations
static size_t sw_dsts_count = 0;
/// destinations for async migration
static struct migration_dst *hw_dsts;
/// Number of detected async destinations
static size_t hw_dsts_count = 0;

/** @brief handler of the migration using locusta library
 *  @param[in] sig Signal number
 *  @param[in] info siginfo_t, unused.
 *  @param[in] ucontext userland context before signal, unused.
 */
static void locusta_handler(int sig, siginfo_t *info, void *ucontext) {
  int res;
  // our migration ID is the displacement from the base migration signal
  int signal_offset = sig - MIGRATION_SIGNAL;
  // we calculate the number of signals for software and hardware migration
  int sw_signals = SW_MODES * SW_DSTS;
  int hw_signals = HW_MODES * HW_DSTS;
  // the ID of the migration destination from struct migration_dst
  int dst_id = -1;
  // number of modes compatible for the selected destinations
  int selected_modes = 0;
  // selecting the migration engine implicitly restricts the number of
  // destinations available
  struct migration_dst *selected_dsts = NULL, selected_dst;
  size_t selected_dsts_len = 0;
  enum migration_engine engine;
  enum migration_mode mode;
  size_t migration_size = 0;
  if (migration_source != NULL) {
    fprintf(stderr, "ERROR: Migration source is NULL!\n");
    return;
  }
  if (heap_size <= 0) {
    fprintf(stderr, "ERROR: Invalid heap size page count!\n");
    return;
  }
  // get list of destinations for migration (according to engine type)

  // sw_signals + hw_signals is the last valid signal we can have for the
  // migration
  if (signal_offset > hw_signals + sw_signals) {
    fprintf(stderr, "ERROR: migration signal %lu out of range\n", heap_size);
    return;
  }
  printf("DEBUG: signal offset is %d\n", signal_offset);
  // 0 to DUMMY_SIGNALS -1 -> we fake the migration
  if (signal_offset < DUMMY_SIGNALS) {
    printf("DEBUG: selected DUMMY handler\n");
    return;
  } else {
    signal_offset -= DUMMY_SIGNALS;
    // DUMMY_SIGNALS to sw_signals -1 -> software migration
    if (signal_offset < sw_signals) {
      selected_dsts = sw_dsts;
      selected_dsts_len = sw_dsts_count;
      selected_modes = SW_MODES;
      engine = MIGRATION_ENGINE_SW;
      switch (signal_offset % selected_modes) {
      case 0:
        printf("DEBUG: selected SW SYNC migration\n");
        mode = MIGRATION_MODE_SYNC;
        break;
      case 1:
        printf("DEBUG: selected SW SYNC LIGHT migration\n");
        mode = MIGRATION_MODE_SYNC_LIGHT;
        break;
      case 2:
        printf("DEBUG: selected SW SYNC NO COPY migration\n");
        mode = MIGRATION_MODE_SYNC_NO_COPY;
        break;
      default:
        fprintf(stderr,
                "ERROR: %d is an invalid migration mode for SW engine!\n",
                signal_offset % selected_modes);
        return;
      }
    } else {
      signal_offset -= sw_signals;
      // sw_signals to hw_signals -1 -> hardware migration
      if (signal_offset < hw_signals) {
        selected_modes = HW_MODES;
        selected_dsts = hw_dsts;
        selected_dsts_len = hw_dsts_count;
        engine = MIGRATION_ENGINE_LOCUSTA;
        switch (signal_offset % selected_modes) {
        case 0:
          printf("DEBUG: selected HW ASYNC migration\n");
          mode = MIGRATION_MODE_ASYNC;
          break;
        default:
          fprintf(
              stderr,
              "ERROR: %d is an invalid migration mode for Locusta engine!\n",
              signal_offset % selected_modes);
          return;
        }
      } else {
        fprintf(stderr, "ERROR: Offset %d is out of range for migration!\n",
                sig - MIGRATION_SIGNAL);
        return;
      }
    }
  }
  // now select the destination according to which engine and mode is encoded in
  // the signal offset
  if (signal_offset / selected_modes < selected_dsts_len) {
    selected_dst = selected_dsts[signal_offset % selected_modes];
    dst_id = selected_dst.id;
    // adjust the migration size accordingly with the size of the destination
    if (selected_dst.size > 0 && selected_dst.size < heap_size) {
      migration_size = selected_dst.size - 1;
    } else {
      migration_size = heap_size - 1;
    }
  } else {
    fprintf(stderr, "ERROR: Invalid migration destination for mode %d\n", mode);
    return;
  }
  printf("DEBUG: migrating pages to destination %d with size %lu\n", dst_id,
         migration_size);
  res = migrate_pages_to_dst(migration_source, migration_size, engine, dst_id,
                             mode);
  if (res < 0) {
    fprintf(stderr, "ERROR: Migration failed!\n");
  }
}

static inline void print_destinations(struct migration_dst *dsts,
                                      size_t count) {
  int i;
  printf("Found %lu destinations: \n", count);
  for (i = 0; i < count; i++) {
    printf("\t %d: %s, size: %ld\n", i, dsts[i].name, dsts[i].size);
  }
}

int setup_migration(void *source, size_t size) {
  int res = -1;
  sigset_t mask;
  if (source == NULL) {
    fprintf(stderr, "ERROR: NULL migration destination!\n");
    return -1;
  }
  if (size == 0) {
    fprintf(stderr, "ERROR: Invalid size for migration area!\n");
    return -1;
  }
  res = sigfillset(&mask);
  if (res < 0) {
    perror("ERROR: Cannot fill signal mask while setting up locusta signal "
           "handler\n");
    return res;
  }
  struct sigaction locusta_action = {
      .sa_mask = mask, .sa_sigaction = locusta_handler, .sa_flags = SA_SIGINFO};
  // get syn migration destinations
  res = migration_list_destinations(MIGRATION_ENGINE_SW, &sw_dsts,
                                    &sw_dsts_count);
  if (res < 0) {
    fprintf(stderr, "ERROR: Cannot enumerate software migration destinations!");
    return res;
  }
  printf("SW destinations for migration:\n");
  print_destinations(sw_dsts, sw_dsts_count);
  res = migration_list_destinations(MIGRATION_ENGINE_LOCUSTA, &hw_dsts,
                                    &hw_dsts_count);
  if (res < 0) {
    fprintf(stderr, "ERROR: Cannot enumerate locusta migration destinations!");
    return res;
  }
  printf("HW destinations for migration:\n");
  print_destinations(hw_dsts, hw_dsts_count);
  printf("DEBUG: Setting up migration signals\n");
  for (int i = 0;
       i < DUMMY_SIGNALS + (SW_MODES * SW_DSTS) + (HW_MODES * HW_DSTS); i++) {
    res = sigaction(MIGRATION_SIGNAL + i, &locusta_action, NULL);
    if (res < 0) {
      fprintf(stderr,
              "ERROR: Cannot setup locusta signal handler for signal %s, %s\n",
              strsignal(MIGRATION_SIGNAL + i), strerror(errno));
    }
  }
  migration_source = source;
  heap_size = size;
  printf("DEBUG: migration setup done\n");
  return 0;
}

void destroy_migration_handler(void) {
  int res;
  sigset_t mask;
  res = sigemptyset(&mask);
  if (res < 0) {
    perror("ERROR: Cannot empty signal mask while removing up locusta signal "
           "handler\n");
  }
  for (int i = 0;
       i < DUMMY_SIGNALS + (SW_MODES * SW_DSTS) + (HW_MODES * HW_DSTS); i++) {
    res = sigaddset(&mask, MIGRATION_SIGNAL + i);
    if (res < 0) {
      fprintf(stderr,
              "ERROR: Cannot add %s to signal mask while removing up locusta "
              "signal "
              "handler, %s\n",
              strsignal(MIGRATION_SIGNAL + i), strerror(errno));
    }
  }
  res = sigprocmask(SIG_BLOCK, &mask, NULL);
  if (res < 0) {
    perror("ERROR: Cannot block migration signals while removing up locusta "
           "signal "
           "handler\n");
  }
  migration_cleanup();
}
