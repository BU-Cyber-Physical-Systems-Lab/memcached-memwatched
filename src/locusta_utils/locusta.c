#include "locusta.h"
#include "page_migration_lib.h"
#include "at_intf_user.h"
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdbool.h>
#include <inttypes.h>

/// Size of the migration in pages
static size_t heap_size_pages = -1;
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
/// The amount of logs to print
static int verbose = 0;
/// `1` if a migration request is being processed, `0` otherwise.
static volatile bool migration_in_progress =false;
static volatile bool setup_done = false;

/**@brief Select destination from migration destination address.
 * @param[in] engine The from which destinations are searched.
 * @param[in] address The address to match to a destination.
 * @returns the migration destination or NULL on failure.
 */
static inline struct migration_dst *
select_dst_from_addr(enum migration_engine engine, size_t addr) {
  struct migration_dst *dsts = NULL;
  int dsts_len = 0;
  switch (engine) {
  case MIGRATION_ENGINE_LOCUSTA:
    dsts = hw_dsts;
    dsts_len = hw_dsts_count;
    break;
  case MIGRATION_ENGINE_SW:
    dsts = sw_dsts;
    dsts_len = sw_dsts_count;
    break;
  default:
    fprintf(stderr, "ERROR: Engine %d has no supported destinations!\n",
            engine);
    return NULL;
  }
  for (int i = 0; i < dsts_len; i++) {
      if (verbose > 0) {
         fprintf(stderr,"DEBUG: looking at destination %d: id %d name:%s engine %d size: %lx, start 0x%lx\n",i,dsts[i].id,dsts[i].name,dsts[i].engine,dsts[i].size,dsts[i].start);
    }
    if (dsts[i].start == addr) {
      if (verbose > 0) {
         fprintf(stderr,"DEBUG: selected destination %d, %s, id %d\n",i,dsts[i].name,dsts[i].id);
    }
      return dsts + i;
    }
  }
  return NULL;
}

/** @brief trigger a migration to selected destination with the selected engine
 * and mode
 *  @param[in] dst The selected destination.
 *  @param[in] engine The selected engine.
 *  @param[in] mode The selected mode.
 *  @return 0 on success, -1 on failure.
 */
static inline int trigger_migration(struct migration_dst dst,
                                    enum migration_engine engine,
                                    enum migration_mode mode) {
  int dst_id = -1, res;
  size_t migration_size = 0;
  bool expected_migration_status=false,desired_migration_status=true;
  union at_response response={0};
  if (!setup_done) {
    fprintf(stderr, "ERROR: Migration triggered before setup completed!\n");
    return -1;
  }
  if (migration_source == NULL) {
    fprintf(stderr, "ERROR: Migration source is NULL!\n");
    return -1;
  }
  if (heap_size_pages <= 0) {
    fprintf(stderr, "ERROR: Invalid heap size page count!\n");
    return -1;
  }
  // https://gcc.gnu.org/onlinedocs/gcc/_005f_005fatomic-Builtins.html
  if ( !__atomic_compare_exchange(&migration_in_progress,&expected_migration_status,&desired_migration_status,false,__ATOMIC_SEQ_CST,__ATOMIC_SEQ_CST)) {
    fprintf(stderr, "WARN: Another migration request is already being processed, try later\n");
    return -1;
  }
  dst_id = dst.id;
  // adjust the migration size accordingly with the size of the destination
  if (dst.size / getpagesize() > 0 &&
      dst.size / getpagesize() < heap_size_pages) {
    migration_size = (dst.size / getpagesize()) - 1;
  } else {
    migration_size = heap_size_pages - 1;
  }
  migration_size=1023;
  if(verbose>0){
    at_intf_translate((uint64_t) migration_source, 0, &response);
    if(response.success.f==0){
        fprintf(stderr,"DEBUG: VA before migration %p, PA PFN before migration: 0x%"PRIx64"\n",migration_source,(uint64_t)response.success.pa_pfn);
    }else{
      printf("WARNING: Migration check failed!\n");
    }
  }
  if (verbose > 0) {
    printf(
        "DEBUG: heap size %lu destination size %lu chosen migration size %lu\n",
        heap_size_pages, dst.size / getpagesize(), migration_size);
    fprintf(stderr,"DEBUG: migrating pages from %p to destination %d (start at 0x%lx) with "
           "size %lu\n",
           migration_source,dst_id, dst.start, migration_size);
  }
  res = migrate_pages_to_dst(migration_source, migration_size, engine, dst_id,
                             mode);
  if(verbose>0){
    at_intf_translate((uint64_t) migration_source, 0, &response);
    if(response.success.f==0){
      fprintf(stderr,"DEBUG: VA after migration %p, PA PFN after migration: 0x%"PRIx64"\n",migration_source,(uint64_t)response.success.pa_pfn);
    }else{
      printf("WARNING: Migration check failed!\n");
    }
  }
  if (res < 0) {
    fprintf(stderr, "ERROR: Migration failed!\n");
  }
  desired_migration_status=false;
  __atomic_store(&migration_in_progress,&desired_migration_status, __ATOMIC_SEQ_CST);
  return res;
}

