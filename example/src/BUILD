load("@rules_cc_module//:tools/cc_module.bzl", "cc_module_library")


cc_module_library(
    name = "main_util",
    srcs = ["main_util.cpp"],
    deps = [":include"]
)


cc_library(
    name = "include",
    hdrs = ["include.h"],
)

cc_module_library(
    name = "_main1",
    srcs = ["main1.cpp"],
    deps = [":main_util", ]
)

cc_binary(
    name = "main1",
    deps = [":_main1"],
)

