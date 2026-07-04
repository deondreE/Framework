#import "Basic";
#import "Compiler";
#import "File";
#import "Process";

copy_file :: (from: string, to: string) -> bool {
    data, success := read_entire_file(from);
    if !success {
        print("Error: could not read %.\n", from);
        return false;
    }
    defer free(data);

    if !write_entire_file(to, data) {
        print("Error: could not write %.\n", to);
        return false;
    }
    return true;
}

#run {
    set_build_options_dc(.{do_output=false});

    make_directory_if_it_does_not_exist("bin");

    print("Staging Metal shader source for runtime compilation...\n");

    if !copy_file("Shaders/default.metal", "bin/default.metal") {
        return;
    }

    // @Todo: Make this copy folder
    if !copy_file("Assets/icon.png", "bin/icon.png") {
        return;
    }

    w := compiler_create_workspace("Metal Framework");
    if !w return;

    options := get_build_options(w);
    options.output_executable_name = "framework_demo";
    options.output_path = "bin/";

    import_paths: [..] string;
    array_add(*import_paths, ..options.import_path);
    array_add(*import_paths, ".");
    options.import_path = import_paths;

    set_build_options(options, w);

    add_build_file("main.jai", w);
}