/** @brief handler of the migration using locusta library
 *  @param[in] sig Signal number
 *  @param[in] info siginfo_t, unused.
 *  @param[in] ucontext userland context before signal, unused.
 */
static void locusta_handler(int sig, siginfo_t *info, void *ucontext) {
  // our migration ID is the displacement from the base migration signal
  int signal_offset = sig - MIGRATION_SIGNAL;
  // we calculate the number of signals for software and hardware migration
  int sw_signals = SW_MODES * SW_DSTS;
  int hw_signals = HW_MODES * HW_DSTS;
  // number of modes compatible for the selected destinations
  int selected_modes = 0;
  // selecting the migration engine implicitly restricts the number of
  // destinations available
  struct migration_dst *selected_dsts = NULL, selected_dst;
  size_t selected_dsts_len = 0;
  enum migration_engine engine;
  enum migration_mode mode;
  // get list of destinations for migration (according to engine type)

  // sw_signals + hw_signals is the last valid signal we can have for the
  // migration
  if (signal_offset > hw_signals + sw_signals) {
    fprintf(stderr, "ERROR: migration signal %lu out of range\n",
            heap_size_pages);
    return;
  }
  if (verbose > 0) {
    fprintf(stderr,"DEBUG: signal offset is %d\n", signal_offset);
  }
  // 0 to DUMMY_SIGNALS -1 -> we fake the migration
  if (signal_offset < DUMMY_SIGNALS) {
    if (verbose > 0) {
      fprintf(stderr,"DEBUG: selected DUMMY handler\n");
    }
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
        if (verbose > 0) {
          fprintf(stderr,"DEBUG: selected SW SYNC migration\n");
        }
        mode = MIGRATION_MODE_SYNC;
        break;
      case 1:
        if (verbose > 0) {
          fprintf(stderr,"DEBUG: selected SW SYNC LIGHT migration\n");
        }
        mode = MIGRATION_MODE_SYNC_LIGHT;
        break;
      case 2:
        if (verbose > 0) {
          fprintf(stderr,"DEBUG: selected SW SYNC NO COPY migration\n");
        }
        mode = MIGRATION_MODE_SYNC_NO_COPY;
        break;
      case 3:
        if (verbose > 0) {
          fprintf(stderr,"DEBUG: selected SW ASYNC migration\n");
        }
        mode = MIGRATION_MODE_ASYNC;
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
          if (verbose > 0) {
            fprintf(stderr,"DEBUG: selected HW ASYNC migration\n");
          }
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
    selected_dst = selected_dsts[signal_offset / selected_dsts_len];
    if (verbose > 0) {
    fprintf(stderr, "DEBUG: Selected destination %lu, %s id %d\n",signal_offset / selected_dsts_len,selected_dst.name,selected_dst.id);
    }
  } else {
    fprintf(stderr, "ERROR: Invalid migration destination for mode %d\n", mode);
    return;
  }
  trigger_migration(selected_dst, engine, mode);
}

static inline void print_destinations(struct migration_dst *dsts,
                                      size_t count) {
  int i;
  printf("Found %lu destinations: \n", count);
  for (i = 0; i < count; i++) {
    printf("\t %d: %s, size: %ld start: 0x%lx\n", i, dsts[i].name, dsts[i].size,
           dsts[i].start);
  }
}

