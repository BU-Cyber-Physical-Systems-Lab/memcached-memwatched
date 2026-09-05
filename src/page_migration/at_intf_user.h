#include "at_intf.h"

#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

int at_intf_translate(uint64_t vaddr, uint8_t write, union at_response *response);