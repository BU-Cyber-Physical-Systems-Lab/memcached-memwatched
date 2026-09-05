#include "at_intf_user.h"

int at_intf_translate(uint64_t vaddr, uint8_t write, union at_response *response) {
    struct at_packet packet = {
        .request = {
            .vaddr = vaddr,
            .write = (__u8) (write ? 1 : 0),
        },
    };

    int fd = open("/dev/" AT_INTF_DEV_FILENAME, O_RDWR);
    if (fd < 0) {
        perror("open");
        return -1;
    }

    if (ioctl(fd, AT_INTF_IOC_TRANSLATE, &packet) < 0) {
        perror("ioctl");
        close(fd);
        return -1;
    }

    *response = packet.response;

    close(fd);
    return 0;
}