int setup_migration(void *source, size_t offset, size_t size,
                    int verbose_level) {
    int res = -1;
    bool current_setup_val=false;
    int migration_signals=DUMMY_SIGNALS + (SW_MODES * SW_DSTS) + (HW_MODES * HW_DSTS);
  verbose = verbose_level;
  if (verbose > 0) {
        fprintf(stderr,"DEBUG: migration source addr %p, offset 0x%lx, size: %lu\n",source,offset,size);
  }
  __atomic_load(&setup_done,&current_setup_val,__ATOMIC_SEQ_CST);
  if (current_setup_val) {
    fprintf(stderr, "ERROR: Attempting to setup migration handler twice!\n");
    return -1;
  }
  sigset_t mask;
  if (MIGRATION_SIGNAL + migration_signals > SIGRTMAX -2 ) {
    fprintf(stderr, "ERROR: more migration signals (%d) than the ones between SIGRTMIN (%d) and SIGRTMAX (%d) (%d >+ %d)!\n",migration_signals,SIGRTMIN,SIGRTMAX,SIGRTMIN + migration_signals,SIGRTMAX);
    return -1;
  }
  if (source == NULL) {
    fprintf(stderr, "ERROR: NULL migration destination!\n");
    return -1;
  }
  if (size == 0) {
    fprintf(stderr, "ERROR: Invalid size for migration area!\n");
    return -1;
  }
  for (int i = 0; i < migration_signals; i++) {
      res = sigaddset(&mask, MIGRATION_SIGNAL+i);
  if (res < 0) {
    perror("ERROR: Cannot add migration signals to mask while setting up locusta signal "
           "handler\n");
    return res;
  }
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
  if (verbose > 0) {
    printf("SW destinations for migration:\n");
    print_destinations(sw_dsts, sw_dsts_count);
  }
  res = migration_list_destinations(MIGRATION_ENGINE_LOCUSTA, &hw_dsts,
                                    &hw_dsts_count);
  if (res < 0) {
    fprintf(stderr, "ERROR: Cannot enumerate locusta migration destinations!");
    return res;
  }
  if (verbose > 0) {
    printf("HW destinations for migration:\n");
    print_destinations(hw_dsts, hw_dsts_count);
    fprintf(stderr,"DEBUG: Setting up migration signals\n");
  }
  for (int i = 0;
       i < migration_signals; i++) {
    res = sigaction(MIGRATION_SIGNAL + i, &locusta_action, NULL);
    if (res < 0) {
      fprintf(stderr,
              "ERROR: Cannot setup locusta signal handler for signal %s, %s\n",
              strsignal(MIGRATION_SIGNAL + i), strerror(errno));
    }
  }
  migration_source = source;
  heap_size_pages = size;
  if (verbose > 0) {
    fprintf(stderr,"DEBUG: migration setup done\n");
  }
  current_setup_val=true;
  __atomic_store(&setup_done,&current_setup_val, __ATOMIC_SEQ_CST);
  if (offset > 0) {
    struct migration_dst *premigration_dst =
        //select_dst_from_addr(MIGRATION_ENGINE_SW, offset);
        sw_dsts;
    if (verbose > 0) {
      fprintf(stderr,"DEBUG: triggering premigration to 0x%lx\n", premigration_dst->start);
    }
    trigger_migration(*premigration_dst, MIGRATION_ENGINE_SW,
                      MIGRATION_MODE_SYNC);
    if (verbose > 0) {
      fprintf(stderr,"DEBUG: premigration to 0x%lx done\n", premigration_dst->start);
    }
  }
  return 0;
}

int start_periodic_migration_tool(void) {
    int res = 0;
    pid_t tool_pid=0;
    FILE *tool_pid_file=fopen("/tmp/periodic_migration","r");
    if (tool_pid_file == NULL) {
        fprintf(stderr,"/tmp/periodic_migration not found, skipping signal\n");
        return 0;
    }
    FILE *my_pid_file = fopen("/tmp/bmark_to_migrate", "w+");
    if (my_pid_file == NULL) {
        perror("cannot create /tmp/bmark_to_migrate");
        exit(-1);
    }
    fprintf(my_pid_file, "%d", getpid());
    fflush(my_pid_file);
    fclose(my_pid_file);
    res=fscanf(tool_pid_file, "%d", &tool_pid);
    fclose(tool_pid_file);
    printf("Restarting periodic migration (sending signal %d) process with PID: %d\n",RESTART_SIGNAL,tool_pid);
    res = kill(tool_pid, RESTART_SIGNAL);
    return res;
}

void destroy_migration_handler(void) {
  int res;
  sigset_t mask;
  bool current_setup_val=false;
  __atomic_load(&setup_done,&current_setup_val,__ATOMIC_SEQ_CST);
  if (!current_setup_val) {
      fprintf(stderr,"WARN: attempting to dsaible migration handler when not setup\n");
      return;
  }
  unlink("/tmp/bmark_to_migrate");
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
