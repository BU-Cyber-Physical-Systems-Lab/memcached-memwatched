#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>

int main(int argc, char **argv) {
  char *filename = "mutilate_start.log";
  if (argc > 2) {
    fprintf(stderr, "Wrong number of argument supplied!\n");
    fprintf(stderr, "Usage: dump_time [path to output file]\n");
    return -1;
  }
  if (argc == 2) {
    filename = argv[1];
  }
  struct timeval tv;
  gettimeofday(&tv, NULL);
  double timestamp = tv.tv_sec + (double)tv.tv_usec / 1000000;
  FILE *file = fopen(filename, "w");
  if (file == NULL) {
    perror("Cannot open output file");
    return -1;
  }
  fprintf(file, "%lf\n", timestamp);
  fflush(file);
  fclose(file);
  return 0;
}
