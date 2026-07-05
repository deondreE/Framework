#import "Basic";
#import "Compiler";
#import "File_Utilities";
#import "File";
#import "String";
#import "Process";

copy_directory_l :: (source: string, dest: string) -> bool {
    Args :: struct {
        source_name: string;
        dest_root:   string;
        success:     bool = true;
    }
    
    args: Args;
    args.source_name = source;
    args.dest_root   = dest;

    visitor :: (info: *File_Visit_Info, args: *Args) {
        if !args.success return;

        relative_path := info.full_name;
        if starts_with(relative_path, args.source_name) {
            advance(*relative_path, args.source_name.count);
        }
        
        if relative_path.count > 0 && (relative_path[0] == #char "/" || relative_path[0] == #char "\\") {
            advance(*relative_path, 1);
        }

        dest_path := join(args.dest_root, "/", relative_path);
        defer free(dest_path);

        if info.is_directory {
            if !make_directory_if_it_does_not_exist(dest_path, recursive=true) {
                args.success = false;
                info.descend_into_directory = false;
            }
        } else {
            parent_dir := path_strip_filename(dest_path);
            if !make_directory_if_it_does_not_exist(parent_dir, recursive=true) {
                args.success = false;
                return;
            }

            if !copy_file(info.full_name, dest_path) {
                args.success = false;
            }
        }
    }

    if !make_directory_if_it_does_not_exist(dest, recursive=true) return false;
    success := visit_files(source, recursive=true, *args, visitor, visit_directories=true);
    
    return success && args.success;
}

copy_file_l :: (from: string, to: string) -> bool {
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

    if !copy_file_l("Shaders/default.metal", "bin/default.metal") {
        return;
    }

    // @INFO: Copy Assets
    print("Copying asset folders...");
    if !copy_directory_l("Assets", "bin/Assets") {
        print("Error: Could not create Assets folder. \n");
    }
    
    // @Todo: Make this copy folder
//    if !copy_file("Assets/icon.png", "bin/icon.png") {
//       return;
//    }

    w := compiler_create_workspace("Metal Framework");
    if !w return;

    options := get_build_options(w);
    options.output_executable_name = "framework_demo";
    options.output_path = "bin/";
    options.backend = .LLVM;

    import_paths: [..] string;
    array_add(*import_paths, ..options.import_path);
    array_add(*import_paths, ".");
    options.import_path = import_paths;

    set_build_options(options, w);

    add_build_file("main.jai", w);
}
