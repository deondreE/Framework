#import "Basic";
#import "Thread";
#import "Atomics";

Job_Group :: struct {
    counter: s64;
}

Job_Proc :: #type (group: *Job_Group, payload: *void);

Job :: struct {
    proc: Job_Proc;
    payload: *void;
    group: *Job_Group;
}

Job_System :: struct {
    threads: [] Thread;
    job_queue: [..] Job;
    queue_mutex: Mutex;
    job_semaphore: Semaphore;
    should_exit: bool;
}

global_job_system: Job_System;

job_system_init :: (thread_count: int = -1) {
    sys := *global_job_system;
    
    // Default to CPU core count - 1
    actual_count := thread_count;
    if actual_count <= 0 {
        actual_count = 7;
    }

    init(*sys.queue_mutex);
    init(*sys.job_semaphore);

    array_resize(*sys.threads, actual_count);
    for * sys.threads {
        thread_init(it, worker_thread_proc);
        it.data = sys;
        thread_start(it);
    }
}

push_job :: (proc: Job_Proc, payload: *void = null, group: *Job_Group = null) {
    sys := *global_job_system;

    if group {
        atomic_add(*group.counter, 1);
    }

    lock(*sys.queue_mutex);
    job: Job = .{proc, payload, group};
    array_add(*sys.job_queue, job);
    unlock(*sys.queue_mutex);
    
    signal(*sys.job_semaphore);
}

#if OS == .MACOS || OS == .LINUX {
    yield :: () {
        sched_yield();
    }

    #scope_file
    sched_yield :: () -> s32 #foreign libc;
} else #if OS == .WINDOWS {
    yield :: () {
        Sleep(0);
    }

    Sleep :: (ms: u32) -> void #foreign "kernel32";
}

until_for_group :: (group: *Job_Group) {
    if !group return;

    sys := *global_job_system;

    while atomic_read(*group.counter) > 0 {
        job: Job;
        found := false;

        lock(*sys.queue_mutex);
        if sys.job_queue.count > 0 {
            job = sys.job_queue[0];
            array_ordered_remove_by_index(*sys.job_queue, 0);
            found = true;
        }
        unlock(*sys.queue_mutex);

        if found {
            job.proc(job.group, job.payload);
            if job.group {
                atomic_add(*job.group.counter, -1);
            }
        } else {
            reset_temporary_storage();
            yield();
        }
    }
}

worker_thread_proc :: (thread: *Thread) -> s64 {
    sys := cast(*Job_System) thread.data;
    
    while !sys.should_exit {
        wait_for(*sys.job_semaphore); 
        if sys.should_exit break;

        job: Job;
        found := false;

        lock(*sys.queue_mutex);
        if sys.job_queue.count > 0 {
            job = sys.job_queue[0];
            array_ordered_remove_by_index(*sys.job_queue, 0);
            found = true;
        }
        unlock(*sys.queue_mutex);

        if found {
            job.proc(job.group, job.payload);

            if job.group {
                atomic_add(*job.group.counter, -1);
            }
        }

        // INFO: Helps prevent memory block in longer-running loops
        reset_temporary_storage();
    }
   return 0;
}

job_system_shutdown :: () {
    sys := *global_job_system;
    sys.should_exit = true;

    for 1..sys.threads.count {
        signal(*sys.job_semaphore);
    }
    
    for * sys.threads {
        // thread_wait(it);
        thread_deinit(it);
    }
    
    destroy(*sys.queue_mutex);
    destroy(*sys.job_semaphore);
    array_reset(*sys.job_queue);
}
