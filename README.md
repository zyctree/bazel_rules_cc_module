# rules_cc_module

bazel rules for compiling c++ 20 modules

## how to use

need to install `clang-10` and `libc++` first


in `WORKSPACE`

```python
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")

git_repository(
   name = "rules_cc_module",
   commit = "13edd4e5beeb738c09e8174263abd6c2fba1ae97",
   remote = "https://github.com/zyctree/bazel_rules_cc_module.git",
)
```

in `.bazelrc`

```python
build --repo_env=CC='clang++'
build --cxxopt='-stdlib=libc++'
build --linkopt='-lc++'

build --cxxopt='-std=c++2a'
build --cxxopt='-fmodules'
build --spawn_strategy=standalone
```

in `BUILD`

```python
load("@rules_cc_module//:tools/cc_module.bzl", "cc_module_library")

cc_module_library(
    name = "mod_a",
    srcs = [
        "partition1.cpp",
        "partition2.cpp",
    ],
    ordered_srcs = ["mod_a.cpp"],
)
```

## quick start


```shell
cd example
bazel build mod_a
bazel run src:main1
```

