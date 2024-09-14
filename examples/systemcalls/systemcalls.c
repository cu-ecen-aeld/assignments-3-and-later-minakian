#include "systemcalls.h"

/**
 * @param cmd the command to execute with system()
 * @return true if the command in @param cmd was executed
 *   successfully using the system() call, false if an error occurred,
 *   either in invocation of the system() call, or if a non-zero return
 *   value was returned by the command issued in @param cmd.
*/
bool do_system(const char *cmd)
{
    if (cmd == NULL) {
        fprintf(stderr, "Error: Command is NULL.\n");
        return false;
    }

    // Execute the command using system()
    int ret = system(cmd);

    if (ret == -1) {
        // system() failed to execute
        perror("system");
        return false;
    } else {
        // Check how the command terminated
        if (WIFEXITED(ret)) {
            int exit_status = WEXITSTATUS(ret);
            if (exit_status == 0) {
                // Command executed successfully
                return true;
            } else {
                // Command executed but returned a non-zero exit status
                fprintf(stderr, "Command exited with non-zero status: %d\n", exit_status);
                return false;
            }
        } else if (WIFSIGNALED(ret)) {
            // Command was terminated by a signal
            int term_signal = WTERMSIG(ret);
            fprintf(stderr, "Command was terminated by signal: %d\n", term_signal);
            return false;
        } else {
            // Other cases
            fprintf(stderr, "Command did not terminate normally.\n");
            return false;
        }
    }
}

// Function to check if a path is absolute
bool is_absolute_path(const char *path) {
    if (path == NULL || path[0] != '/') {
        return false;
    }
    return true;
}

/**
* @param count -The numbers of variables passed to the function. The variables are command to execute.
*   followed by arguments to pass to the command
*   Since exec() does not perform path expansion, the command to execute needs
*   to be an absolute path.
* @param ... - A list of 1 or more arguments after the @param count argument.
*   The first is always the full path to the command to execute with execv()
*   The remaining arguments are a list of arguments to pass to the command in execv()
* @return true if the command @param ... with arguments @param arguments were executed successfully
*   using the execv() call, false if an error occurred, either in invocation of the
*   fork, waitpid, or execv() command, or if a non-zero return value was returned
*   by the command issued in @param arguments with the specified arguments.
*/

bool do_exec(int count, ...)
{
    va_list args;
    va_start(args, count);
    
    // Allocate memory for command arguments
    // VLAs are not supported in C90 or C++, so we use malloc instead
    char **command = malloc((count + 1) * sizeof(char *));
    if (command == NULL) {
        perror("malloc");
        va_end(args);
        return false;
    }

    // Collect the command and its arguments
    for(int i = 0; i < count; i++)
    {
        command[i] = va_arg(args, char *);
    }
    command[count] = NULL; // Null-terminate the argument list

    // Verify that command[0] is an absolute path
    if (!is_absolute_path(command[0])) {
        fprintf(stderr, "Error: Command must be an absolute path.\n");
        free(command);
        va_end(args);
        return false;
    }

    pid_t pid = fork();
    if (pid == -1)
    {
        perror("fork");
        free(command);
        va_end(args);
        return false;
    }
    else if (pid == 0)
    {
        // Child process
        execv(command[0], command);
        // If execv returns, an error occurred
        perror("execv");
        _exit(EXIT_FAILURE); // Use _exit to terminate immediately
    }
    else
    {
        // Parent process
        int status;
        if (waitpid(pid, &status, 0) == -1)
        {
            perror("waitpid");
            free(command);
            va_end(args);
            return false;
        }

        // Check if the child terminated normally and exited with status 0
        if (WIFEXITED(status) && WEXITSTATUS(status) == 0)
        {
            free(command);
            va_end(args);
            return true;
        }
        else
        {
            free(command);
            va_end(args);
            return false;
        }
    }

    // Cleanup (unreachable code, but good practice)
    free(command);
    va_end(args);
    return true;
}

/**
* @param outputfile - The full path to the file to write with command output.
*   This file will be closed at completion of the function call.
* All other parameters, see do_exec above
*/
bool do_exec_redirect(const char *outputfile, int count, ...)
{
    va_list args;
    va_start(args, count);

    // Allocate memory for command arguments (+1 for NULL terminator)
    // VLAs are not supported in C90 or C++, so we use malloc instead
    char **command = malloc((count + 1) * sizeof(char *));
    if (command == NULL) {
        perror("malloc");
        va_end(args);
        return false;
    }

    // Collect the command and its arguments
    for(int i = 0; i < count; i++) {
        command[i] = va_arg(args, char *);
    }
    command[count] = NULL; // Null-terminate the argument list

    // Verify that command[0] is an absolute path
    if (!is_absolute_path(command[0])) {
        fprintf(stderr, "Error: Command must be an absolute path.\n");
        free(command);
        va_end(args);
        return false;
    }

    // Fork a child process
    pid_t pid = fork();
    if (pid == -1) {
        // Fork failed
        perror("fork");
        free(command);
        va_end(args);
        return false;
    }
    else if (pid == 0) {
        // Child process

        // Open the output file with write-only access, create if it doesn't exist, truncate if it does
        int fd = open(outputfile, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd == -1) {
            perror("open");
            _exit(EXIT_FAILURE); // Use _exit to terminate immediately
        }

        // Redirect stdout to the output file
        if (dup2(fd, STDOUT_FILENO) == -1) {
            perror("dup2");
            close(fd);
            _exit(EXIT_FAILURE);
        }

        // Close the original file descriptor as it's no longer needed
        if (close(fd) == -1) {
            perror("close");
            _exit(EXIT_FAILURE);
        }

        // Execute the command
        execv(command[0], command);

        // If execv returns, an error occurred
        perror("execv");
        _exit(EXIT_FAILURE);
    }
    else {
        // Parent process

        int status;
        pid_t wait_result = waitpid(pid, &status, 0);
        if (wait_result == -1) {
            // waitpid failed
            perror("waitpid");
            free(command);
            va_end(args);
            return false;
        }

        // Check if the child terminated normally and exited with status 0
        if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
            // Success
            free(command);
            va_end(args);
            return true;
        }
        else {
            // Child exited with an error or did not terminate normally
            if (WIFEXITED(status)) {
                fprintf(stderr, "Command exited, status: %d\n", WEXITSTATUS(status));
            }
            else if (WIFSIGNALED(status)) {
                fprintf(stderr, "Command terminated, signal: %d\n", WTERMSIG(status));
            }
            free(command);
            va_end(args);
            return false;
        }
    }

    // Cleanup (just in case)
    free(command);
    va_end(args);
    return false;
}
