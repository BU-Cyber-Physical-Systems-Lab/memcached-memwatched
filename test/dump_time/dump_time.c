#include <stdio.h>
#include <sys/time.h>

int main(void) {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  double timestamp = tv.tv_sec + (double)tv.tv_usec / 1000000;
  FILE *file = fopen("mutilate_start.log", "w");
  if (file == NULL) {
    perror("Cannot open output file");
    return -1;
  }
  fprintf(file, "%lf\n", timestamp);
  fflush(file);
  fclose(file);
  return 0;
}
