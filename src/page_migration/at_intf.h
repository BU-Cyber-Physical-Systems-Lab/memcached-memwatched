#ifndef _AT_UAPI_H
#define _AT_UAPI_H

#ifdef __KERNEL__
#include <linux/types.h>
#include <linux/ioctl.h>
#else
#include <stdint.h>
#include <linux/types.h>
#include <sys/ioctl.h>
#endif

union at_response {
    struct {
        __u64 f : 1; // aborted
        __u64 fst : 6; // fault status
        __u64 res0_0 : 1;
        __u64 pwt : 1; 
        __u64 s : 1;
        __u64 reserved : 54;
    } failure;

    struct {
        __u64 f : 1; // not aborted
        __u64 res_0 : 6;
        __u64 sh : 2;
        __u64 ns : 1;
        __u64 res_1 : 2;
        __u64 pa_pfn : 40;
        __u64 res_2 : 4;
        __u64 attr : 8;
    } success;

    struct {
        __u64 aborted : 1;  // 1 if the access would abort, 0 otherwise
        __u64 padding : 63; // physical address (if not aborted)
    } check;

    __u64 raw;

};

struct at_packet {
    struct {
        __u64 vaddr;      /* in: user VA to translate */
        __u8  write;      /* in: 1 = check as a write access, 0 = read */
    } request;

    union at_response response; /* out: result of the translation */
};

#define AT_INTF_IOC_MAGIC     'A'
#define AT_INTF_IOC_TRANSLATE _IOWR(AT_INTF_IOC_MAGIC, 1, struct at_packet)
#define AT_INTF_DEV_FILENAME  "at_intf"

#endif /* _AT_UAPI_H */