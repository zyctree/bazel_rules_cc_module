# load("//:bazel/printer.bzl", "printer")
load(
    "@rules_cc//cc:action_names.bzl",
    "CPP_COMPILE_ACTION_NAME",
    "CPP_LINK_STATIC_LIBRARY_ACTION_NAME",
    "CPP_MODULE_CODEGEN_ACTION_NAME",
    "CPP_MODULE_COMPILE_ACTION_NAME",
)
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load("@bazel_tools//tools/cpp:cc_flags_supplier.bzl", "cc_flags_supplier")
load("@rules_cc//cc:defs.bzl", "cc_library", "cc_toolchain", "cc_toolchain_suite")

CXX = "clang++ -std=c++2a -fmodules"

ModuleInfo = provider(
    fields = {
        "transitive_pcms": "module files' path",
        "transitive_srcs": "sources files' path",
    },
)

def _get_cc_info(ctx, deps):
    attr = ctx.attr
    compilation_context = cc_common.create_compilation_context(
        defines = depset(attr.defines),
    )
    linking_inputs = cc_common.create_linker_input(
        owner = ctx.label,
        user_link_flags = depset(attr.linkopts),
    )
    linking_context = cc_common.create_linking_context(
        linker_inputs = depset([linking_inputs]),
    )
    cc_info = CcInfo(
        compilation_context = compilation_context,
        linking_context = linking_context,
    )
    cc_info_list = [cc_info]
    trans_pcms_list = []
    trans_srcs_list = []
    for dep in deps:
        if CcInfo in dep:
            cc_info_list.append(dep[CcInfo])
        if ModuleInfo in dep:
            trans_pcms_list.append(dep[ModuleInfo].transitive_pcms)
            trans_srcs_list.append(dep[ModuleInfo].transitive_srcs)
    cc_info = cc_common.merge_cc_infos(cc_infos = cc_info_list)

    # print(module_info_list)
    # module_files = depset([], transitive = module_info_list)
    return (cc_info, trans_pcms_list, trans_srcs_list)

def _run_pcm_action(ctx, src, cc_info, pcms_list, srcs_list):
    cc_toolchain = find_cpp_toolchain(ctx)
    compilation_context = cc_info.compilation_context

    src_label = src.label
    src = src.files.to_list()[0]
    pcm_path = src_label.name + ".pcm"
    pcm = ctx.actions.declare_file(pcm_path)
    cxxopts = ctx.fragments.cpp.copts + ctx.fragments.cpp.cxxopts
    cxxopts += ["-fmodule-file=" + pcm.path for pcm in pcms_list]
    inputs = compilation_context.headers.to_list() + compilation_context.direct_headers

    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    compiler_path = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = CPP_MODULE_CODEGEN_ACTION_NAME,
    )
    compile_variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = cxxopts,
        source_file = src.path,
        output_file = pcm.path,
        include_directories = compilation_context.includes,
        system_include_directories = compilation_context.system_includes,
        # quote_include_directories = compilation_context.quote_includes,
    )
    command_line = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = CPP_MODULE_CODEGEN_ACTION_NAME,
        variables = compile_variables,
    )
    env = cc_common.get_environment_variables(
        feature_configuration = feature_configuration,
        action_name = CPP_MODULE_CODEGEN_ACTION_NAME,
        variables = compile_variables,
    )
    c_index = command_line.index("-c")
    module_codegen = ["--precompile", "-x", "c++-module"]
    command_line = command_line[:c_index] + module_codegen + command_line[c_index + 1:]

    # compiler_path = "pwd"
    # command_line = []
    ctx.actions.run(
        executable = compiler_path,
        arguments = command_line,
        env = env,
        inputs = depset(
            [src] + pcms_list + srcs_list + inputs,
            transitive = [cc_toolchain.all_files],
        ),
        outputs = [pcm],
    )
    return (pcm, src)

