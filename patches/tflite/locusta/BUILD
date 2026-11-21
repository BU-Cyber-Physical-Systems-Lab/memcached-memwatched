package(default_visibility = ["//visibility:public"])

cc_import(
    name = "page_migration_lib",
    static_library = "libpage_migration_lib.a",
)

cc_library(
    name = "locusta",
    srcs = [
        "locusta.c",
        "at_intf_user.c",
    ],
    hdrs = [
        "locusta.h",
        "at_intf_user.h",
        "at_intf.h",
        "page_migration_lib.h"
    ],
    deps = [
        ":page_migration_lib",
    ],
    linkopts = [
    "-lrt",
    ],
)
