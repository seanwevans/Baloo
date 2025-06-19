; include/defines.inc

%define SYS_READ        0
%define SYS_WRITE       1
%define SYS_OPEN        2
%define SYS_CLOSE       3
%define SYS_STAT        4
%define SYS_LSEEK       8
%define SYS_MMAP        9

%define SYS_IOCTL       16

%define SYS_ACCESS      21

%define SYS_GETPID      39

%define SYS_EXECVE      59

%define SYS_EXIT        60
%define SYS_KILL        62
%define SYS_UNAME       63

%define SYS_FSYNC       74
%define SYS_TRUNCATE    76
%define SYS_FTRUNCATE   77
%define SYS_GETCWD      79

%define SYS_CHDIR       80
%define SYS_RENAME      82
%define SYS_MKDIR       83
%define SYS_RMDIR       84
%define SYS_LINK        86
%define SYS_UNLINK      87
%define SYS_SYMLINK     88
%define SYS_READLINK    89

%define SYS_CHMOD       90
%define SYS_CHOWN       92
%define SYS_UMASK       95
%define SYS_SYSINFO     99

%define SYS_GETUID      102
%define SYS_GETGID      104
%define SYS_GETEUID     107

%define SYS_GETGROUPS   115

%define SYS_MKNOD       133
%define SYS_STATFS      137

%define SYS_GETHOSTID   142

%define SYS_CHROOT      161
%define SYS_SYNC        162

%define SYS_TIME        201

%define SYS_GETENV      211
%define SYS_GETDENTS64  217

%define SYS_UTIMENSAT   280

%define SYS_GETRANDOM   318

%define BASE64_TABLE   "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
%define BASE32_TABLE   "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

%define AT_FDCWD       -100
%define SEEK_SET        0

%define HOSTID_PATH    "/etc/hostid"

%define STDIN_FILENO    0       ; standard in
%define STDOUT_FILENO   1       ; standard out
%define STDERR_FILENO   2       ; standard error

%define O_RDONLY        0       ; Open for read-only
%define O_WRONLY        1       ; Open for write-only
%define O_RDWR          2       ; Open for read/write
%define O_CREAT         64      ; Open for creation
%define O_EXCL          128     ; Error if file already exists
%define O_TRUNC         512     ; Open for truncating
%define O_APPEND        1024    ; Open for appending

%define S_IFIFO       0o010000  ; FIFO file type
%define S_IRUSR       0o0400    ; Read permission for owner
%define S_IWUSR       0o0200    ; Write permission for owner
%define S_IRGRP       0o0040    ; Read permission for group
%define S_IWGRP       0o0020    ; Write permission for group
%define S_IROTH       0o0004    ; Read permission for others
%define S_IWOTH       0o0002    ; Write permission for others

%define F_OK            0       ; Test for file existence
%define X_OK            1       ; Test for execute permission
%define W_OK            2       ; Test for write permission
%define R_OK            4       ; Test for read permission

%define DIR_MODE      0o700     ; rwx------
%define DEFAULT_MODE  0o644     ; rw-r--r--

%define UT_TYPE_OFF     0       ; short   ut_type;       (Offset 0,   Size 2)
%define UT_PID_OFF      4       ; pid_t   ut_pid;        (Offset 4,   Size 4)
%define UT_LINE_OFF     8       ; char    ut_line[32];   (Offset 8,   Size 32)
%define UT_LINESIZE     32      ; Size of tty line field
%define UT_NAMESIZE     32      ; Size of username field
%define UT_ID_OFF       40      ; char    ut_id[4];      (Offset 40,  Size 4)
%define UT_USER_OFF     44      ; char    ut_user[32];   (Offset 44,  Size 32)
%define UT_HOST_OFF     76      ; char    ut_host[256];  (Offset 76,  Size 256)
%define UT_HOSTSIZE     256     ; Size of hostname field
%define UT_EXIT_OFF     332     ; struct  exit_status;   (Offset 332, Size 4)
%define UT_SESSION_OFF  336     ; int32_t ut_session;    (Offset 336, Size 4)
%define UT_TV_OFF       340     ; struct  timeval32;     (Offset 340, Size 8)
%define UT_ADDR_OFF     348     ; int32_t ut_addr_v6[4]; (Offset 348, Size 16)

%define UTMP_SIZE       384

%define EMPTY           0       ; Record does not contain valid info
%define RUN_LVL         1       ; Change in system run-level
%define BOOT_TIME       2       ; Time of system boot
%define NEW_TIME        3       ; Time after system clock change
%define OLD_TIME        4       ; Time before system clock change
%define INIT_PROCESS    5       ; Process spawned by init
%define LOGIN_PROCESS   6       ; Session leader process for user login
%define USER_PROCESS    7       ; Normal user process
%define DEAD_PROCESS    8       ; Terminated process
%define ACCOUNTING      9

%define EEXIST          17      ; Error number for "File exists"

%define WHITESPACE_TAB  9       ; '\t'
%define WHITESPACE_NL   10      ; '\n'
%define WHITESPACE_SPACE 32     ; ' '