def _run_obj_action(ctx, src, pcm, cc_info, pcms_list, srcs_list, use_pic):
    cc_toolchain = find_cpp_toolchain(ctx)
    compilation_context = cc_info.compilation_context

    src_label = src.label
    src = src.files.to_list()[0]
    obj_path = src_label.name + (".o" if use_pic else ".pic.o")
    obj = ctx.actions.declare_file(obj_path)

    cxxopts = ctx.fragments.cpp.copts + ctx.fragments.cpp.cxxopts
    cxxopts += ["-fmodule-file=" + pcm.path for pcm in pcms_list]
    inputs = compilation_context.framework_includes.to_list() + compilation_context.includes.to_list()

    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    compiler_path = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = CPP_COMPILE_ACTION_NAME,
    )
    compile_variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        user_compile_flags = cxxopts,
        # there are still some errors of created obj from pcm
        # source_file = pcm.path,
        source_file = src.path,
        output_file = obj.path,
        include_directories = compilation_context.includes,
        system_include_directories = compilation_context.system_includes,
        # quote_include_directories = compilation_context.quote_includes,
        use_pic = use_pic,
    )
    command_line = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = CPP_COMPILE_ACTION_NAME,
        variables = compile_variables,
    )
    env = cc_common.get_environment_variables(
        feature_configuration = feature_configuration,
        action_name = CPP_COMPILE_ACTION_NAME,
        variables = compile_variables,
    )
    # print([pcm, src] + pcms_list + srcs_list)
    
    # compiler_path = "pwd"
    # command_line = []
    ctx.actions.run(
        executable = compiler_path,
        arguments = command_line,
        env = env,
        inputs = depset(
            [pcm, src] + pcms_list + srcs_list + inputs,
            transitive = [cc_toolchain.all_files],
        ),
        outputs = [obj],
    )

    return obj

def _run_lib_action(ctx, obj_list, pic_obj_list):
    cc_toolchain = find_cpp_toolchain(ctx)

    compilation_outputs = cc_common.create_compilation_outputs(objects = depset(obj_list), pic_objects = depset(pic_obj_list))

    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    linking_context, linking_outputs = cc_common.create_linking_context_from_compilation_outputs(
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = compilation_outputs,
        name = ctx.label.name,
    )

    # linking_outputs.library_to_link)
    linker_input = cc_common.create_linker_input(
        owner = ctx.label,
        libraries = depset([linking_outputs.library_to_link]),
    )
    linking_context = cc_common.create_linking_context(
        linker_inputs = depset([linker_input]),
    )

    compilation_context = cc_common.create_compilation_context()
    cc_info = CcInfo(
        compilation_context = compilation_context,
        linking_context = linking_context,
    )
    return cc_info

def _impl(ctx):
    cc_toolchain = find_cpp_toolchain(ctx)
    cc_info, trans_pcms_list, trans_srcs_list = _get_cc_info(ctx, ctx.attr.deps)
    pcms_list = depset([], transitive = trans_pcms_list).to_list()
    srcs_list = depset([], transitive = trans_srcs_list).to_list()
    my_pcms_list = []
    my_srcs_list = []
    obj_list = []
    pic_obj_list = []
    for src in ctx.attr.srcs:
        pcm, src_file = _run_pcm_action(ctx, src, cc_info, pcms_list, srcs_list)
        my_pcms_list.append(pcm)
        my_srcs_list.append(src_file)
        obj_list.append(_run_obj_action(ctx, src, pcm, cc_info, pcms_list, srcs_list, use_pic = False))
        pic_obj_list.append(_run_obj_action(ctx, src, pcm, cc_info, pcms_list, srcs_list, use_pic = True))

    for src in ctx.attr.ordered_srcs:
        all_pcms_list = pcms_list + my_pcms_list
        all_srcs_list = srcs_list + my_srcs_list
        pcm, src_file = _run_pcm_action(ctx, src, cc_info, all_pcms_list, all_srcs_list)
        my_pcms_list.append(pcm)
        my_srcs_list.append(src_file)

        obj_list.append(_run_obj_action(ctx, src, pcm, cc_info, all_pcms_list, all_srcs_list, use_pic = False))
        pic_obj_list.append(_run_obj_action(ctx, src, pcm, cc_info, all_pcms_list, all_srcs_list, use_pic = True))

    # module_ = depset(pcms_list, transitive = [module_files])
    new_cc_info = _run_lib_action(ctx, obj_list, pic_obj_list)
    cc_info = cc_common.merge_cc_infos(cc_infos = [cc_info, new_cc_info])

    return [
        cc_info,
        DefaultInfo(files = depset(my_pcms_list + obj_list + pic_obj_list)),
        ModuleInfo(
            transitive_pcms = depset(my_pcms_list, transitive = trans_pcms_list),
            transitive_srcs = depset(my_srcs_list, transitive = trans_srcs_list),
        ),
    ]

cc_module_library = rule(
    implementation = _impl,
    attrs = {
        "srcs": attr.label_list(mandatory = False, allow_files = True, default = []),
        "ordered_srcs": attr.label_list(mandatory = False, allow_files = True, default = []),
        "deps": attr.label_list(mandatory = False, allow_files = True, default = []),
        "defines": attr.label_list(mandatory = False, default = []),
        "linkopts": attr.label_list(mandatory = False, default = []),
        "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
    },
    fragments = ["cpp"],
)
