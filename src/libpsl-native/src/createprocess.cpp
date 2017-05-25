#include "createprocess.h"

#include <assert.h>
#include <errno.h>
#include <limits>
#include <limits.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <syslog.h>
#include <unistd.h>

enum
{
    CREATE_NEW_PROCESS_SESSION = 0x00000001
};

enum
{
    READ_END_OF_PIPE = 0,
    WRITE_END_OF_PIPE = 1
};

static void CloseIfOpen(int fd)
{
    if (fd >= 0)
    {
        close(fd); // Ignoring errors from close is a deliberate choice
    }
}

// Checks if the IO operation was interrupted and needs to be retried.
// Returns true if the operation was interrupted; otherwise, false.
template <typename TInt>
static inline bool CheckInterrupted(TInt result)
{
    return result < 0 && errno == EINTR;
}

static int Dup2WithInterruptedRetry(int oldfd, int newfd)
{
    int result;
    while (CheckInterrupted(result = dup2(oldfd, newfd)));
    return result;
}

int32_t ForkAndExecProcess(
    const char* filename,
    char* const argv[],
    char* const envp[],
    const char* cwd,
    int32_t redirectStdin,
    int32_t redirectStdout,
    int32_t redirectStderr,
    int32_t creationFlags,
    int32_t* childPid,
    int32_t* stdinFd,
    int32_t* stdoutFd,
    int32_t* stderrFd)
{
    int success = true;
    int processId = -1;
    int stdinFds[2] = { -1, -1 };
    int stdoutFds[2] = { -1, -1 };
    int stderrFds[2] = { -1, -1 };

    // Validate arguments
    if (nullptr == filename || nullptr == argv || nullptr == envp || nullptr == stdinFd || nullptr == stdoutFd ||
        nullptr == stderrFd || nullptr == childPid)
    {
        assert(false && "null argument.");
        errno = EINVAL;
        success = false;
        goto done;
    }

    if ((redirectStdin & ~1) != 0 || (redirectStdout & ~1) != 0 || (redirectStderr & ~1) != 0)
    {
        assert(false && "Boolean redirect* inputs must be 0 or 1.");
        errno = EINVAL;
        success = false;
        goto done;
    }

    // Make sure we can find and access the executable. exec will do this, of course, but at that point it's already
    // in the child process, at which point it'll translate to the child process' exit code rather than to failing
    // the Start itself.  There's a race condition here, in that this could change prior to exec's checks, but there's
    // little we can do about that. There are also more rigorous checks exec does, such as validating the executable
    // format of the target; such errors will emerge via the child process' exit code.
    if (access(filename, X_OK) != 0)
    {
        success = false;
        goto done;
    }

    // Open pipes for any requests to redirect stdin/stdout/stderr
    if ((redirectStdin && pipe(stdinFds) != 0) || (redirectStdout && pipe(stdoutFds) != 0) ||
        (redirectStderr && pipe(stderrFds) != 0))
    {
        success = false;
        goto done;
    }

    // Fork the child process
    if ((processId = fork()) == -1)
    {
        success = false;
        goto done;
    }

    if (processId == 0) // processId == 0 if this is child process
    {
        // Close the child's copy of the parent end of any open pipes
        CloseIfOpen(stdinFds[WRITE_END_OF_PIPE]);
        CloseIfOpen(stdoutFds[READ_END_OF_PIPE]);
        CloseIfOpen(stderrFds[READ_END_OF_PIPE]);

        // For any redirections that should happen, dup the pipe descriptors onto stdin/out/err.
        // Then close out the old pipe descriptors, which we no longer need.
        if ((redirectStdin && Dup2WithInterruptedRetry(stdinFds[READ_END_OF_PIPE], STDIN_FILENO) == -1) ||
            (redirectStdout && Dup2WithInterruptedRetry(stdoutFds[WRITE_END_OF_PIPE], STDOUT_FILENO) == -1) ||
            (redirectStderr && Dup2WithInterruptedRetry(stderrFds[WRITE_END_OF_PIPE], STDERR_FILENO) == -1))
        {
            _exit(errno != 0 ? errno : EXIT_FAILURE);
        }
        CloseIfOpen(stdinFds[READ_END_OF_PIPE]);
        CloseIfOpen(stdoutFds[WRITE_END_OF_PIPE]);
        CloseIfOpen(stderrFds[WRITE_END_OF_PIPE]);

        // Change to the designated working directory, if one was specified
        if (nullptr != cwd)
        {
            int result;
            while (CheckInterrupted(result = chdir(cwd)));
            if (result == -1)
            {
                _exit(errno != 0 ? errno : EXIT_FAILURE);
            }
        }

        // If CREATE_NEW_PROCESS_SESSION was chosen then set the child process to be in its own
        // session.  The processId, processGroupId, and sessionId will all be the same.
        if (creationFlags & CREATE_NEW_PROCESS_SESSION)
        {
            int result;
            while (CheckInterrupted(result = setsid()));
            if (result == -1)
            {
                _exit(errno != 0 ? errno : EXIT_FAILURE);
            }
        }

        // Finally, execute the new process.  execve will not return if it's successful.
        execve(filename, argv, envp);
        _exit(errno != 0 ? errno : EXIT_FAILURE); // execve failed
    }

    // This is the parent process. processId == pid of the child
    *childPid = processId;
    *stdinFd = stdinFds[WRITE_END_OF_PIPE];
    *stdoutFd = stdoutFds[READ_END_OF_PIPE];
    *stderrFd = stderrFds[READ_END_OF_PIPE];

done:
    int priorErrno = errno;

    // Regardless of success or failure, close the parent's copy of the child's end of
    // any opened pipes.  The parent doesn't need them anymore.
    CloseIfOpen(stdinFds[READ_END_OF_PIPE]);
    CloseIfOpen(stdoutFds[WRITE_END_OF_PIPE]);
    CloseIfOpen(stderrFds[WRITE_END_OF_PIPE]);

    // If we failed, close everything else and give back error values in all out arguments.
    if (!success)
    {
        CloseIfOpen(stdinFds[WRITE_END_OF_PIPE]);
        CloseIfOpen(stdoutFds[READ_END_OF_PIPE]);
        CloseIfOpen(stderrFds[READ_END_OF_PIPE]);

        *stdinFd = -1;
        *stdoutFd = -1;
        *stderrFd = -1;
        *childPid = -1;

        errno = priorErrno;
        return -1;
    }

    return 0;
}
